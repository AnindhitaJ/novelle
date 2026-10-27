# Novelle

Studio menulis novel pribadi untuk satu pemilik. Situs statis (tanpa server dan tanpa proses build) + Supabase. Semua berkas ada di satu level, tanpa folder.

## Isi
| Berkas | Fungsi |
|---|---|
| `index.html`, `app.js` | Aplikasi |
| `config.js` | URL dan anon key Supabase (sudah terisi untuk proyekmu) |
| `schema.sql` | Skema lengkap untuk instalasi baru |
| `update-1.sql` | Hanya untuk yang sudah punya database versi sebelumnya |
| `sw.js`, `manifest.webmanifest`, `icon-*.png` | PWA |
| `vercel.json` | Header keamanan (CSP) untuk Vercel; diabaikan di host lain |

## Pasang baru (sekitar 10 menit)
1. **Supabase**: buat proyek. Di *Authentication → Sign In / Providers*, **matikan "Allow new users to sign up"**.
2. *SQL Editor*: tempel seluruh isi `schema.sql`, lalu Run.
3. *Authentication → Users → Add user*: isi email pemilik dan kata sandi kuat (centang auto-confirm). Salin **UUID** user itu.
4. *SQL Editor*: `insert into public.app_config (owner_id) values ('UUID-PEMILIK');`
5. *Project Settings → API*: salin **Project URL** dan **anon public key** ke `config.js`. Jangan memakai kunci `service_role`.
6. **Upload ke GitHub**: buat repo, *Add file → Upload files*, seret semua berkas, commit.
7. **Deploy**: impor repo di Vercel. Pastikan repo hanya berisi berkas di atas (tanpa `package.json` atau sisa Next.js). `vercel.json` memaksa Framework Preset "Other" tanpa build.
8. *Supabase → Authentication → URL Configuration*: isi **Site URL** dan **Redirect URLs** dengan alamat situsmu.

## Memperbarui dari versi sebelumnya
1. **Jalankan `update-1.sql` lebih dulu** di Supabase SQL Editor (sekali saja).
2. Baru ganti `index.html` dan `app.js` di GitHub. Jika urutannya terbalik, aplikasi menampilkan pesan "Database belum diperbarui".
3. Tunggu Vercel *Ready*, lalu Cmd+Shift+R. Bila tampilan lama masih muncul: DevTools → *Application → Service Workers* → Unregister.

## Fitur
- Login pemilik tunggal, pemulihan kata sandi, tanpa pendaftaran.
- Perpustakaan: sampul berwarna, pencarian, target dan progres kata, bahasa naskah per novel.
- Editor: format dasar, urungkan/ulangi, ukuran dan lebar teks, mode fokus, ejaan bawaan browser (`id-ID`), **cari dan ganti** (Ctrl/Cmd+F, semua hasil ditandai, ganti satu atau semua, bisa diurungkan), Ctrl/Cmd+S.
- Autosave ke IndexedDB lalu Supabase dengan nomor revisi, layar konflik, riwayat revisi dan pemulihan.
- **Daftar bab**: judul penuh (dua baris), "522 kata", **seret-dan-lepas** untuk mengurutkan, menu ⋯ (Naik/Turun/Sampah).
- **Sampah 30 hari**: bab dan novel yang dihapus pindah ke Sampah, ada tombol Urungkan, bisa dipulihkan, dihapus permanen otomatis setelah 30 hari atau lewat konfirmasi dua klik.
- **Target harian dan streak** (di header): hanya kata baru yang dihitung, hari mengikuti zona waktu browser, bisa dimatikan.
- **Cek Tulisan Indonesia** (lokal): ejaan, tata bahasa dan tanda baca, gaya, kontinuitas. **Terapkan saran** mengganti teks di editor setelah konfirmasi, dan bisa diurungkan.
- **Karakter** (alias, gaya bicara), **Relasi** (daftar dan grafik), **Lokasi**, **Outline** (daftar, papan, seret untuk mengurutkan, buat bab dari adegan), **Linimasa** (waktu bebas, tanda bentrok), **Benang plot**. Temuan outline, benang plot, dan linimasa ikut muncul di tab Kontinuitas.
- Ekspor TXT, Markdown, JSON (bab di Sampah tidak ikut). PWA, tema terang/gelap/ikuti sistem.

## Keamanan
Akses ditegakkan oleh database (RLS dengan `is_owner()` di semua tabel dan fungsi). Layar login hanya menentukan apa yang ditampilkan. Isi bab hanya bisa berubah lewat `save_chapter()`. Setelah pemilik terdaftar, trigger menolak pembuatan akun lain. Naskah tidak dikirim ke layanan lain; satu-satunya tujuan jaringan adalah Supabase milikmu. Keluar akun menghapus draf dan cache lokal.

## Batasan yang diketahui
- Seret-dan-lepas hanya bekerja dengan mouse di komputer. Di layar sentuh, pakai menu ⋯ → Naik/Turun.
- Cari-ganti mencocokkan teks dalam satu paragraf (tidak lintas paragraf).
- Karakter pada peristiwa linimasa disimpan sebagai daftar id; karakter yang dihapus tampil sebagai "(dihapus)".
- Target harian menghitung penambahan kata, jadi menempel teks panjang ikut terhitung.
- Pemeriksaan tulisan berbasis aturan dan heuristik, bukan pemeriksa tata bahasa lengkap.
- Offline: aplikasi bisa dibuka dan tulisan di bab yang sedang terbuka aman; daftar novel/bab belum tersimpan offline.
- Belum ada: perbandingan dua revisi, DOCX/EPUB, UI kamus pribadi, penyimpanan data cerita offline.
- `app.js` adalah hasil kompilasi; kode sumber tidak ikut di berkas ini.
- Yang sudah diuji: tes unit, tes RLS di PostgreSQL lokal, dan menjalankan aplikasi di jsdom dengan Supabase palsu. Belum diuji di browser sungguhan dan belum terhadap proyek Supabase-mu.

## Jika "Gagal membuat novel"
Profil pemilik belum ada karena user dibuat sebelum skema dijalankan:
```sql
insert into public.profiles (id) select id from auth.users on conflict do nothing;
insert into public.user_preferences (user_id) select id from public.profiles on conflict do nothing;
```
