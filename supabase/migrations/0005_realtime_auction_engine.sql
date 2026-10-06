-- Phase 3: anonymous-session, database-authoritative auction engine.
-- The public RPC surface accepts an opaque room session key. Sensitive tables
-- remain write-protected; all mutations below run in one transaction.

create table if not exists auction_events (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms(id) on delete cascade,
  event_type text not null check (event_type in ('AUCTION_STARTED','BID','SOLD','UNSOLD','AUCTION_PAUSED','AUCTION_RESUMED','SET_COMPLETED','AUCTION_ENDED','MEMBER_JOINED','MEMBER_RECONNECTED')),
  player_id uuid references players(id),
  franchise_id uuid references franchises(id),
  amount_lakh integer,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table room_auction_queue add column if not exists official_set_code text;
alter table room_auction_queue add column if not exists completed_at timestamptz;
alter table room_auction_queue add column if not exists sale_price_lakh integer;
alter table room_auction_queue add column if not exists winning_franchise_id uuid references franchises(id);
alter table squads add column if not exists qualification_status text not null default 'PENDING' check (qualification_status in ('PENDING','QUALIFIED','ELIMINATED'));
alter table squads add column if not exists overseas_count integer not null default 0 check (overseas_count between 0 and 8);

update room_auction_queue q
set official_set_code = s.official_set_code
from auction_sets s
where q.set_no = s.official_set_no and q.official_set_code is null;

alter table room_auction_queue alter column official_set_code set not null;
with ordered as (select id, row_number() over(order by official_set_no, official_set_code)::int as new_order from auction_sets where official_set_code <> 'M0')
update auction_sets s set set_order = case when s.official_set_code='M0' then 0 else o.new_order end from ordered o where s.id=o.id;
create index if not exists auction_events_room_created_idx on auction_events(room_id, created_at desc);
create index if not exists queue_room_status_idx on room_auction_queue(room_id, status, set_no);

alter table auction_events enable row level security;
alter table room_auction_queue enable row level security;
alter table bids enable row level security;
alter table player_stats enable row level security;
alter table team_ratings enable row level security;

-- There are intentionally no direct anon/authenticated SELECT policies for
-- events, bids, or the queue. The session-validated snapshot RPC below is the
-- only public read surface and never includes hidden queue columns.

revoke insert, update, delete, truncate on rooms, room_members, room_auction_queue, auction_state, bids, squads, squad_players, playing_xi, player_stats, team_ratings, tournaments, matches, standings, auction_events from anon, authenticated;
create or replace function public.next_bid_amount(p_current integer)
returns integer language sql immutable set search_path = public, pg_temp as $$
  select p_current + case when p_current < 100 then 5 when p_current < 200 then 10 when p_current < 500 then 20 else 25 end
$$;

create or replace function public.assert_room_session(p_room_id uuid, p_session_key text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_member uuid;
begin
  select id into v_member from room_members where room_id = p_room_id and session_key = p_session_key and status <> 'LEFT' for update;
  if v_member is null then raise exception using errcode = 'P0001', message = 'ROOM_SESSION_INVALID'; end if;
  update room_members set status = 'CONNECTED', last_seen_at = now() where id = v_member;
  return v_member;
end;
$$;

create or replace function public.create_auction_room(p_display_name text, p_franchise_code text, p_minimum_squad_size integer, p_timer_seconds integer, p_privacy text default 'PRIVATE')
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_room rooms; v_member room_members; v_franchise franchises; v_session text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''); v_code text;
begin
  if length(trim(p_display_name)) not between 1 and 40 then raise exception using message = 'DISPLAY_NAME_INVALID'; end if;
  if p_minimum_squad_size not in (15,20) then raise exception using message = 'MINIMUM_SQUAD_INVALID'; end if;
  if p_timer_seconds not in (8,10,15) then raise exception using message = 'TIMER_INVALID'; end if;
  select * into v_franchise from franchises where code = upper(p_franchise_code);
  if v_franchise.id is null then raise exception using message = 'FRANCHISE_INVALID'; end if;
  loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    exit when not exists(select 1 from rooms where room_code = v_code);
  end loop;
  insert into rooms(room_code, minimum_squad_size, auction_timer_seconds, privacy) values(v_code, p_minimum_squad_size, p_timer_seconds, upper(coalesce(p_privacy,'PRIVATE'))) returning * into v_room;
  insert into room_members(room_id, display_name, franchise_id, session_key) values(v_room.id, trim(p_display_name), v_franchise.id, v_session) returning * into v_member;
  update rooms set host_member_id = v_member.id where id = v_room.id returning * into v_room;
  insert into squads(room_id, franchise_id, member_id) values(v_room.id, v_franchise.id, v_member.id);
  insert into auction_state(room_id) values(v_room.id);
  insert into auction_events(room_id,event_type,franchise_id,payload) values(v_room.id,'MEMBER_JOINED',v_franchise.id,jsonb_build_object('display_name',v_member.display_name,'franchise_code',v_franchise.code));
  return jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,'member_id',v_member.id,'session_key',v_session,'is_host',true);
