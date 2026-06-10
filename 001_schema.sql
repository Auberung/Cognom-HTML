-- =========================================================
-- Cognom — Supabase schema
-- Run this in your Supabase SQL Editor (Dashboard → SQL Editor → New query)
-- =========================================================

-- User profiles: stores SELF data and PEOPLE array as JSONB
-- One row per authenticated user
create table if not exists user_data (
  id uuid primary key references auth.users(id) on delete cascade,
  self_data jsonb not null default '{}'::jsonb,
  people_data jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- Row Level Security: users can only read/write their own row
alter table user_data enable row level security;

-- Policy: users can read their own data
create policy "Users can read own data"
  on user_data for select
  using (auth.uid() = id);

-- Policy: users can insert their own data
create policy "Users can insert own data"
  on user_data for insert
  with check (auth.uid() = id);

-- Policy: users can update their own data
create policy "Users can update own data"
  on user_data for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Policy: users can delete their own data
create policy "Users can delete own data"
  on user_data for delete
  using (auth.uid() = id);

-- Auto-update the updated_at timestamp
create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger user_data_updated_at
  before update on user_data
  for each row
  execute function update_updated_at();
