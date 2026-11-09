-- DIT Factory Tour Tracker · Supabase schema
-- Run in Supabase SQL Editor. Review policies with your IT/security team before production.
create extension if not exists pgcrypto;

create table if not exists public.tour_sessions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  status text not null default 'active' check (status in ('draft','active','completed','cancelled')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.tour_groups (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.tour_sessions(id) on delete cascade,
  name text not null,
  leader_id uuid not null references auth.users(id) on delete restrict,
  leader_name text,
  status text not null default 'ready' check (status in ('ready','in_progress','paused','completed')),
  created_at timestamptz not null default now()
);

create table if not exists public.group_locations (
  group_id uuid primary key references public.tour_groups(id) on delete cascade,
  session_id uuid not null references public.tour_sessions(id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  accuracy double precision,
  speed double precision,
  heading double precision,
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id)
);

create table if not exists public.checkpoint_events (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.tour_sessions(id) on delete cascade,
  group_id uuid not null references public.tour_groups(id) on delete cascade,
  checkpoint_code text not null,
  checkpoint_name text not null,
  checked_in_by uuid not null references auth.users(id),
  checked_in_at timestamptz not null default now(),
  latitude double precision,
  longitude double precision,
  source text not null default 'leader_manual'
);

create index if not exists idx_tour_groups_session on public.tour_groups(session_id);
create index if not exists idx_checkpoint_events_group_time on public.checkpoint_events(group_id, checked_in_at desc);
create index if not exists idx_group_locations_session on public.group_locations(session_id);

-- Membership controls access: creator is session admin; assigned leader can write for their group;
-- HR monitor must be explicitly added as monitor to session_members.
create table if not exists public.session_members (
  session_id uuid not null references public.tour_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','leader','monitor')),
  created_at timestamptz not null default now(),
  primary key(session_id,user_id)
);

create or replace function public.is_session_member(p_session uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.session_members m where m.session_id=p_session and m.user_id=auth.uid()) $$;

create or replace function public.is_session_admin(p_session uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.session_members m where m.session_id=p_session and m.user_id=auth.uid() and m.role='admin') $$;

create or replace function public.is_group_leader(p_group uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.tour_groups g where g.id=p_group and g.leader_id=auth.uid()) $$;

alter table public.tour_sessions enable row level security;
alter table public.tour_groups enable row level security;
alter table public.group_locations enable row level security;
alter table public.checkpoint_events enable row level security;
alter table public.session_members enable row level security;

drop policy if exists "session member read sessions" on public.tour_sessions;
create policy "session member read sessions" on public.tour_sessions for select to authenticated using (public.is_session_member(id) or created_by=auth.uid());
drop policy if exists "authenticated create own sessions" on public.tour_sessions;
create policy "authenticated create own sessions" on public.tour_sessions for insert to authenticated with check (created_by=auth.uid());
drop policy if exists "admin update sessions" on public.tour_sessions;
create policy "admin update sessions" on public.tour_sessions for update to authenticated using (public.is_session_admin(id)) with check (public.is_session_admin(id));

drop policy if exists "member read groups" on public.tour_groups;
create policy "member read groups" on public.tour_groups for select to authenticated using (public.is_session_member(session_id));
drop policy if exists "admin or assigned leader create groups" on public.tour_groups;
create policy "admin or assigned leader create groups" on public.tour_groups for insert to authenticated with check (public.is_session_admin(session_id) and leader_id=auth.uid());
drop policy if exists "leader or admin update group" on public.tour_groups;
create policy "leader or admin update group" on public.tour_groups for update to authenticated using (leader_id=auth.uid() or public.is_session_admin(session_id)) with check (leader_id=auth.uid() or public.is_session_admin(session_id));

drop policy if exists "members read locations" on public.group_locations;
create policy "members read locations" on public.group_locations for select to authenticated using (public.is_session_member(session_id));
drop policy if exists "leader upsert own group location" on public.group_locations;
create policy "leader upsert own group location" on public.group_locations for insert to authenticated with check (public.is_session_member(session_id) and public.is_group_leader(group_id) and updated_by=auth.uid());
drop policy if exists "leader update own group location" on public.group_locations;
create policy "leader update own group location" on public.group_locations for update to authenticated using (public.is_group_leader(group_id) and public.is_session_member(session_id)) with check (public.is_group_leader(group_id) and updated_by=auth.uid());

drop policy if exists "members read checkpoint events" on public.checkpoint_events;
create policy "members read checkpoint events" on public.checkpoint_events for select to authenticated using (public.is_session_member(session_id));
drop policy if exists "leader insert checkpoint events" on public.checkpoint_events;
create policy "leader insert checkpoint events" on public.checkpoint_events for insert to authenticated with check (public.is_session_member(session_id) and public.is_group_leader(group_id) and checked_in_by=auth.uid());

drop policy if exists "members read session members" on public.session_members;
create policy "members read session members" on public.session_members for select to authenticated using (public.is_session_member(session_id) or exists(select 1 from public.tour_sessions s where s.id=session_id and s.created_by=auth.uid()));
drop policy if exists "creator adds self as admin" on public.session_members;
create policy "creator adds self as admin" on public.session_members for insert to authenticated with check (user_id=auth.uid() and role='admin' and exists(select 1 from public.tour_sessions s where s.id=session_id and s.created_by=auth.uid()));
drop policy if exists "admin manages members" on public.session_members;
create policy "admin manages members" on public.session_members for all to authenticated using (public.is_session_admin(session_id)) with check (public.is_session_admin(session_id));

-- Enable Realtime for tables used by live monitor.
do $$ begin
  alter publication supabase_realtime add table public.group_locations;
exception when duplicate_object then null;
when undefined_object then null;
end $$;
do $$ begin
  alter publication supabase_realtime add table public.checkpoint_events;
exception when duplicate_object then null;
when undefined_object then null;
end $$;

-- IMPORTANT:
-- After creating a tour_sessions row, insert its creator as admin into session_members.
-- This starter app currently creates the session row; add the membership insert in your
-- trusted server-side provisioning workflow, or run the following SQL with the new IDs:
-- insert into public.session_members(session_id,user_id,role)
-- values ('SESSION_UUID','AUTH_USER_UUID','admin');
-- Then add HR monitor accounts as role='monitor' and leaders as role='leader'.
-- Do not expose service_role keys in browser code.
