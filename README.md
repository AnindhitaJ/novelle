# Novelle

Studio menulis novel pribadi untuk satu pemilik. Situs statis (tanpa server dan tanpa proses build) + Supabase. Semua berkas ada di satu level, tanpa folder.

## Isi
| Berkas | Fungsi |
|---|---|
| `index.html`, `app.js` | Aplikasi |
| `config.js` | **Satu-satunya yang perlu kamu edit**: URL dan anon key Supabase |
| `schema.sql` | Skema database, RLS, dan fungsi simpan. Dijalankan sekali di Supabase |
| `sw.js`, `manifest.webmanifest`, `icon-*.png` | PWA (bisa diinstal, shell tersedia offline) |
| `vercel.json` | Header keamanan (CSP) untuk Vercel; diabaikan di host lain |

## Pasang (sekitar 10 menit)
1. **Supabase**: buat proyek. Di *Authentication → Sign In / Providers*, **matikan "Allow new users to sign up"**.
2. *SQL Editor*: tempel seluruh isi `schema.sql`, lalu Run.
3. *Authentication → Users → Add user*: isi email pemilik dan kata sandi kuat (centang auto-confirm). Salin **UUID** user itu.
4. *SQL Editor*: `insert into public.app_config (owner_id) values ('UUID-PEMILIK');`
5. *Project Settings → API*: salin **Project URL** dan **anon public key** ke `config.js`. Jangan memakai kunci `service_role`.
6. **Upload ke GitHub**: buat repo, klik *Add file → Upload files*, seret semua berkas ini, commit.
7. **Deploy**: impor repo di Vercel (Framework Preset: *Other*, kosongkan Build Command). GitHub Pages juga bisa.
8. *Supabase → Authentication → URL Configuration*: isi **Site URL** dan **Redirect URLs** dengan alamat situsmu (mis. `https://novelle.vercel.app/`). Ini dipakai tautan pemulihan kata sandi.

## Fitur
Login pemilik (tanpa pendaftaran), pemulihan kata sandi, perpustakaan novel (bahasa naskah Indonesia/English), editor (tebal, miring, garis bawah, coret, judul, urungkan, ukuran dan lebar teks, mode fokus, ejaan bawaan browser `id-ID`), bab (tambah, ganti judul, urutkan, hapus), autosave ke IndexedDB lalu Supabase dengan nomor revisi dan layar konflik, riwayat revisi dan pemulihan, karakter (alias, gaya bicara, kata yang dihindari), Cek Tulisan Indonesia (ejaan, tata bahasa dan tanda baca, gaya, kontinuitas), ekspor TXT/Markdown/JSON, PWA.

## Keamanan
- Tidak ada pendaftaran: sign-up dimatikan, dan setelah `app_config` terisi sebuah trigger menolak pembuatan akun lain lewat jalur apa pun.
- Penegak aksesnya adalah **database** (RLS dengan `is_owner()` di semua tabel dan fungsi). Karena ini situs statis, tidak ada pemeriksaan di sisi server hosting; layar login hanya menentukan apa yang ditampilkan. Orang yang bukan pemilik tetap tidak bisa membaca atau menulis data walau tahu ID novel.
- Anon key di `config.js` memang publik. Yang tidak boleh bocor adalah `service_role` dan kata sandimu.
- Naskah tidak dikirim ke layanan lain: pemeriksaan tulisan dan ekspor berjalan di browser; satu-satunya tujuan jaringan adalah Supabase milikmu.
- Keluar akun menghapus draf dan cache lokal dari perangkat (dengan peringatan bila ada yang belum tersinkron).

## Batasan
- `app.js` adalah hasil kompilasi; kode sumbernya tidak ikut di berkas ini.
- Offline: aplikasi bisa dibuka dan tulisan di bab yang sedang dibuka aman di perangkat lalu tersinkron saat online. Perpustakaan dan daftar bab tidak tersimpan offline.
- Belum ada: relasi karakter, lokasi, worldbuilding, outline/adegan, linimasa, benang plot, target menulis harian, perbandingan dua revisi, DOCX/EPUB, UI kamus pribadi.
- Pemeriksaan tulisan berbasis aturan dan heuristik, bukan pemeriksa tata bahasa lengkap. Ejaan bawaan browser bergantung pada browser dan sistem operasi.
- Login dan penyimpanan belum diuji terhadap proyek Supabase sungguhan oleh pembuatnya. Skema dan RLS sudah diuji di PostgreSQL lokal; tampilan awal dan layar login sudah dijalankan di jsdom.
