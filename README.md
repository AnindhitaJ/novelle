# Novelle: sinkronisasi, pemilik tunggal, dan pemeriksaan tulisan Indonesia

## Model akses: satu pemilik
- Tidak ada halaman atau endpoint pendaftaran. Hanya login, logout, dan pemulihan kata sandi.
- Akses dikunci tiga lapis: **middleware** (`src/middleware.ts`), **server** (`requireOwner()` di setiap server action dan route) dan **RLS** (`is_owner()` di semua tabel dan RPC).
- Aplikasi terkunci (HTTP 503) sampai `OWNER_USER_ID` diisi; database tertutup sampai baris `app_config` dibuat.
- Tidak ada service-role key di aplikasi. Kata sandi tidak ada di kode, env, maupun migrasi.

### Menyiapkan akun pemilik (sekali saja)
1. Supabase Dashboard → Authentication → Sign In / Providers → **matikan "Allow new users to sign up"**.
2. Jalankan migrasi `0001`, `0002`, `0003` (SQL Editor atau `supabase db push`).
3. Authentication → Users → **Add user** → isi email pemilik dan kata sandi kuat, centang auto-confirm. Salin **UUID** pengguna itu.
4. SQL Editor: `insert into public.app_config (owner_id) values ('UUID-PEMILIK');`
   Sejak baris ini ada, trigger `block_extra_users` menolak pembuatan akun lain lewat jalur apa pun.
5. Isi env di Vercel (lihat `.env.example`): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SITE_URL`, `OWNER_USER_ID`.
6. Authentication → URL Configuration: Site URL = `NEXT_PUBLIC_SITE_URL`; Redirect URLs = `NEXT_PUBLIC_SITE_URL/auth/callback`.
7. Pastikan email pemilik adalah alamat yang kamu kendalikan: pemulihan kata sandi dikirim ke sana.

Mengganti pemilik: hapus baris `app_config`, buat akun baru, isi baris baru, ubah `OWNER_USER_ID`.

## Bahasa Indonesia
- Bahasa naskah bawaan `id-ID` (`novels.language`), per novel, terpisah dari bahasa antarmuka (`user_preferences.ui_language`). `<html lang="id">` untuk antarmuka; editor memakai `editorAttrs(novel.language)` (`lang`, `spellcheck="true"`).
- **Ejaan** memakai pemeriksa bawaan browser. Kamus dan saran bergantung pada browser dan sistem operasi, sehingga bisa berbeda antarperangkat. Tidak ada teks yang dikirim ke layanan ejaan oleh aplikasi ini. Kata pribadi disimpan di `custom_words`; tidak ada penggantian otomatis.
- **Pemeriksaan aturan** (`src/lib/writing-checks`) berjalan lokal: kata berulang, tanda baca, kutip, duplikasi, spasi, kapital, "di"/"di-", pola ejaan umum, ungkapan berlebihan, kalimat panjang, tanda baca dialog, register, dan pola bicara tokoh.
  Setiap temuan ditandai **objektif** (format), **heuristik** (dugaan), atau **gaya**. Ini bukan pemeriksa tata bahasa lengkap dan tidak memahami makna. Dialog, slang, dan gaya tokoh tidak dipaksa formal.
- **Kontinuitas**: `findMentions()` mengenali nama, alias, dan sapaan (Pak, Bu, Mbak, dst.) tanpa memedulikan huruf besar, mempertahankan diakritik, dan tidak menganggap nama mirip sebagai tokoh yang sama.

## Menjalankan tes
- `npm test`: mesin sinkronisasi, aturan tulisan Indonesia, logika pemilik.
- `npm run typecheck`.
- `DATABASE_URL=... npm run test:rls`: tes RLS pada Postgres kosong (skrip meniru skema `auth`, jangan jalankan pada database Supabase asli).

## Batasan yang diketahui
- Login, middleware, dan alur pemulihan kata sandi lolos typecheck, tetapi belum dijalankan terhadap proyek Supabase dan Next.js sungguhan.
- Peran `service_role` dan `postgres` tetap melewati RLS (sifat Supabase). Pembatasan akun baru bergantung pada trigger dan pengaturan sign-up.
- Daftar ejaan, kata kerja pasif, dan kata tempat bersifat terbatas dan perlu diperluas lewat pemakaian nyata.