end;
$$;

create or replace function public.join_auction_room(p_room_code text, p_display_name text, p_session_key text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_room rooms; v_member room_members; v_session text := coalesce(nullif(p_session_key,''), replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''));
begin
  select * into v_room from rooms where room_code = upper(trim(p_room_code)) for update;
  if v_room.id is null then raise exception using message = 'ROOM_NOT_FOUND'; end if;
  if v_room.status <> 'WAITING' then raise exception using message = 'AUCTION_ALREADY_STARTED'; end if;
  if p_session_key is not null then
    select * into v_member from room_members where room_id=v_room.id and session_key=p_session_key;
    if v_member.id is not null then update room_members set status='CONNECTED',last_seen_at=now(),display_name=trim(p_display_name) where id=v_member.id; return jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,'member_id',v_member.id,'session_key',p_session_key,'is_host',v_member.id=v_room.host_member_id); end if;
  end if;
  if (select count(*) from room_members where room_id=v_room.id and status <> 'LEFT') >= 10 then raise exception using message = 'ROOM_FULL'; end if;
  insert into room_members(room_id, display_name, session_key) values(v_room.id,trim(p_display_name),v_session) returning * into v_member;
  insert into auction_events(room_id,event_type,payload) values(v_room.id,'MEMBER_JOINED',jsonb_build_object('display_name',v_member.display_name));
  return jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,'member_id',v_member.id,'session_key',v_session,'is_host',false);
end;
$$;

