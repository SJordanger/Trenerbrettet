-- Kjor i Supabase SQL Editor. Krever eksisterende public.team_members.
create table if not exists public.tb_live_matches (
 token text primary key, match_id text not null, team_id uuid not null references public.teams(id),
 owner_id uuid not null references auth.users(id), payload jsonb not null default '{}'::jsonb,
 active boolean not null default true, updated_at timestamptz not null default now(),
 created_at timestamptz not null default now()
);
alter table public.tb_live_matches enable row level security;
revoke all on public.tb_live_matches from anon,authenticated;
create or replace function public.tb_live_create(p_team_id uuid,p_match_id text,p_show_names boolean default false)
returns text language plpgsql security definer set search_path='' as $$
declare v_token text;
begin
 if auth.uid() is null or p_team_id is null or length(coalesce(p_match_id,'')) not between 3 and 100 then raise exception 'Innlogging og gyldig kamp/lag kreves';end if;
 if not exists(select 1 from public.team_members where team_id=p_team_id and user_id=auth.uid() and role in ('admin','coach')) then raise exception 'Du har ikke trenertilgang til laget';end if;
 v_token=encode(gen_random_bytes(32),'hex');
 insert into public.tb_live_matches(token,match_id,team_id,owner_id,payload)
 values(v_token,p_match_id,p_team_id,auth.uid(),jsonb_build_object('showNames',p_show_names));
 return v_token;
end;$$;
create or replace function public.tb_live_publish(p_token text,p_payload jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare v_team uuid;
begin
 select team_id into v_team from public.tb_live_matches where token=p_token and active=true and owner_id=auth.uid();
 if v_team is null or not exists(select 1 from public.team_members where team_id=v_team and user_id=auth.uid() and role in ('admin','coach')) then raise exception 'Ingen tilgang til livekamp';end if;
 if pg_column_size(p_payload)>60000 or jsonb_typeof(p_payload->'events') is distinct from 'array' or jsonb_array_length(p_payload->'events')>200 then raise exception 'Ugyldige live-data';end if;
 update public.tb_live_matches set payload=p_payload,updated_at=now() where token=p_token and active=true;
end;$$;
create or replace function public.tb_live_view(p_token text)
returns jsonb language sql security definer set search_path='' as $$
 select payload from public.tb_live_matches where token=p_token and active=true
$$;
create or replace function public.tb_live_stop(p_token text)
returns void language plpgsql security definer set search_path='' as $$
begin
 update public.tb_live_matches set active=false where token=p_token and owner_id=auth.uid();
end;$$;
revoke all on function public.tb_live_create(uuid,text,boolean) from public,anon;
revoke all on function public.tb_live_publish(text,jsonb) from public,anon;
revoke all on function public.tb_live_view(text) from public;
revoke all on function public.tb_live_stop(text) from public,anon;
grant execute on function public.tb_live_create(uuid,text,boolean) to authenticated;
grant execute on function public.tb_live_publish(text,jsonb) to authenticated;
grant execute on function public.tb_live_stop(text) to authenticated;
grant execute on function public.tb_live_view(text) to anon,authenticated;
