-- =============================================================
-- Cognom — initial database schema, RLS, storage, triggers
-- Run this once in the Supabase SQL Editor.
-- =============================================================

-- =============================================================
-- 1. UPDATED_AT TRIGGER HELPER
-- =============================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =============================================================
-- 2. PROFILES — one row per auth user, holds the SELF data
-- =============================================================
create table public.profiles (
  user_id           uuid        primary key references auth.users(id) on delete cascade,
  name              text        default '',
  about             text        default '',
  photo_url         text        default '',
  voice_sample_url  text        default '',
  voice_sample_mime text        default '',
  sp_values         text        default '',
  sp_needs          text        default '',
  sp_emotions      text        default '',
  sp_thought_count  int         default 0,
  sp_journal        jsonb       default '[]'::jsonb,
  self_events       jsonb       default '[]'::jsonb,  -- moments hosted by self
  created_at        timestamptz default now(),
  updated_at        timestamptz default now()
);
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-create a profile row when a new user signs up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (user_id) values (new.id);
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =============================================================
-- 3. PEOPLE — the tree
-- =============================================================
create table public.people (
  id                uuid        primary key default gen_random_uuid(),
  user_id           uuid        not null references auth.users(id) on delete cascade,
  -- core identity
  name              text        not null,
  family_name       text        default '',
  who               text        default '',
  initial           text        default '',
  av_class          text        default '',
  relation          text        default 'Friend',
  photo_url         text        default '',
  -- calling
  phone             text        default '',
  channel           text        default 'phone',  -- phone | whatsapp | telegram | facetime
  -- cadence loop
  cadence           text        default '',       -- '' | weekly | biweekly | monthly | quarterly
  cadence_set_at    timestamptz,
  last_conv_date    timestamptz,
  snoozed_until     timestamptz,
  -- portrait (AI-derived)
  conv_count        int         default 0,
  last_call         text        default 'No conversations yet',
  precall_q         text        default '',
  precall_ctx       text        default '',
  comm_style        text        default '',
  matters           text        default '',
  mentioned         text        default '',
  emotion           text        default '',
  -- structured data
  chips             jsonb       default '[]'::jsonb,
  alt_questions     jsonb       default '[]'::jsonb,
  alt_q_idx         int         default 0,
  timeline          jsonb       default '[]'::jsonb,
  gems              jsonb       default '[]'::jsonb,
  orbit             jsonb       default '[]'::jsonb,
  topics            jsonb       default '[]'::jsonb,
  forget            jsonb       default '[]'::jsonb,
  links             jsonb       default '[]'::jsonb,
  echoes            jsonb       default '[]'::jsonb,
  about_you         jsonb       default '[]'::jsonb,
  capsule           jsonb       default '[]'::jsonb,
  your_view         jsonb       default '{}'::jsonb,
  -- linkage when this person also has a Cognom account
  linked_user_id    uuid        references auth.users(id) on delete set null,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now()
);
create index people_user_id_idx        on public.people(user_id);
create index people_linked_user_id_idx on public.people(linked_user_id) where linked_user_id is not null;
create trigger people_updated_at before update on public.people
  for each row execute function public.set_updated_at();

-- =============================================================
-- 4. EVENTS — moments (1–4 photos plus context)
-- =============================================================
create table public.events (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null references auth.users(id) on delete cascade,
  person_id       uuid        references public.people(id) on delete cascade,
  photos          jsonb       default '[]'::jsonb,  -- array of photo URLs
  context         text        default '',
  date_display    text        default '',          -- human-readable date string
  tagged_people   uuid[]      default '{}',
  shared_with     jsonb       default '[]'::jsonb, -- [{pid, name, channel, date, token?}]
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);
create index events_user_id_idx   on public.events(user_id);
create index events_person_id_idx on public.events(person_id);
create trigger events_updated_at before update on public.events
  for each row execute function public.set_updated_at();