create or replace function public.choose_franchise(p_room_id uuid, p_franchise_id uuid, p_session_key text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_member uuid; v_room rooms; v_squad squads;
begin
  v_member := public.assert_room_session(p_room_id,p_session_key);
  select * into v_room from rooms where id=p_room_id for update;
  if v_room.status <> 'WAITING' then raise exception using message = 'AUCTION_ALREADY_STARTED'; end if;
  if exists(select 1 from room_members where room_id=p_room_id and franchise_id=p_franchise_id and id<>v_member and status<>'LEFT') then raise exception using message = 'FRANCHISE_ALREADY_SELECTED'; end if;
  update room_members set franchise_id=p_franchise_id where id=v_member;
  insert into squads(room_id,franchise_id,member_id) values(p_room_id,p_franchise_id,v_member) on conflict(room_id,franchise_id) do update set member_id=excluded.member_id;
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.choose_franchise_by_code(p_room_id uuid, p_franchise_code text, p_session_key text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_franchise uuid;
begin
  select id into v_franchise from franchises where code=upper(trim(p_franchise_code));
  if v_franchise is null then raise exception using message='FRANCHISE_INVALID'; end if;
  return public.choose_franchise(p_room_id,v_franchise,p_session_key);
end;
$$;

create or replace function public.start_auction(p_room_id uuid, p_session_key text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_member uuid; v_room rooms; v_state auction_state; v_first room_auction_queue; v_set auction_sets;
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_room from rooms where id=p_room_id for update;
  if v_room.host_member_id<>v_member then raise exception using message='NOT_HOST'; end if;
  if v_room.status<>'WAITING' then raise exception using message='AUCTION_ALREADY_STARTED'; end if;
  if exists(select 1 from room_members where room_id=p_room_id and franchise_id is null and status<>'LEFT') then raise exception using message='FRANCHISE_SELECTION_INCOMPLETE'; end if;
  if not exists(select 1 from room_auction_queue where room_id=p_room_id) then
    insert into room_auction_queue(room_id,player_id,set_no,official_set_code,random_position_in_set,overall_queue_position)
    select p_room_id,p.id,p.official_set_no,p.official_set_code,row_number() over(partition by p.official_set_code order by random()),row_number() over(order by s.set_order,random())
    from players p join auction_sets s on s.official_set_no=p.official_set_no and s.official_set_code=p.official_set_code;
  end if;
  select * into v_first from room_auction_queue where room_id=p_room_id and status='AVAILABLE' order by overall_queue_position limit 1;
  select * into v_set from auction_sets where official_set_no=v_first.set_no and official_set_code=v_first.official_set_code;
  update room_auction_queue set status='CURRENT' where id=v_first.id;
  update auction_state set status='RUNNING',current_set_no=v_first.set_no,current_set_code=v_first.official_set_code,current_player_id=v_first.player_id,current_bid_lakh=0,highest_bidder_team_id=null,timer_ends_at=now()+make_interval(secs=>v_room.auction_timer_seconds),current_queue_position=v_first.overall_queue_position,updated_at=now() where room_id=p_room_id returning * into v_state;
  update rooms set status='RUNNING' where id=p_room_id;
  insert into auction_events(room_id,event_type,player_id,payload) values(p_room_id,'AUCTION_STARTED',v_first.player_id,jsonb_build_object('set_code',v_first.official_set_code));
  return jsonb_build_object('ok',true,'state',to_jsonb(v_state));
end;
$$;

create or replace function public.place_bid(p_room_id uuid, p_expected_player_id uuid, p_session_key text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_member uuid; v_state auction_state; v_room rooms; v_squad squads; v_amount integer; v_needed integer; v_reserve integer := 0; v_overseas boolean;
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_room from rooms where id=p_room_id; select * into v_state from auction_state where room_id=p_room_id for update;
  if v_state.status<>'RUNNING' then raise exception using message=case when v_state.status='PAUSED' then 'AUCTION_PAUSED' else 'AUCTION_NOT_RUNNING' end; end if;
  if v_state.timer_ends_at <= now() then raise exception using message='TIMER_EXPIRED'; end if;
  if v_state.current_player_id<>p_expected_player_id then raise exception using message='STALE_PLAYER'; end if;
  select * into v_squad from squads where room_id=p_room_id and member_id=v_member for update;
  if v_squad.id is null then raise exception using message='NOT_TEAM_OWNER'; end if;
  if v_state.highest_bidder_team_id=v_squad.franchise_id then raise exception using message='ALREADY_HIGHEST_BIDDER'; end if;
  select overseas into v_overseas from players where id=v_state.current_player_id;
  if v_squad.overseas_count >= 8 and v_overseas then raise exception using message='OVERSEAS_LIMIT_REACHED'; end if;
  if (select count(*) from squad_players where squad_id=v_squad.id) >= v_room.maximum_squad_size then raise exception using message='SQUAD_LIMIT_REACHED'; end if;
  v_amount:=case when v_state.current_bid_lakh=0 then (select base_price_lakh from players where id=v_state.current_player_id) else public.next_bid_amount(v_state.current_bid_lakh) end;
  if v_squad.purse_remaining_lakh < v_amount then raise exception using message='INSUFFICIENT_PURSE'; end if;
  v_needed:=greatest(v_room.minimum_squad_size-(select count(*) from squad_players where squad_id=v_squad.id)-1,0);
  if v_needed>0 then select coalesce(sum(base_price_lakh),0) into v_reserve from (select p.base_price_lakh from room_auction_queue q join players p on p.id=q.player_id where q.room_id=p_room_id and q.status='AVAILABLE' and q.player_id<>v_state.current_player_id order by p.base_price_lakh limit v_needed) cheapest; end if;
  if v_squad.purse_remaining_lakh-v_amount < v_reserve then raise exception using message='MINIMUM_SQUAD_RESERVE_REQUIRED'; end if;
  insert into bids(room_id,player_id,member_id,franchise_id,amount_lakh) values(p_room_id,v_state.current_player_id,v_member,v_squad.franchise_id,v_amount);
  update auction_state set current_bid_lakh=v_amount,highest_bidder_team_id=v_squad.franchise_id,timer_ends_at=now()+make_interval(secs=>v_room.auction_timer_seconds),updated_at=now() where room_id=p_room_id returning * into v_state;
  insert into auction_events(room_id,event_type,player_id,franchise_id,amount_lakh,payload) values(p_room_id,'BID',v_state.current_player_id,v_squad.franchise_id,v_amount,jsonb_build_object('display_name',(select display_name from room_members where id=v_member),'next_increment',public.next_bid_amount(v_amount)-v_amount));
  return jsonb_build_object('ok',true,'amount_lakh',v_amount,'state',to_jsonb(v_state));
end;
$$;

create or replace function public.advance_auction_player(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_state auction_state; v_next room_auction_queue; v_next_set auction_sets; v_room rooms;
begin
  select * into v_room from rooms where id=p_room_id; select * into v_state from auction_state where room_id=p_room_id for update;
  if v_state.status<>'RUNNING' or v_state.timer_ends_at is null or v_state.timer_ends_at>now() then return jsonb_build_object('advanced',false); end if;
  select * into v_next from room_auction_queue where room_id=p_room_id and status='AVAILABLE' order by overall_queue_position limit 1;
  if v_next.id is null then update rooms set status='QUALIFICATION' where id=p_room_id; update auction_state set status='QUALIFICATION',current_player_id=null,timer_ends_at=null,updated_at=now() where room_id=p_room_id; update squads set qualification_status=case when (select count(*) from squad_players sp where sp.squad_id=squads.id)>=v_room.minimum_squad_size then 'QUALIFIED' else 'ELIMINATED' end where room_id=p_room_id; insert into auction_events(room_id,event_type,payload) values(p_room_id,'AUCTION_ENDED',jsonb_build_object('reason','POOL_COMPLETE')); return jsonb_build_object('advanced',true,'ended',true); end if;
  if v_state.highest_bidder_team_id is not null then
    insert into squad_players(squad_id,player_id,purchase_price_lakh) select s.id,v_state.current_player_id,v_state.current_bid_lakh from squads s where s.room_id=p_room_id and s.franchise_id=v_state.highest_bidder_team_id;
    update squads s set purse_remaining_lakh=s.purse_remaining_lakh-v_state.current_bid_lakh, overseas_count=s.overseas_count+case when (select overseas from players where id=v_state.current_player_id) then 1 else 0 end where s.room_id=p_room_id and s.franchise_id=v_state.highest_bidder_team_id;
    update room_auction_queue set status='SOLD',completed_at=now(),sale_price_lakh=v_state.current_bid_lakh,winning_franchise_id=v_state.highest_bidder_team_id where room_id=p_room_id and player_id=v_state.current_player_id;
    insert into auction_events(room_id,event_type,player_id,franchise_id,amount_lakh) values(p_room_id,'SOLD',v_state.current_player_id,v_state.highest_bidder_team_id,v_state.current_bid_lakh);
  else
    update room_auction_queue set status='UNSOLD',completed_at=now() where room_id=p_room_id and player_id=v_state.current_player_id;
    insert into auction_events(room_id,event_type,player_id) values(p_room_id,'UNSOLD',v_state.current_player_id);
  end if;
  select * into v_next from room_auction_queue where room_id=p_room_id and status='AVAILABLE' order by overall_queue_position limit 1;
  select * into v_next_set from auction_sets where official_set_no=v_next.set_no and official_set_code=v_next.official_set_code;
  update room_auction_queue set status='CURRENT' where id=v_next.id;
  update auction_state set current_set_no=v_next.set_no,current_set_code=v_next.official_set_code,current_player_id=v_next.player_id,current_bid_lakh=0,highest_bidder_team_id=null,timer_ends_at=now()+make_interval(secs=>v_room.auction_timer_seconds),current_queue_position=v_next.overall_queue_position,updated_at=now() where room_id=p_room_id;
  return jsonb_build_object('advanced',true,'ended',false,'current_player_id',v_next.player_id);
end;
$$;

create or replace function public.settle_current_player(p_room_id uuid,p_session_key text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$ begin perform public.assert_room_session(p_room_id,p_session_key); return public.advance_auction_player(p_room_id); end; $$;

create or replace function public.pause_auction(p_room_id uuid,p_session_key text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_room rooms; v_state auction_state;
begin v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_room from rooms where id=p_room_id; select * into v_state from auction_state where room_id=p_room_id for update; if v_room.host_member_id<>v_member then raise exception using message='NOT_HOST'; end if; if v_state.status<>'RUNNING' then raise exception using message='INVALID_STATE_TRANSITION'; end if; update auction_state set status='PAUSED',timer_remaining_ms_when_paused=greatest(extract(epoch from (timer_ends_at-now()))*1000,0)::bigint,timer_ends_at=null,paused_at=now(),updated_at=now() where room_id=p_room_id returning * into v_state; update rooms set status='PAUSED' where id=p_room_id; insert into auction_events(room_id,event_type) values(p_room_id,'AUCTION_PAUSED'); return jsonb_build_object('ok',true,'remaining_ms',v_state.timer_remaining_ms_when_paused); end; $$;

create or replace function public.resume_auction(p_room_id uuid,p_session_key text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_room rooms; v_state auction_state;
begin v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_room from rooms where id=p_room_id; select * into v_state from auction_state where room_id=p_room_id for update; if v_room.host_member_id<>v_member then raise exception using message='NOT_HOST'; end if; if v_state.status<>'PAUSED' then raise exception using message='INVALID_STATE_TRANSITION'; end if; update auction_state set status='RUNNING',timer_ends_at=now()+make_interval(secs=>greatest(timer_remaining_ms_when_paused,0)/1000.0),timer_remaining_ms_when_paused=null,paused_at=null,updated_at=now() where room_id=p_room_id; update rooms set status='RUNNING' where id=p_room_id; insert into auction_events(room_id,event_type) values(p_room_id,'AUCTION_RESUMED'); return jsonb_build_object('ok',true); end; $$;

create or replace function public.end_auction(p_room_id uuid,p_session_key text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_room rooms;
begin v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_room from rooms where id=p_room_id for update; if v_room.host_member_id<>v_member then raise exception using message='NOT_HOST'; end if; if v_room.status not in ('RUNNING','PAUSED') then raise exception using message='INVALID_STATE_TRANSITION'; end if; update rooms set status='QUALIFICATION' where id=p_room_id; update auction_state set status='QUALIFICATION',timer_ends_at=null,updated_at=now() where room_id=p_room_id; update squads set qualification_status=case when (select count(*) from squad_players sp where sp.squad_id=squads.id)>=v_room.minimum_squad_size then 'QUALIFIED' else 'ELIMINATED' end where room_id=p_room_id; insert into auction_events(room_id,event_type,payload) values(p_room_id,'AUCTION_ENDED',jsonb_build_object('reason','HOST_ENDED')); return jsonb_build_object('ok',true); end; $$;

create or replace function public.heartbeat_auction_member(p_room_id uuid,p_session_key text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$ declare v_member uuid; begin v_member:=public.assert_room_session(p_room_id,p_session_key); return jsonb_build_object('ok',true,'member_id',v_member); end; $$;

create or replace function public.get_auction_snapshot(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_room jsonb; v_state jsonb; v_self jsonb; v_players jsonb; v_members jsonb; v_squads jsonb; v_events jsonb;
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key);
  select to_jsonb(r) - 'host_member_id' into v_room from rooms r where id=p_room_id;
  select to_jsonb(a) into v_state from auction_state a where room_id=p_room_id;
  select jsonb_build_object('id',m.id,'display_name',m.display_name,'franchise_id',m.franchise_id,'franchise_code',(select code from franchises f where f.id=m.franchise_id),'status',m.status,'is_host',m.id=(select host_member_id from rooms where id=p_room_id)) into v_self from room_members m where m.id=v_member;
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'display_name',m.display_name,'franchise_id',m.franchise_id,'franchise_code',(select code from franchises f where f.id=m.franchise_id),'status',m.status,'is_host',m.id=(select host_member_id from rooms where id=p_room_id)) order by m.joined_at),'[]') into v_members from room_members m where m.room_id=p_room_id and m.status<>'LEFT';
  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'franchise_id',s.franchise_id,'franchise_code',(select code from franchises f where f.id=s.franchise_id),'purse_remaining_lakh',s.purse_remaining_lakh,'overseas_count',s.overseas_count,'squad_count',(select count(*) from squad_players sp where sp.squad_id=s.id),'qualification_status',s.qualification_status)),'[]') into v_squads from squads s where s.room_id=p_room_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'country',p.country,'specialism',p.specialism,'overseas',p.overseas,'base_price_lakh',p.base_price_lakh,'status',coalesce(q.status::text,'AVAILABLE'),'sale_price_lakh',q.sale_price_lakh,'winning_franchise_id',q.winning_franchise_id) order by lower(p.full_name)),'[]') into v_players from players p join room_auction_queue q on q.player_id=p.id and q.room_id=p_room_id where q.official_set_code=(select current_set_code from auction_state where room_id=p_room_id);
  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'event_type',e.event_type,'player_id',e.player_id,'franchise_id',e.franchise_id,'amount_lakh',e.amount_lakh,'payload',e.payload,'created_at',e.created_at) order by e.created_at desc),'[]') into v_events from (select * from auction_events where room_id=p_room_id order by created_at desc limit 30) e;
  return jsonb_build_object('room',v_room,'state',v_state,'self',v_self,'members',v_members,'squads',v_squads,'current_set_players',v_players,'events',v_events);
