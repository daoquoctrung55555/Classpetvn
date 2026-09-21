const SUPABASE_URL = "https://tyrwtmnxeblpktuutlta.supabase.co";

const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_Gmcm7kEfywP1feyAdVF4Xw_CNDvnwwC";

const supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY
);

// JavaScript của ClassPet được tải inline trong index.html.
// File này được giữ để chuẩn bị tách toàn bộ logic sang script.js.

async function testSupabase() {
  const { data, error } = await supabaseClient
    .from("classes")
    .select("*");

  if (error) {
    console.error("❌ Supabase lỗi:", error);
  } else {
    console.log("✅ Supabase đã kết nối!");
    console.log("Dữ liệu classes:", data);
  }
}

testSupabase();
