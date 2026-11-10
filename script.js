const SUPABASE_URL = "https://tyrwtmnxeblpktuutlta.supabase.co";

const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_Gmcm7kEfywP1feyAdVF4Xw_CNDvnwwC";

const supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY
);

// JavaScript của ClassPet được tải inline trong index.html.
// File này được giữ để chuẩn bị tách toàn bộ logic sang script.js.

// Không tự truy vấn dữ liệu lớp khi tải trang.
// Các truy vấn chỉ được thực hiện sau khi người dùng đăng nhập và theo đúng lớp được chọn.