-- =============================================================
-- 5. SHARES — Cognom-to-Cognom delivery queue + invite links
-- =============================================================
create table public.shares (
  id              uuid        primary key default gen_random_uuid(),
  from_user_id    uuid        not null references auth.users(id) on delete cascade,
  to_user_id      uuid        references auth.users(id) on delete cascade,  -- null until invite is claimed
  event_id        uuid        references public.events(id) on delete cascade,
  channel         text        not null,    -- 'cognom' | 'invite'
  token           text        unique,      -- for invite links
  recipient_name  text        default '',
  status          text        default 'pending', -- pending | delivered | opened
  created_at      timestamptz default now(),
  delivered_at    timestamptz
);
create index shares_from_user_id_idx on public.shares(from_user_id);
create index shares_to_user_id_idx   on public.shares(to_user_id) where to_user_id is not null;
create index shares_token_idx        on public.shares(token)      where token       is not null;

-- =============================================================
-- 6. ROW LEVEL SECURITY
-- (auto-RLS is enabled, but we add explicit policies anyway)
-- =============================================================
alter table public.profiles enable row level security;
alter table public.people   enable row level security;
alter table public.events   enable row level security;
alter table public.shares   enable row level security;

-- profiles: own row only
create policy "Read own profile"   on public.profiles for select using  (auth.uid() = user_id);
create policy "Update own profile" on public.profiles for update using  (auth.uid() = user_id);
create policy "Insert own profile" on public.profiles for insert with check (auth.uid() = user_id);
create policy "Delete own profile" on public.profiles for delete using  (auth.uid() = user_id);

-- people: tree owner only
create policy "Read own people"   on public.people for select using  (auth.uid() = user_id);
create policy "Insert own people" on public.people for insert with check (auth.uid() = user_id);
create policy "Update own people" on public.people for update using  (auth.uid() = user_id);
create policy "Delete own people" on public.people for delete using  (auth.uid() = user_id);

-- events: tree owner only
create policy "Read own events"   on public.events for select using  (auth.uid() = user_id);
create policy "Insert own events" on public.events for insert with check (auth.uid() = user_id);
create policy "Update own events" on public.events for update using  (auth.uid() = user_id);
create policy "Delete own events" on public.events for delete using  (auth.uid() = user_id);

-- shares: sender can read all their sent; recipient can read incoming
create policy "Read shares sent"     on public.shares for select using  (auth.uid() = from_user_id);
create policy "Read shares received" on public.shares for select using  (auth.uid() = to_user_id);
create policy "Send shares"          on public.shares for insert with check (auth.uid() = from_user_id);
create policy "Update sent shares"   on public.shares for update using  (auth.uid() = from_user_id);
create policy "Recipient marks opened" on public.shares for update using  (auth.uid() = to_user_id);
create policy "Delete own shares"    on public.shares for delete using  (auth.uid() = from_user_id);

-- =============================================================
-- 7. API EXPOSURE (because "Automatically expose new tables" is OFF)
-- =============================================================
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.profiles, public.people, public.events, public.shares to authenticated;
-- anon role gets nothing — sign-in is required for everything

-- =============================================================
-- 8. STORAGE BUCKETS
-- =============================================================
insert into storage.buckets (id, name, public) values
  ('avatars', 'avatars', false),
  ('moments', 'moments', false),
  ('audio',   'audio',   false)
on conflict (id) do nothing;

-- Storage RLS: each user gets a folder named after their user_id.
-- The first path segment of every uploaded object must match auth.uid().
create policy "Read own avatars"   on storage.objects for select using  (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "Upload own avatars" on storage.objects for insert with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "Update own avatars" on storage.objects for update using  (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "Delete own avatars" on storage.objects for delete using  (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "Read own moments"   on storage.objects for select using  (bucket_id = 'moments' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "Upload own moments" on storage.objects for insert with check (bucket_id = 'moments' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "Update own moments" on storage.objects for update using  (bucket_id = 'moments' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "Delete own moments" on storage.objects for delete using  (bucket_id = 'moments' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "Read own audio"   on storage.objects for select using  (bucket_id = 'audio' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "Upload own audio" on storage.objects for insert with check (bucket_id = 'audio' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "Update own audio" on storage.objects for update using  (bucket_id = 'audio' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "Delete own audio" on storage.objects for delete using  (bucket_id = 'audio' and auth.uid()::text = (storage.foldername(name))[1]);

-- =============================================================
-- DONE.
-- =============================================================