end;
$$;

revoke all on function public.next_bid_amount(integer) from public;
revoke all on function public.assert_room_session(uuid,text) from public;
revoke all on function public.advance_auction_player(uuid) from public;
revoke execute on function public.next_bid_amount(integer), public.assert_room_session(uuid,text), public.advance_auction_player(uuid), public.choose_franchise(uuid,uuid,text) from anon, authenticated, public;
revoke all on function public.create_auction_room(text,text,integer,integer,text) from public;
revoke all on function public.join_auction_room(text,text,text) from public;
revoke all on function public.choose_franchise(uuid,uuid,text) from public;
revoke all on function public.choose_franchise_by_code(uuid,text,text) from public;
revoke all on function public.start_auction(uuid,text) from public;
revoke all on function public.place_bid(uuid,uuid,text) from public;
revoke all on function public.settle_current_player(uuid,text) from public;
revoke all on function public.pause_auction(uuid,text) from public;
revoke all on function public.resume_auction(uuid,text) from public;
revoke all on function public.end_auction(uuid,text) from public;
revoke all on function public.get_auction_snapshot(uuid,text) from public;
revoke all on function public.heartbeat_auction_member(uuid,text) from public;
grant execute on function public.create_auction_room(text,text,integer,integer,text) to anon, authenticated;
grant execute on function public.join_auction_room(text,text,text) to anon, authenticated;
grant execute on function public.choose_franchise_by_code(uuid,text,text) to anon, authenticated;
grant execute on function public.start_auction(uuid,text) to anon, authenticated;
grant execute on function public.place_bid(uuid,uuid,text) to anon, authenticated;
grant execute on function public.settle_current_player(uuid,text) to anon, authenticated;
grant execute on function public.pause_auction(uuid,text) to anon, authenticated;
grant execute on function public.resume_auction(uuid,text) to anon, authenticated;
grant execute on function public.end_auction(uuid,text) to anon, authenticated;
grant execute on function public.get_auction_snapshot(uuid,text) to anon, authenticated;
grant execute on function public.heartbeat_auction_member(uuid,text) to anon, authenticated;
