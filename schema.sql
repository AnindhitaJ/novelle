-- Novelle: skema lengkap. Jalankan SEKALI di Supabase -> SQL Editor (seluruh isi berkas ini).
-- Setelah selesai dan user pemilik dibuat: insert into public.app_config (owner_id) values ('UUID-PEMILIK');

-- ===== 0001_novelle_phase1 =====
-- Novelle — Phase 1 foundation: profiles, novels, parts, chapters, scenes, revisions.
-- Ownership model: every table has user_id; children use composite FKs (parent_id, user_id)
-- so a row can never reference another user's parent. RLS restricts all access to auth.uid().

create extension if not exists pgcrypto;

-- ---------- helpers ----------
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;

-- ---------- profiles & preferences ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text check (char_length(display_name) <= 80),
  timezone text not null default 'UTC',
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  theme text not null default 'system' check (theme in ('light','dark','system')),
  editor_font text not null default 'serif',
  editor_font_size int not null default 18 check (editor_font_size between 12 and 32),
  editor_line_height numeric(3,2) not null default 1.7 check (editor_line_height between 1.0 and 3.0),
  editor_width text not null default 'medium' check (editor_width in ('narrow','medium','wide')),
  daily_word_goal int check (daily_word_goal is null or daily_word_goal > 0), -- null = goals disabled
  autosave_delay_ms int not null default 1500 check (autosave_delay_ms between 1000 and 10000),
  updated_at timestamptz not null default now()
);

-- Create profile + preferences automatically on signup.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id);
  insert into public.user_preferences (user_id) values (new.id);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- novels ----------
create table public.novels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 200),
  subtitle text,
  synopsis text,
  genre text,
  tags text[] not null default '{}',
  language text not null default 'en',
  target_word_count int check (target_word_count is null or target_word_count > 0),
  target_chapter_count int check (target_chapter_count is null or target_chapter_count > 0),
  status text not null default 'idea'
    check (status in ('idea','planning','drafting','revising','completed','archived')),
  settings jsonb not null default '{}',
  last_opened_chapter_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);
create index novels_user_updated_idx on public.novels (user_id, updated_at desc);

-- ---------- parts ----------
create table public.parts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  novel_id uuid not null,
  title text not null check (char_length(title) <= 200),
  position numeric not null,                 -- fractional ordering: reorder = 1 row update
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  foreign key (novel_id, user_id) references public.novels (id, user_id) on delete cascade
);
create index parts_novel_pos_idx on public.parts (novel_id, position);

-- ---------- chapters (content kept separate from planning metadata) ----------
create table public.chapters (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  novel_id uuid not null,
  part_id uuid,
  title text not null default 'Untitled chapter' check (char_length(title) <= 200),
  position numeric not null,
  status text not null default 'idea' check (status in ('idea','planned','drafting','revised','final')),
  content jsonb not null default '{"type":"doc","content":[]}',  -- TipTap JSON
  revision int not null default 1,           -- optimistic concurrency token
  last_op_id uuid,                           -- idempotency for retried saves
  word_count int not null default 0 check (word_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  foreign key (novel_id, user_id) references public.novels (id, user_id) on delete cascade,
  foreign key (part_id, user_id) references public.parts (id, user_id) on delete set null (part_id)
);
create index chapters_novel_pos_idx on public.chapters (novel_id, position);

-- ---------- scenes (planning metadata; same identity whether planned or written) ----------
create table public.scenes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  novel_id uuid not null,
  chapter_id uuid,
  title text not null default 'Untitled scene' check (char_length(title) <= 200),
  position numeric not null,
  summary text,
  purpose text,
  conflict text,
  tone text,
  status text not null default 'idea' check (status in ('idea','planned','drafting','revised','final')),
  estimated_word_count int check (estimated_word_count is null or estimated_word_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  foreign key (novel_id, user_id) references public.novels (id, user_id) on delete cascade,
  foreign key (chapter_id, user_id) references public.chapters (id, user_id) on delete set null (chapter_id)
);
create index scenes_novel_pos_idx on public.scenes (novel_id, position);

-- ---------- revisions ----------
create table public.manuscript_revisions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  chapter_id uuid not null,
  chapter_revision int not null,             -- matches chapters.revision at snapshot time
  content jsonb not null,
  word_count int not null,
  reason text not null default 'autosave' check (reason in ('autosave','manual','pre_restore','restore')),
  created_at timestamptz not null default now(),
  foreign key (chapter_id, user_id) references public.chapters (id, user_id) on delete cascade
);
create index revisions_chapter_idx on public.manuscript_revisions (chapter_id, created_at desc);

