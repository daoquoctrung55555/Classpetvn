-- ClassPet security and atomic deletion migration
-- Review and run in Supabase SQL Editor before deploying frontend changes.
-- No existing records are deleted by this migration.

begin;

-- Remove every policy granting access to PUBLIC or anon on protected tables.
-- Student portal access is provided only through the narrowly scoped SECURITY DEFINER RPCs.
do $migration$
declare
  pol record;
begin
  for pol in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'classes', 'students', 'pets', 'tasks', 'activities',
        'task_completions', 'pet_feed_logs', 'student_reward_logs'
      )
      and ('public' = any(roles) or 'anon' = any(roles))
  loop
    execute format('drop policy if exists %I on %I.%I', pol.policyname, pol.schemaname, pol.tablename);
  end loop;
end;
$migration$;

-- Remove broad public access policies. Student access must go through the
-- existing student_* SECURITY DEFINER RPCs, never direct table reads.
drop policy if exists "Allow public read activities" on public.activities;
drop policy if exists "Allow public insert activities" on public.activities;
drop policy if exists "Allow public read classes" on public.classes;
drop policy if exists "Allow public insert classes" on public.classes;
drop policy if exists "Public can find class by code" on public.classes;
drop policy if exists "Allow public read students" on public.students;
drop policy if exists "Allow public insert students" on public.students;
drop policy if exists "Allow public read pets" on public.pets;
drop policy if exists "Allow public insert pets" on public.pets;
drop policy if exists "Allow public read tasks" on public.tasks;
drop policy if exists "Allow public insert tasks" on public.tasks;

-- Teacher-owned class access.
drop policy if exists "Teachers can read own classes" on public.classes;
drop policy if exists "Teachers can insert own classes" on public.classes;
drop policy if exists "Teachers can update own classes" on public.classes;
drop policy if exists "Teachers can delete own classes" on public.classes;
create policy "Teachers can read own classes" on public.classes
  for select to authenticated using (teacher_id = auth.uid());
create policy "Teachers can insert own classes" on public.classes
  for insert to authenticated with check (teacher_id = auth.uid());
create policy "Teachers can update own classes" on public.classes
  for update to authenticated using (teacher_id = auth.uid())
  with check (teacher_id = auth.uid());
create policy "Teachers can delete own classes" on public.classes
  for delete to authenticated using (teacher_id = auth.uid());

-- Students are visible and manageable only by the teacher who owns their class.
drop policy if exists "Teachers can read students in own classes" on public.students;
drop policy if exists "Teachers can insert students in own classes" on public.students;
drop policy if exists "Teachers can update students in own classes" on public.students;
create policy "Teachers can read students in own classes" on public.students
  for select to authenticated using (
    exists (select 1 from public.classes c
      where c.id = students.class_id and c.teacher_id = auth.uid())
  );
create policy "Teachers can insert students in own classes" on public.students
  for insert to authenticated with check (
    exists (select 1 from public.classes c
      where c.id = students.class_id and c.teacher_id = auth.uid())
  );
create policy "Teachers can update students in own classes" on public.students
  for update to authenticated using (
    exists (select 1 from public.classes c
      where c.id = students.class_id and c.teacher_id = auth.uid())
  ) with check (
    exists (select 1 from public.classes c
      where c.id = students.class_id and c.teacher_id = auth.uid())
  );

-- Pets inherit ownership through students -> classes.
drop policy if exists "Teachers can read pets in own classes" on public.pets;
drop policy if exists "Teachers can insert pets in own classes" on public.pets;
create policy "Teachers can read pets in own classes" on public.pets
  for select to authenticated using (
    exists (select 1 from public.students s join public.classes c on c.id = s.class_id
      where s.id = pets.student_id and c.teacher_id = auth.uid())
  );
create policy "Teachers can insert pets in own classes" on public.pets
  for insert to authenticated with check (
    exists (select 1 from public.students s join public.classes c on c.id = s.class_id
      where s.id = pets.student_id and c.teacher_id = auth.uid())
  );

-- Pets need teacher update/delete rights for feeding, status changes and pet removal.
drop policy if exists "Teachers can update pets in own classes" on public.pets;
drop policy if exists "Teachers can delete pets in own classes" on public.pets;
create policy "Teachers can update pets in own classes" on public.pets
  for update to authenticated using (
    exists (select 1 from public.students s join public.classes c on c.id = s.class_id
      where s.id = pets.student_id and c.teacher_id = auth.uid())
  ) with check (
    exists (select 1 from public.students s join public.classes c on c.id = s.class_id
      where s.id = pets.student_id and c.teacher_id = auth.uid())
  );
create policy "Teachers can delete pets in own classes" on public.pets
  for delete to authenticated using (
    exists (select 1 from public.students s join public.classes c on c.id = s.class_id
      where s.id = pets.student_id and c.teacher_id = auth.uid())
  );

-- Tasks belong directly to a class.
drop policy if exists "Teachers can read tasks in own classes" on public.tasks;
drop policy if exists "Teachers can insert tasks in own classes" on public.tasks;
create policy "Teachers can read tasks in own classes" on public.tasks
  for select to authenticated using (
    exists (select 1 from public.classes c
      where c.id = tasks.class_id and c.teacher_id = auth.uid())
  );
