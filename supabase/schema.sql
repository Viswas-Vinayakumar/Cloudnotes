-- CloudNotes backend schema (run once in your Supabase project's SQL editor).
-- Free tier is plenty: notes are tiny rows.

create table if not exists public.notes (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  content text not null default '',
  pre_ai_content text,
  rtf_base64 text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);

-- Each user can only see and touch their own notes.
alter table public.notes enable row level security;

create policy "users manage own notes"
  on public.notes
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Stream inserts/updates to clients in real time.
alter publication supabase_realtime add table public.notes;

-- If you created the table before formatting support, run this once:
alter table public.notes add column if not exists rtf_base64 text;
