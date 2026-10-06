-- Final live-auction polish: stable timer errors and an explicit bidder identity
-- in the safe auction snapshot. Existing auction state and rules are unchanged.

create or replace function public.set_auction_timer(p_room_id uuid, p_timer_seconds integer, p_session_key text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_member uuid; v_room rooms;
begin
  v_member := public.assert_room_session(p_room_id, p_session_key);
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then raise exception using message = 'ROOM_NOT_FOUND'; end if;
  if v_room.host_member_id <> v_member then raise exception using message = 'NOT_HOST'; end if;
  if v_room.status <> 'WAITING' then raise exception using message = 'AUCTION_ALREADY_STARTED'; end if;
  if p_timer_seconds not in (5, 8, 10, 15, 20, 25) then raise exception using message = 'INVALID_AUCTION_TIMER'; end if;
  update rooms set auction_timer_seconds = p_timer_seconds where id = p_room_id;
  return jsonb_build_object('ok', true, 'timer_seconds', p_timer_seconds);
end;
$$;

create or replace function public.get_auction_snapshot(p_room_id uuid, p_session_key text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_member uuid; v_room jsonb; v_state jsonb; v_self jsonb; v_players jsonb; v_members jsonb; v_squads jsonb; v_events jsonb;
begin
  v_member := public.assert_room_session(p_room_id, p_session_key);
  select to_jsonb(r) - 'host_member_id' into v_room from rooms r where id = p_room_id;
  select to_jsonb(a) || jsonb_build_object(
    'highest_bidder_franchise_id', a.highest_bidder_team_id,
    'highest_bidder_franchise_code', (select f.code from franchises f where f.id = a.highest_bidder_team_id)
  ) into v_state from auction_state a where room_id = p_room_id;
  select jsonb_build_object('id',m.id,'display_name',m.display_name,'franchise_id',m.franchise_id,'franchise_code',(select code from franchises f where f.id=m.franchise_id),'status',m.status,'is_host',m.id=(select host_member_id from rooms where id=p_room_id)) into v_self from room_members m where m.id=v_member;
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'display_name',m.display_name,'franchise_id',m.franchise_id,'franchise_code',(select code from franchises f where f.id=m.franchise_id),'status',m.status,'is_host',m.id=(select host_member_id from rooms where id=p_room_id)) order by m.joined_at),'[]') into v_members from room_members m where m.room_id=p_room_id and m.status<>'LEFT';
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,
    'franchise_id',s.franchise_id,
    'franchise_code',(select code from franchises f where f.id=s.franchise_id),
    'purse_remaining_lakh',s.purse_remaining_lakh,
    'overseas_count',s.overseas_count,
    'squad_count',(select count(*) from squad_players sp where sp.squad_id=s.id),
    'qualification_status',s.qualification_status,
    'players',coalesce((select jsonb_agg(jsonb_build_object('player_id',p.id,'full_name',p.full_name,'country',p.country,'specialism',p.specialism,'overseas',p.overseas,'purchase_price_lakh',sp.purchase_price_lakh,'acquired_at',sp.acquired_at) order by sp.acquired_at) from squad_players sp join players p on p.id=sp.player_id where sp.squad_id=s.id),'[]'::jsonb)
  )),'[]') into v_squads from squads s where s.room_id=p_room_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'country',p.country,'specialism',p.specialism,'overseas',p.overseas,'base_price_lakh',p.base_price_lakh,'status',coalesce(q.status::text,'AVAILABLE'),'sale_price_lakh',q.sale_price_lakh,'winning_franchise_id',q.winning_franchise_id,'winning_franchise_code',(select code from franchises f where f.id=q.winning_franchise_id)) order by lower(p.full_name)),'[]') into v_players from players p join room_auction_queue q on q.player_id=p.id and q.room_id=p_room_id where q.official_set_code=(select current_set_code from auction_state where room_id=p_room_id);
  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'event_type',e.event_type,'player_id',e.player_id,'franchise_id',e.franchise_id,'amount_lakh',e.amount_lakh,'payload',e.payload,'created_at',e.created_at) order by e.created_at desc),'[]') into v_events from (select * from auction_events where room_id=p_room_id order by created_at desc limit 30) e;
  return jsonb_build_object('room',v_room,'state',v_state,'self',v_self,'members',v_members,'squads',v_squads,'current_set_players',v_players,'events',v_events);
end;
$$;

