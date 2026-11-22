-- TRENERBRETTET V46 - FASE 2. Kjor i Supabase SQL Editor.
-- Dette lager brukerkonto-profiler og en sikret basis for delte lag.
-- Ingen lokale kamper/spillere importeres i denne fasen.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 80),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','coach')),
  joined_at timestamptz not null default now(),
  primary key (team_id,user_id)
);
create index if not exists team_members_user_idx on public.team_members(user_id);

alter table public.profiles enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;

-- Eksplisitte GRANTs kun for innloggede brukere.
revoke all on public.profiles,public.teams,public.team_members from anon;
grant select,insert,update on public.profiles to authenticated;
grant select,insert,update on public.teams to authenticated;
grant select on public.team_members to authenticated;

-- Profiler er kun synlige og redigerbare av eieren i denne fasen.
create policy "profile_select_own" on public.profiles for select to authenticated using ((select auth.uid())=id);
create policy "profile_insert_own" on public.profiles for insert to authenticated with check ((select auth.uid())=id);
create policy "profile_update_own" on public.profiles for update to authenticated using ((select auth.uid())=id) with check ((select auth.uid())=id);

-- Direkte medlemsoppslag fra teams, uten rekursive policies.
create policy "team_view_member" on public.teams for select to authenticated
  using (exists(select 1 from public.team_members m where m.team_id=teams.id and m.user_id=(select auth.uid())));
create policy "team_insert_owner" on public.teams for insert to authenticated
  with check (created_by=(select auth.uid()));

-- Medlemslisten er bare synlig for eget medlemskap. Deling kommer i fase 3.
create policy "member_view_own" on public.team_members for select to authenticated
  using (user_id=(select auth.uid()));

-- Opprett profil automatisk ved brukerregistrering.
create or replace function public.handle_new_trenerbrettet_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists trenerbrettet_auth_user_created on auth.users;
create trigger trenerbrettet_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_trenerbrettet_user();

-- NB: Dette er grunnlag for fase 3, og ikke et komplett medlemssystem.
-- Oppretting av team + admin-medlemskap skal gjores atomisk i server-RPC i fase 3.
