-- Novelle UPDATE 1. Jalankan SEKALI di Supabase -> SQL Editor pada database yang sudah memakai versi sebelumnya,
-- SEBELUM mengganti app.js dan index.html. Menambah: Sampah 30 hari, target menulis harian, lokasi, relasi karakter, outline, linimasa, benang plot.

-- Novelle update 1: sampah 30 hari (soft delete), target menulis harian, dan data cerita
-- (lokasi, relasi karakter, adegan/outline, linimasa, benang plot). Aman dijalankan sekali pada database yang sudah memakai 0001-0004.

-- ---------- sampah: hapus lunak 30 hari ----------
alter table public.novels   add column deleted_at timestamptz;
alter table public.chapters add column deleted_at timestamptz;
create index novels_active_idx   on public.novels   (user_id, updated_at desc) where deleted_at is null;
create index chapters_active_idx on public.chapters (novel_id, position)       where deleted_at is null;
grant update (deleted_at) on public.chapters to authenticated;   -- isi bab tetap hanya lewat save_chapter()

create or replace function public.purge_trash() returns int
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int; m int;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  delete from public.chapters where user_id = uid and deleted_at < now() - interval '30 days';
  get diagnostics n = row_count;
  delete from public.novels where user_id = uid and deleted_at < now() - interval '30 days';
  get diagnostics m = row_count;
  return n + m;
end $$;
revoke all on function public.purge_trash() from public, anon;
grant execute on function public.purge_trash() to authenticated;

-- ---------- target harian: hanya kata BARU yang ditulis (penambahan), tidak dihitung ulang dari isi naskah ----------
create table public.writing_days (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null,
  words_added int not null default 0 check (words_added >= 0),
  primary key (user_id, day)
);
alter table public.writing_days enable row level security;
create policy writing_days_select on public.writing_days for select using (user_id = (select auth.uid()) and (select public.is_owner()));
-- tidak ada policy tulis: penambahan hanya lewat add_words()

create or replace function public.add_words(p_day date, p_words int) returns int
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); total int;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_words <= 0 or p_words > 50000 then raise exception 'jumlah kata tidak wajar' using errcode = '22023'; end if;
  if p_day not between current_date - 2 and current_date + 2 then raise exception 'tanggal tidak wajar' using errcode = '22023'; end if;
  insert into public.writing_days (user_id, day, words_added) values (uid, p_day, p_words)
  on conflict (user_id, day) do update set words_added = public.writing_days.words_added + excluded.words_added
  returning words_added into total;
  return total;
end $$;
revoke all on function public.add_words(date, int) from public, anon;
grant execute on function public.add_words(date, int) to authenticated;

-- ---------- lokasi ----------
create table public.locations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  novel_id uuid not null,
  name text not null check (char_length(name) between 1 and 120),
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  foreign key (novel_id, user_id) references public.novels (id, user_id) on delete cascade
);
create index locations_novel_idx on public.locations (novel_id, name);

-- ---------- relasi karakter ----------
create table public.character_relationships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  novel_id uuid not null,
  a_id uuid not null,
  b_id uuid not null,
  rel_type text not null check (char_length(rel_type) between 1 and 80),
  status text not null default '',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (a_id <> b_id),
  foreign key (novel_id, user_id) references public.novels (id, user_id) on delete cascade,
  foreign key (a_id, user_id) references public.characters (id, user_id) on delete cascade,
  foreign key (b_id, user_id) references public.characters (id, user_id) on delete cascade
);
create index relationships_novel_idx on public.character_relationships (novel_id);

-- ---------- adegan / outline (tabel scenes sudah ada dari 0001) ----------
alter table public.scenes add column pov_id uuid;
alter table public.scenes add column location_id uuid;
alter table public.scenes add foreign key (pov_id, user_id) references public.characters (id, user_id) on delete set null (pov_id);
alter table public.scenes add foreign key (location_id, user_id) references public.locations (id, user_id) on delete set null (location_id);

-- ---------- linimasa ----------
create table public.timeline_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  novel_id uuid not null,
  title text not null check (char_length(title) between 1 and 200),
  when_label text not null default '',              -- waktu dalam cerita, bebas (tidak dipaksa kalender Masehi)
  position numeric not null,                        -- urutan kronologis
  location_id uuid,
  chapter_id uuid,
  character_ids uuid[] not null default '{}',       -- id karakter yang terlibat; id yang sudah dihapus ditampilkan sebagai "(dihapus)"
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (novel_id, user_id) references public.novels (id, user_id) on delete cascade,
  foreign key (location_id, user_id) references public.locations (id, user_id) on delete set null (location_id),
  foreign key (chapter_id, user_id) references public.chapters (id, user_id) on delete set null (chapter_id)
);
create index timeline_novel_idx on public.timeline_events (novel_id, position);

-- ---------- benang plot ----------
create table public.plot_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  novel_id uuid not null,
  title text not null check (char_length(title) between 1 and 200),
  status text not null default 'open' check (status in ('open','resolved')),
  note text not null default '',
  planted_chapter_id uuid,
  payoff_chapter_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (novel_id, user_id) references public.novels (id, user_id) on delete cascade,
  foreign key (planted_chapter_id, user_id) references public.chapters (id, user_id) on delete set null (planted_chapter_id),
  foreign key (payoff_chapter_id, user_id) references public.chapters (id, user_id) on delete set null (payoff_chapter_id)
);
create index threads_novel_idx on public.plot_threads (novel_id);

do $$ declare t text; begin
  foreach t in array array['locations','character_relationships','timeline_events','plot_threads'] loop
    execute format('create trigger %I_updated before update on public.%I for each row execute function public.set_updated_at()', t, t);
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select using (user_id = (select auth.uid()) and (select public.is_owner()))', t || '_select', t);
    execute format('create policy %I on public.%I for insert with check (user_id = (select auth.uid()) and (select public.is_owner()))', t || '_insert', t);
    execute format('create policy %I on public.%I for update using (user_id = (select auth.uid()) and (select public.is_owner())) with check (user_id = (select auth.uid()) and (select public.is_owner()))', t || '_update', t);
    execute format('create policy %I on public.%I for delete using (user_id = (select auth.uid()) and (select public.is_owner()))', t || '_delete', t);
  end loop;
end $$;
