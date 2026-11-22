-- Trenerbrettet v50: kjor hele filen EN gang i Supabase SQL Editor.
-- Oppretter bare grunnlag for manuell overforing av lag/spillerstall.
-- Ingen kampdata lagres i skyen enna.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
revoke all on public.profiles from anon;
grant select,insert,update on public.profiles to authenticated;
drop policy if exists "profile_select_own" on public.profiles;
create policy "profile_select_own" on public.profiles for select to authenticated using ((select auth.uid())=id);
drop policy if exists "profile_insert_own" on public.profiles;
create policy "profile_insert_own" on public.profiles for insert to authenticated with check ((select auth.uid())=id);
drop policy if exists "profile_update_own" on public.profiles;
create policy "profile_update_own" on public.profiles for update to authenticated
  using ((select auth.uid())=id) with check ((select auth.uid())=id);
-- Ensure accounts created before installing this migration have a profile.
insert into public.profiles(id) select id from auth.users on conflict (id) do nothing;
create or replace function public.handle_new_trenerbrettet_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id) values(new.id) on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists trenerbrettet_auth_user_created on auth.users;
create trigger trenerbrettet_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_trenerbrettet_user();

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
create table if not exists public.players (
  id uuid primary key,
  team_id uuid not null references public.teams(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  shirt_number int not null check (shirt_number between 1 and 99),
  active_by_default boolean not null default true,
  preferred_roles text[] not null default '{}',
  updated_at timestamptz not null default now(),
  unique (team_id, shirt_number)
);
create index if not exists tb_member_user_idx on public.team_members(user_id);
create index if not exists tb_players_team_idx on public.players(team_id);

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.players enable row level security;
revoke all on public.teams, public.team_members, public.players from anon;
grant select on public.teams, public.team_members, public.players to authenticated;
-- All writes go through validated RPC functions, not direct browser writes.
revoke insert,update,delete on public.teams, public.team_members, public.players from authenticated;

drop policy if exists "team_view_member" on public.teams;
create policy "team_view_member" on public.teams for select to authenticated
using (exists(select 1 from public.team_members m where m.team_id=teams.id and m.user_id=(select auth.uid())));
drop policy if exists "member_view_own" on public.team_members;
create policy "member_view_own" on public.team_members for select to authenticated
using (user_id=(select auth.uid()));
drop policy if exists "tb_players_select" on public.players;
create policy "tb_players_select" on public.players for select to authenticated
using (exists(select 1 from public.team_members m where m.team_id=players.team_id and m.user_id=(select auth.uid())));

-- Important: pre-existing v46 insert policy must not allow direct table writes.
drop policy if exists "team_insert_owner" on public.teams;

create or replace function public.tb_save_team_roster(
  p_team_id uuid, p_name text, p_players jsonb
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_player jsonb;
  v_role text;
  v_number integer;
  v_player_id uuid;
  v_seen_numbers int[] := '{}';
  v_seen_ids uuid[] := '{}';
begin
  if v_uid is null then raise exception 'Logg inn forst'; end if;
  if p_team_id is null or char_length(trim(coalesce(p_name,''))) not between 1 and 80 then
    raise exception 'Ugyldig lag';
  end if;
  if jsonb_typeof(p_players) is distinct from 'array' or jsonb_array_length(p_players)>100 then
    raise exception 'Ugyldig spillerliste';
  end if;
  select created_by into v_owner from public.teams where id=p_team_id for update;
  if v_owner is null then
    insert into public.teams(id,name,created_by) values(p_team_id,trim(p_name),v_uid);
    insert into public.team_members(team_id,user_id,role) values(p_team_id,v_uid,'admin')
    on conflict (team_id,user_id) do nothing;
  else
    select role into v_role from public.team_members where team_id=p_team_id and user_id=v_uid;
    if v_role is distinct from 'admin' then raise exception 'Bare lagadministrator kan laste opp laget'; end if;
    update public.teams set name=trim(p_name) where id=p_team_id;
  end if;
  -- Validate entire roster before writing any player rows (transactional).
  for v_player in select value from jsonb_array_elements(p_players) loop
    v_player_id := (v_player->>'id')::uuid;
    v_number := (v_player->>'number')::integer;
    if v_player_id is null or v_player_id=any(v_seen_ids)
       or v_number not between 1 and 99 or v_number=any(v_seen_numbers)
       or char_length(trim(coalesce(v_player->>'name',''))) not between 1 and 80 then
      raise exception 'Ugyldig eller duplisert spiller/nummer';
    end if;
    v_seen_ids := array_append(v_seen_ids,v_player_id);
    v_seen_numbers := array_append(v_seen_numbers,v_number);
  end loop;
  -- Remove old rows for this specific team before inserting the new roster.
  -- Only an admin can invoke this function; transaction rolls back on failure.
  delete from public.players where team_id=p_team_id;
  for v_player in select value from jsonb_array_elements(p_players) loop
    insert into public.players(id,team_id,name,shirt_number,active_by_default,preferred_roles)
    values ((v_player->>'id')::uuid,p_team_id,trim(v_player->>'name'),
      (v_player->>'number')::integer,
      coalesce((v_player->>'inSquad')::boolean,true),
      coalesce((select array_agg(s) from jsonb_array_elements_text(coalesce(v_player->'preferredRoles','[]'::jsonb)) as s
        where s in ('K','F','M','A')),'{}'));
  end loop;
  return p_team_id;
end; $$;
revoke all on function public.tb_save_team_roster(uuid,text,jsonb) from public,anon;
grant execute on function public.tb_save_team_roster(uuid,text,jsonb) to authenticated;

-- Database checks are mandatory for SELECT, too; normal client roles cannot bypass RLS.
