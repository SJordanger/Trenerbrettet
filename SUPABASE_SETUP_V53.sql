-- Trenerbrettet v53 - sikker automatisk synkronisering av spillerstaller.
-- Kjor etter V50 og V52 i Supabase SQL Editor.
-- Beholder alle eksisterende lag, spillere og medlemskap.
-- Ved samtidige endringer avvises overskriving med SYNC_CONFLICT.

alter table public.teams
  add column if not exists roster_version bigint not null default 1;

create or replace function public.tb_sync_team_roster(
  p_team_id uuid, p_name text, p_players jsonb, p_expected_version bigint
) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_existing bigint;
  v_next bigint;
  v_player jsonb;
  v_number integer;
  v_player_id uuid;
  v_seen_numbers integer[] := '{}';
  v_seen_ids uuid[] := '{}';
begin
  if v_uid is null then raise exception 'Du maa vaere logget inn'; end if;
  if p_team_id is null or char_length(trim(coalesce(p_name,''))) not between 1 and 80 then
    raise exception 'Ugyldig lag';
  end if;
  if p_expected_version is null or p_expected_version < 0 then
    raise exception 'Ugyldig forventet versjon';
  end if;
  if jsonb_typeof(p_players) is distinct from 'array' or jsonb_array_length(p_players) > 100 then
    raise exception 'Ugyldig spillerliste';
  end if;

  -- Validate entire roster BEFORE any changes.
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

  -- Lock the team row. Only one update at a time can win.
  select roster_version into v_existing from public.teams where id=p_team_id for update;
  if not found then
    if p_expected_version <> 0 then raise exception 'SYNC_CONFLICT: Laget finnes ikke'; end if;
    insert into public.teams(id,name,created_by,roster_version)
    values(p_team_id,trim(p_name),v_uid,1);
    insert into public.team_members(team_id,user_id,role)
    values(p_team_id,v_uid,'admin') on conflict (team_id,user_id) do nothing;
    v_next := 1;
  else
    select role into v_role from public.team_members
    where team_id=p_team_id and user_id=v_uid;
    if v_role is distinct from 'admin' and v_role is distinct from 'coach' then
      raise exception 'Du har ikke tilgang til dette laget';
    end if;
    if v_existing <> p_expected_version then
      raise exception 'SYNC_CONFLICT: Laget er endret av en annen trener';
    end if;
    if v_role='coach' and (select name from public.teams where id=p_team_id) is distinct from trim(p_name) then
      raise exception 'Kun administrator kan endre lagnavnet';
    end if;
    v_next := v_existing+1;
    update public.teams set roster_version=v_next,
      name=case when v_role='admin' then trim(p_name) else name end
    where id=p_team_id;
  end if;

  delete from public.players where team_id=p_team_id;
  for v_player in select value from jsonb_array_elements(p_players) loop
    insert into public.players(id,team_id,name,shirt_number,active_by_default,preferred_roles)
    values ((v_player->>'id')::uuid,p_team_id,trim(v_player->>'name'),
      (v_player->>'number')::integer,
      coalesce((v_player->>'inSquad')::boolean,true),
      coalesce((select array_agg(s) from jsonb_array_elements_text(
          coalesce(v_player->'preferredRoles','[]'::jsonb)) as s
          where s in ('K','F','M','A')),'{}'));
  end loop;
  return v_next;
end;
$$;

revoke all on function public.tb_sync_team_roster(uuid,text,jsonb,bigint) from public,anon;
grant execute on function public.tb_sync_team_roster(uuid,text,jsonb,bigint) to authenticated;

-- IMPORTANT: Prevent older app releases from overwriting a team without
-- a version check. New app version 53 uses tb_sync_team_roster instead.
revoke execute on function public.tb_save_team_roster(uuid,text,jsonb) from public,anon,authenticated;
