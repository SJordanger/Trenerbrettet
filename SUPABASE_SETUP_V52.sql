-- Trenerbrettet v52: Invitasjoner og delte lag.
-- Kjor i SQL Editor ETTER V50. Ingen eksisterende lag eller spillere slettes.
-- Invitasjoner sender ikke e-post automatisk; inviterte godtar etter egen innlogging.
create extension if not exists pgcrypto;

create table if not exists public.team_invitations (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  email text not null check (char_length(email) between 5 and 254),
  invited_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(team_id,email)
);
create index if not exists tb_team_invitation_email_idx on public.team_invitations(email);
alter table public.team_invitations enable row level security;
revoke all on public.team_invitations from anon,authenticated;
-- Only verified backend RPCs access this table.

create or replace function public.tb_invite_team_coach(p_team_id uuid,p_email text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(p_email,'')));
  v_invite uuid;
begin
  if v_uid is null then raise exception 'Logg inn forst'; end if;
  if not exists(select 1 from public.team_members m where m.team_id=p_team_id and m.user_id=v_uid and m.role='admin') then
    raise exception 'Bare administrator kan invitere trenere';
  end if;
  if length(v_email)>254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Ugyldig e-postadresse';
  end if;
  if exists(select 1 from auth.users u where u.id=v_uid and lower(u.email)=v_email) then
    raise exception 'Du er allerede medlem av laget';
  end if;
  if exists(select 1 from auth.users u join public.team_members m on m.user_id=u.id
            where m.team_id=p_team_id and lower(u.email)=v_email) then
    raise exception 'Treneren er allerede medlem av laget';
  end if;
  insert into public.team_invitations(team_id,email,invited_by) values(p_team_id,v_email,v_uid)
  on conflict (team_id,email) do update set invited_by=excluded.invited_by,created_at=now()
  returning id into v_invite;
  return v_invite;
end; $$;

create or replace function public.tb_my_team_invitations()
returns table(id uuid,team_id uuid,team_name text)
language plpgsql security definer set search_path = '' as $$
declare v_email text;
begin
  select lower(u.email) into v_email from auth.users u
  where u.id=auth.uid() and u.email_confirmed_at is not null;
  if v_email is null then raise exception 'Bekreft e-postadressen din'; end if;
  return query select i.id,t.id,t.name from public.team_invitations i
    join public.teams t on t.id=i.team_id
    where i.email=v_email and not exists(
      select 1 from public.team_members m where m.team_id=i.team_id and m.user_id=auth.uid())
    order by i.created_at desc;
end; $$;

create or replace function public.tb_accept_team_invite(p_invitation_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_email text; v_team_id uuid;
begin
  select lower(u.email) into v_email from auth.users u
  where u.id=auth.uid() and u.email_confirmed_at is not null;
  if v_email is null then raise exception 'Bekreft e-postadressen din'; end if;
  select i.team_id into v_team_id from public.team_invitations i
  where i.id=p_invitation_id and i.email=v_email for update;
  if v_team_id is null then raise exception 'Invitasjonen finnes ikke eller tilhorer en annen konto'; end if;
  insert into public.team_members(team_id,user_id,role) values(v_team_id,auth.uid(),'coach')
  on conflict (team_id,user_id) do nothing;
  delete from public.team_invitations where id=p_invitation_id;
  return v_team_id;
end; $$;

create or replace function public.tb_team_access(p_team_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_is_admin boolean;v_result jsonb;
begin
  if not exists(select 1 from public.team_members m where m.team_id=p_team_id and m.user_id=auth.uid()) then
    raise exception 'Du har ikke tilgang til laget';
  end if;
  select (m.role='admin') into v_is_admin from public.team_members m
  where m.team_id=p_team_id and m.user_id=auth.uid();
  select jsonb_build_object(
    'is_admin',v_is_admin,
    'members',coalesce((select jsonb_agg(jsonb_build_object(
      'user_id',m.user_id,'email',u.email,'role',m.role) order by m.joined_at)
      from public.team_members m join auth.users u on u.id=m.user_id
      where m.team_id=p_team_id),'[]'::jsonb),
    'pending',case when v_is_admin then coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'email',i.email) order by i.created_at)
      from public.team_invitations i where i.team_id=p_team_id),'[]'::jsonb)
      else '[]'::jsonb end
  ) into v_result;
  return v_result;
end; $$;

create or replace function public.tb_cancel_team_invite(p_invitation_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.team_invitations i where i.id=p_invitation_id and exists(
    select 1 from public.team_members m where m.team_id=i.team_id
    and m.user_id=auth.uid() and m.role='admin');
  if not found then raise exception 'Invitasjonen finnes ikke, eller du mangler tilgang'; end if;
end; $$;

create or replace function public.tb_remove_team_coach(p_team_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists(select 1 from public.team_members m where m.team_id=p_team_id
    and m.user_id=auth.uid() and m.role='admin') then
    raise exception 'Bare administrator kan fjerne trenere';
  end if;
  delete from public.team_members m where m.team_id=p_team_id and m.user_id=p_user_id and m.role='coach';
  if not found then raise exception 'Treneren finnes ikke, eller kan ikke fjernes'; end if;
end; $$;

-- Make the same manually-triggered roster upload available to shared team coaches.
-- Team names can only be changed by administrators; roster replacement is atomic.
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
    if v_role not in ('admin','coach') then raise exception 'Du har ikke tilgang til laget'; end if;
    if v_role='admin' then
      update public.teams set name=trim(p_name) where id=p_team_id;
    elsif (select name from public.teams where id=p_team_id) is distinct from trim(p_name) then
      raise exception 'Bare administrator kan endre lagnavnet';
    end if;
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

-- Restrict all exposed SECURITY DEFINER functions to logged-in users.
revoke all on function public.tb_invite_team_coach(uuid,text) from public,anon;
grant execute on function public.tb_invite_team_coach(uuid,text) to authenticated;
revoke all on function public.tb_my_team_invitations() from public,anon;
grant execute on function public.tb_my_team_invitations() to authenticated;
revoke all on function public.tb_accept_team_invite(uuid) from public,anon;
grant execute on function public.tb_accept_team_invite(uuid) to authenticated;
revoke all on function public.tb_team_access(uuid) from public,anon;
grant execute on function public.tb_team_access(uuid) to authenticated;
revoke all on function public.tb_cancel_team_invite(uuid) from public,anon;
grant execute on function public.tb_cancel_team_invite(uuid) to authenticated;
revoke all on function public.tb_remove_team_coach(uuid,uuid) from public,anon;
grant execute on function public.tb_remove_team_coach(uuid,uuid) to authenticated;
revoke all on function public.tb_save_team_roster(uuid,text,jsonb) from public,anon;
grant execute on function public.tb_save_team_roster(uuid,text,jsonb) to authenticated;