create policy "Teachers can insert tasks in own classes" on public.tasks
  for insert to authenticated with check (
    exists (select 1 from public.classes c
      where c.id = tasks.class_id and c.teacher_id = auth.uid())
  );

-- Teachers may remove tasks only from their own classes.
drop policy if exists "Teachers can delete tasks in own classes" on public.tasks;
create policy "Teachers can delete tasks in own classes" on public.tasks
  for delete to authenticated using (
    exists (select 1 from public.classes c
      where c.id = tasks.class_id and c.teacher_id = auth.uid())
  );

-- Teacher dashboard reads task completion state for tasks in owned classes.
drop policy if exists "Teachers can read task completions in own classes" on public.task_completions;
create policy "Teachers can read task completions in own classes" on public.task_completions
  for select to authenticated using (
    exists (
      select 1 from public.tasks t
      join public.classes c on c.id = t.class_id
      where t.id = task_completions.task_id and c.teacher_id = auth.uid()
    )
  );

-- Activities: teacher-only direct access, scoped to owned classes.
drop policy if exists "Teachers can read activities in own classes" on public.activities;
drop policy if exists "Teachers can insert activities in own classes" on public.activities;
create policy "Teachers can read activities in own classes" on public.activities
  for select to authenticated using (
    exists (select 1 from public.classes c
      where c.id = activities.class_id and c.teacher_id = auth.uid())
  );
create policy "Teachers can insert activities in own classes" on public.activities
  for insert to authenticated with check (
    exists (select 1 from public.classes c
      where c.id = activities.class_id and c.teacher_id = auth.uid())
  );

-- Reward history: validate that class, student and pet all belong together.
drop policy if exists "Teachers can read reward logs in own classes" on public.student_reward_logs;
drop policy if exists "Teachers can insert reward logs in own classes" on public.student_reward_logs;
create policy "Teachers can read reward logs in own classes" on public.student_reward_logs
  for select to authenticated using (
    exists (
      select 1
      from public.classes c
      join public.students s on s.class_id = c.id
      join public.pets p on p.student_id = s.id
      where c.id = student_reward_logs.class_id
        and s.id = student_reward_logs.student_id
        and p.id = student_reward_logs.pet_id
        and c.teacher_id = auth.uid()
    )
  );
create policy "Teachers can insert reward logs in own classes" on public.student_reward_logs
  for insert to authenticated with check (
    exists (
      select 1
      from public.classes c
      join public.students s on s.class_id = c.id
      join public.pets p on p.student_id = s.id
      where c.id = student_reward_logs.class_id
        and s.id = student_reward_logs.student_id
        and p.id = student_reward_logs.pet_id
        and c.teacher_id = auth.uid()
    )
  );

-- Atomic student deletion. FK CASCADE removes pets and dependent logs in one transaction.
create or replace function public.teacher_delete_student(p_student_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted uuid;
begin
  if auth.uid() is null then
    raise exception 'Bạn cần đăng nhập giáo viên.';
  end if;

  delete from public.students s
  using public.classes c
  where s.id = p_student_id
    and c.id = s.class_id
    and c.teacher_id = auth.uid()
  returning s.id into v_deleted;

  if v_deleted is null then
    raise exception 'Không tìm thấy học sinh hoặc bạn không có quyền xóa.';
  end if;

  return jsonb_build_object('success', true, 'student_id', v_deleted);
end;
$$;

-- Atomic class deletion. All dependent records follow the existing FK CASCADE rules.
create or replace function public.teacher_delete_class(p_class_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted uuid;
begin
  if auth.uid() is null then
    raise exception 'Bạn cần đăng nhập giáo viên.';
  end if;

  delete from public.classes c
  where c.id = p_class_id
    and c.teacher_id = auth.uid()
  returning c.id into v_deleted;

  if v_deleted is null then
    raise exception 'Không tìm thấy lớp hoặc bạn không có quyền xóa.';
  end if;

  return jsonb_build_object('success', true, 'class_id', v_deleted);
end;
$$;

-- Clear class roster/tasks/activity while preserving the class itself.
create or replace function public.teacher_clear_class_data(p_class_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_class_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Bạn cần đăng nhập giáo viên.';
  end if;

  select c.id into v_class_id
  from public.classes c
  where c.id = p_class_id and c.teacher_id = auth.uid()
  for update;

  if v_class_id is null then
    raise exception 'Không tìm thấy lớp hoặc bạn không có quyền xóa dữ liệu.';
  end if;

  delete from public.students where class_id = v_class_id;
  delete from public.tasks where class_id = v_class_id;
  delete from public.activities where class_id = v_class_id;

  return jsonb_build_object('success', true, 'class_id', v_class_id);
end;
$$;

revoke all on function public.teacher_delete_student(uuid) from public, anon;
revoke all on function public.teacher_delete_class(uuid) from public, anon;
revoke all on function public.teacher_clear_class_data(uuid) from public, anon;
grant execute on function public.teacher_delete_student(uuid) to authenticated;
grant execute on function public.teacher_delete_class(uuid) to authenticated;
grant execute on function public.teacher_clear_class_data(uuid) to authenticated;

commit;
