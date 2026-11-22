-- Trenerbrettet v85: utloep for livelenker. Kjoer etter SUPABASE_PUSH_V84.sql.
-- Lenken virker til 6 timer etter at kampen er avsluttet, og senest 7 dager etter at den ble opprettet.
-- updated_at oppdateres bare naar innholdet faktisk endres, slik at en aapen app ikke holder lenken i live.

create or replace function public.tb_live_view(p_token text)
returns jsonb language sql security definer set search_path='' as $$
 select payload from public.tb_live_matches
 where token=p_token and active=true
   and created_at > now() - interval '7 days'
   and (payload->>'status' is distinct from 'finished' or updated_at > now() - interval '6 hours')
$$;

create or replace function public.tb_live_publish(p_token text,p_payload jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare v_team uuid;
begin
 select team_id into v_team from public.tb_live_matches where token=p_token and active=true and owner_id=auth.uid();
 if v_team is null or not exists(select 1 from public.team_members where team_id=v_team and user_id=auth.uid() and role in ('admin','coach')) then raise exception 'Ingen tilgang til livekamp';end if;
 if pg_column_size(p_payload)>60000 or jsonb_typeof(p_payload->'events') is distinct from 'array' or jsonb_array_length(p_payload->'events')>200 then raise exception 'Ugyldige live-data';end if;
 update public.tb_live_matches
    set updated_at = case when payload is distinct from p_payload then now() else updated_at end,
        payload = p_payload
  where token=p_token and active=true;
end;$$;

revoke all on function public.tb_live_view(text) from public;
revoke all on function public.tb_live_publish(text,jsonb) from public,anon;
grant execute on function public.tb_live_view(text) to anon,authenticated;
grant execute on function public.tb_live_publish(text,jsonb) to authenticated;