-- ---------- updated_at triggers ----------
do $$ declare t text; begin
  foreach t in array array['profiles','user_preferences','novels','parts','chapters','scenes'] loop
    execute format('create trigger %I_updated before update on public.%I
      for each row execute function public.set_updated_at()', t, t);
  end loop;
end $$;

-- ---------- Row Level Security ----------
do $$ declare t text; begin
  foreach t in array array['novels','parts','chapters','scenes','manuscript_revisions'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "%1$s_select" on public.%1$I for select using (user_id = (select auth.uid()))', t);
    execute format('create policy "%1$s_insert" on public.%1$I for insert with check (user_id = (select auth.uid()))', t);
    execute format('create policy "%1$s_update" on public.%1$I for update using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
    execute format('create policy "%1$s_delete" on public.%1$I for delete using (user_id = (select auth.uid()))', t);
  end loop;
end $$;

alter table public.profiles enable row level security;
create policy profiles_select on public.profiles for select using (id = (select auth.uid()));
create policy profiles_update on public.profiles for update using (id = (select auth.uid())) with check (id = (select auth.uid()));
-- no insert policy: rows are created by handle_new_user(); delete cascades from auth.users

alter table public.user_preferences enable row level security;
create policy prefs_select on public.user_preferences for select using (user_id = (select auth.uid()));
create policy prefs_update on public.user_preferences for update using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Clients may not forge revision counters or snapshots directly: saves go through save_chapter().
revoke update (revision, last_op_id, content, word_count) on public.chapters from authenticated;
revoke insert, update on public.manuscript_revisions from authenticated;

-- ---------- conflict-safe save ----------
-- SECURITY INVOKER (default): RLS still applies, so a caller can only save their own chapters.
create or replace function public.save_chapter(
  p_chapter_id uuid, p_base_revision int, p_content jsonb,
  p_word_count int, p_op_id uuid, p_force_snapshot boolean default false
) returns table (status text, revision int)
language plpgsql security definer set search_path = public as $$
declare c public.chapters; uid uuid := auth.uid(); last_snap timestamptz;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select * into c from public.chapters where id = p_chapter_id and user_id = uid for update;
  if not found then return query select 'not_found'::text, null::int; return; end if;

  if c.last_op_id = p_op_id then                       -- retried request already applied
    return query select 'ok'::text, c.revision; return;
  end if;
  if c.revision <> p_base_revision then                -- server changed independently
    return query select 'conflict'::text, c.revision; return;
  end if;

  select max(created_at) into last_snap from public.manuscript_revisions where chapter_id = c.id;
  if p_force_snapshot or last_snap is null or last_snap < now() - interval '5 minutes' then
    insert into public.manuscript_revisions (user_id, chapter_id, chapter_revision, content, word_count, reason)
    values (uid, c.id, c.revision, c.content, c.word_count, case when p_force_snapshot then 'manual' else 'autosave' end);
  end if;

  update public.chapters
     set content = p_content, word_count = greatest(p_word_count, 0),
         revision = c.revision + 1, last_op_id = p_op_id
   where id = c.id;
  return query select 'ok'::text, c.revision + 1;
end $$;
revoke all on function public.save_chapter from public, anon;
grant execute on function public.save_chapter to authenticated;

-- Restore: snapshots the current version first, then records the restore as a new revision.
create or replace function public.restore_revision(p_revision_id uuid)
returns table (status text, revision int)
language plpgsql security definer set search_path = public as $$
declare r public.manuscript_revisions; c public.chapters; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select * into r from public.manuscript_revisions where id = p_revision_id and user_id = uid;
  if not found then return query select 'not_found'::text, null::int; return; end if;
  select * into c from public.chapters where id = r.chapter_id and user_id = uid for update;

  insert into public.manuscript_revisions (user_id, chapter_id, chapter_revision, content, word_count, reason)
  values (uid, c.id, c.revision, c.content, c.word_count, 'pre_restore');
  update public.chapters set content = r.content, word_count = r.word_count,
         revision = c.revision + 1, last_op_id = null where id = c.id;
  insert into public.manuscript_revisions (user_id, chapter_id, chapter_revision, content, word_count, reason)
  values (uid, c.id, c.revision + 1, r.content, r.word_count, 'restore');
  return query select 'ok'::text, c.revision + 1;
end $$;
revoke all on function public.restore_revision from public, anon;
grant execute on function public.restore_revision to authenticated;

-- ===== 0002_lock_chapter_columns =====
-- Fix for 0001: a column-level REVOKE does nothing while a table-level UPDATE grant exists
-- (Supabase grants UPDATE on the whole table to `authenticated`). Revoke at table level,
-- then grant back only the metadata columns. Manuscript content, revision, last_op_id and
-- word_count can then change only through save_chapter() / restore_revision().
revoke update on public.chapters from authenticated;
grant update (title, part_id, position, status) on public.chapters to authenticated;

-- ===== 0003_single_owner_and_indonesian =====
-- Novelle: single-owner model + Indonesian-first language settings.
-- Provisioning (see README): create the owner in Supabase Auth manually, then run
--   insert into public.app_config (owner_id) values ('<owner uuid>');
-- Until that row exists, is_owner() is false for everyone and no data is reachable.

create table public.app_config (
  singleton boolean primary key default true check (singleton),   -- at most one row
  owner_id uuid not null references auth.users(id) on delete cascade
);
alter table public.app_config enable row level security;          -- no policies: invisible to API roles
revoke all on public.app_config from anon, authenticated;

create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.app_config where owner_id = (select auth.uid()))
$$;
revoke all on function public.is_owner() from public, anon;
grant execute on function public.is_owner() to authenticated;

-- Defense in depth next to "disable sign-ups" in the Auth dashboard: once an owner is
-- configured, no further auth.users row can be created by any route (signup, OAuth, magic link, invite).
create or replace function public.block_extra_users() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.app_config) then
    raise exception 'Pendaftaran ditutup. Novelle hanya untuk satu pemilik.' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger block_extra_users before insert on auth.users
  for each row execute function public.block_extra_users();

-- ---------- policies: owner only AND row belongs to the caller ----------
do $$ declare t text; begin
  foreach t in array array['novels','parts','chapters','scenes','manuscript_revisions'] loop
    execute format('drop policy %I on public.%I', t || '_select', t);
    execute format('drop policy %I on public.%I', t || '_insert', t);
    execute format('drop policy %I on public.%I', t || '_update', t);
    execute format('drop policy %I on public.%I', t || '_delete', t);
    execute format('create policy %I on public.%I for select using (user_id = (select auth.uid()) and (select public.is_owner()))', t || '_select', t);
    execute format('create policy %I on public.%I for insert with check (user_id = (select auth.uid()) and (select public.is_owner()))', t || '_insert', t);
    execute format('create policy %I on public.%I for update using (user_id = (select auth.uid()) and (select public.is_owner())) with check (user_id = (select auth.uid()) and (select public.is_owner()))', t || '_update', t);
    execute format('create policy %I on public.%I for delete using (user_id = (select auth.uid()) and (select public.is_owner()))', t || '_delete', t);
  end loop;
end $$;

drop policy profiles_select on public.profiles;
drop policy profiles_update on public.profiles;
create policy profiles_select on public.profiles for select using (id = (select auth.uid()) and (select public.is_owner()));
create policy profiles_update on public.profiles for update using (id = (select auth.uid()) and (select public.is_owner())) with check (id = (select auth.uid()) and (select public.is_owner()));
drop policy prefs_select on public.user_preferences;
drop policy prefs_update on public.user_preferences;
create policy prefs_select on public.user_preferences for select using (user_id = (select auth.uid()) and (select public.is_owner()));
create policy prefs_update on public.user_preferences for update using (user_id = (select auth.uid()) and (select public.is_owner())) with check (user_id = (select auth.uid()) and (select public.is_owner()));

-- ---------- RPCs: same logic as 0001, plus an explicit owner check (they run as definer) ----------
create or replace function public.save_chapter(
  p_chapter_id uuid, p_base_revision int, p_content jsonb,
  p_word_count int, p_op_id uuid, p_force_snapshot boolean default false
) returns table (status text, revision int)
language plpgsql security definer set search_path = public as $$
declare c public.chapters; uid uuid := auth.uid(); last_snap timestamptz;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into c from public.chapters where id = p_chapter_id and user_id = uid for update;
  if not found then return query select 'not_found'::text, null::int; return; end if;
  if c.last_op_id = p_op_id then return query select 'ok'::text, c.revision; return; end if;
  if c.revision <> p_base_revision then return query select 'conflict'::text, c.revision; return; end if;
  select max(created_at) into last_snap from public.manuscript_revisions where chapter_id = c.id;
  if p_force_snapshot or last_snap is null or last_snap < now() - interval '5 minutes' then
    insert into public.manuscript_revisions (user_id, chapter_id, chapter_revision, content, word_count, reason)
    values (uid, c.id, c.revision, c.content, c.word_count, case when p_force_snapshot then 'manual' else 'autosave' end);
  end if;
  update public.chapters set content = p_content, word_count = greatest(p_word_count, 0),
         revision = c.revision + 1, last_op_id = p_op_id where id = c.id;
  return query select 'ok'::text, c.revision + 1;
end $$;

create or replace function public.restore_revision(p_revision_id uuid)
returns table (status text, revision int)
language plpgsql security definer set search_path = public as $$
declare r public.manuscript_revisions; c public.chapters; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into r from public.manuscript_revisions where id = p_revision_id and user_id = uid;
  if not found then return query select 'not_found'::text, null::int; return; end if;
  select * into c from public.chapters where id = r.chapter_id and user_id = uid for update;
  insert into public.manuscript_revisions (user_id, chapter_id, chapter_revision, content, word_count, reason)
  values (uid, c.id, c.revision, c.content, c.word_count, 'pre_restore');
  update public.chapters set content = r.content, word_count = r.word_count, revision = c.revision + 1, last_op_id = null where id = c.id;
  insert into public.manuscript_revisions (user_id, chapter_id, chapter_revision, content, word_count, reason)
  values (uid, c.id, c.revision + 1, r.content, r.word_count, 'restore');
  return query select 'ok'::text, c.revision + 1;
end $$;

-- ---------- language: manuscript language per novel (default Indonesian); UI language separate ----------
alter table public.novels alter column language set default 'id-ID';
alter table public.novels add constraint novels_language_chk check (language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$');
alter table public.user_preferences add column ui_language text not null default 'id' check (ui_language in ('id','en'));

-- Personal dictionary: words/terms spell-check and writing checks must not flag. novel_id null = all novels.
create table public.custom_words (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  novel_id uuid,
  word text not null check (char_length(word) between 1 and 80),
  kind text not null default 'ignore' check (kind in ('ignore','term')),
  created_at timestamptz not null default now(),
  unique nulls not distinct (user_id, novel_id, word),
  foreign key (novel_id, user_id) references public.novels (id, user_id) on delete cascade
);

-- Remembers findings the owner dismissed or marked intentional. Key comes from the checker (stable across edits).
create table public.finding_states (
  user_id uuid not null references public.profiles(id) on delete cascade,
  novel_id uuid not null,
  key text not null check (char_length(key) <= 200),
  status text not null check (status in ('dismissed','fixed','accepted')),
  updated_at timestamptz not null default now(),
  primary key (novel_id, key),
  foreign key (novel_id, user_id) references public.novels (id, user_id) on delete cascade
);

do $$ declare t text; begin
  foreach t in array array['custom_words','finding_states'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select using (user_id = (select auth.uid()) and (select public.is_owner()))', t || '_select', t);
    execute format('create policy %I on public.%I for insert with check (user_id = (select auth.uid()) and (select public.is_owner()))', t || '_insert', t);
    execute format('create policy %I on public.%I for update using (user_id = (select auth.uid()) and (select public.is_owner())) with check (user_id = (select auth.uid()) and (select public.is_owner()))', t || '_update', t);
    execute format('create policy %I on public.%I for delete using (user_id = (select auth.uid()) and (select public.is_owner()))', t || '_delete', t);
  end loop;
end $$;

-- ===== 0004_characters =====
-- Characters (Story Bible). aliases and speech settings feed the Indonesian writing checks.
create table public.characters (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  novel_id uuid not null,
  name text not null check (char_length(name) between 1 and 120),
  aliases text[] not null default '{}',
  register_style text check (register_style in ('formal','informal')),
  avoid_words text[] not null default '{}',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  foreign key (novel_id, user_id) references public.novels (id, user_id) on delete cascade
);
create index characters_novel_idx on public.characters (novel_id, name);
create trigger characters_updated before update on public.characters for each row execute function public.set_updated_at();
alter table public.characters enable row level security;
create policy characters_select on public.characters for select using (user_id = (select auth.uid()) and (select public.is_owner()));
create policy characters_insert on public.characters for insert with check (user_id = (select auth.uid()) and (select public.is_owner()));
create policy characters_update on public.characters for update using (user_id = (select auth.uid()) and (select public.is_owner())) with check (user_id = (select auth.uid()) and (select public.is_owner()));
create policy characters_delete on public.characters for delete using (user_id = (select auth.uid()) and (select public.is_owner()));

