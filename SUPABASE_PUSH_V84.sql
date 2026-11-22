-- Trenerbrettet v84: Kjor etter SUPABASE_LIVE_V83.sql.
-- Retter ogsaa pgcrypto-feilen i v83.
create extension if not exists pgcrypto with schema extensions;
create or replace function public.tb_live_create(p_team_id uuid,p_match_id text,p_show_names boolean default false)
returns text language plpgsql security definer set search_path='' as $$
declare v_token text;
begin
 if auth.uid() is null or p_team_id is null or length(coalesce(p_match_id,'')) not between 3 and 100 then raise exception 'Innlogging og gyldig kamp/lag kreves';end if;
 if not exists(select 1 from public.team_members where team_id=p_team_id and user_id=auth.uid() and role in ('admin','coach')) then raise exception 'Du har ikke trenertilgang til laget';end if;
 v_token=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.tb_live_matches(token,match_id,team_id,owner_id,payload)
 values(v_token,p_match_id,p_team_id,auth.uid(),jsonb_build_object('showNames',p_show_names));
 return v_token;
end;$$;
revoke all on function public.tb_live_create(uuid,text,boolean) from public,anon;
grant execute on function public.tb_live_create(uuid,text,boolean) to authenticated;

create table if not exists public.tb_push_subscriptions(
 id bigint generated always as identity primary key,
 token text not null references public.tb_live_matches(token) on delete cascade,
 endpoint text not null,
 subscription jsonb not null,
 created_at timestamptz not null default now(),
 unique(token,endpoint)
);
create table if not exists public.tb_push_deliveries(
 token text not null references public.tb_live_matches(token) on delete cascade,
 event_key text not null,
 created_at timestamptz not null default now(),
 primary key(token,event_key)
);
alter table public.tb_push_subscriptions enable row level security;
alter table public.tb_push_deliveries enable row level security;
revoke all on public.tb_push_subscriptions, public.tb_push_deliveries from anon,authenticated;
-- Backend accesses only with Netlify SUPABASE_SERVICE_ROLE_KEY.
