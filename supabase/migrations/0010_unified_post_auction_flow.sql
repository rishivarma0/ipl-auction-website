-- Unified lobby/team/tournament flow. Existing auction rules and hidden queue remain unchanged.

alter table rooms drop constraint if exists rooms_auction_timer_seconds_check;
alter table rooms add constraint rooms_auction_timer_seconds_check check (auction_timer_seconds in (5, 8, 10, 15, 20, 25));

create or replace function public.create_auction_room(p_display_name text, p_franchise_code text, p_minimum_squad_size integer, p_timer_seconds integer, p_privacy text default 'PRIVATE')
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_room rooms; v_member room_members; v_franchise franchises; v_session text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''); v_code text;
begin
  if length(trim(p_display_name)) not between 1 and 40 then raise exception using message = 'DISPLAY_NAME_INVALID'; end if;
  if p_minimum_squad_size not in (15,20) then raise exception using message = 'MINIMUM_SQUAD_INVALID'; end if;
  if p_timer_seconds not in (5,8,10,15,20,25) then raise exception using message = 'TIMER_INVALID'; end if;
  if nullif(trim(p_franchise_code), '') is not null then
    select * into v_franchise from franchises where code = upper(trim(p_franchise_code));
    if v_franchise.id is null then raise exception using message = 'FRANCHISE_INVALID'; end if;
  end if;
  loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    exit when not exists(select 1 from rooms where room_code = v_code);
  end loop;
  insert into rooms(room_code, minimum_squad_size, auction_timer_seconds, privacy) values(v_code, p_minimum_squad_size, p_timer_seconds, upper(coalesce(p_privacy,'PRIVATE'))) returning * into v_room;
  insert into room_members(room_id, display_name, franchise_id, session_key) values(v_room.id, trim(p_display_name), v_franchise.id, v_session) returning * into v_member;
  update rooms set host_member_id = v_member.id where id = v_room.id returning * into v_room;
  if v_franchise.id is not null then insert into squads(room_id, franchise_id, member_id) values(v_room.id, v_franchise.id, v_member.id); end if;
  insert into auction_state(room_id) values(v_room.id);
  insert into auction_events(room_id,event_type,franchise_id,payload) values(v_room.id,'MEMBER_JOINED',v_franchise.id,jsonb_build_object('display_name',v_member.display_name,'franchise_code',v_franchise.code));
  return jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,'member_id',v_member.id,'session_key',v_session,'is_host',true);
end;
$$;

create or replace function public.set_auction_timer(p_room_id uuid, p_timer_seconds integer, p_session_key text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_member uuid; v_room rooms;
begin
  v_member := public.assert_room_session(p_room_id, p_session_key);
  if p_timer_seconds not in (5,8,10,15,20,25) then raise exception using message = 'TIMER_INVALID'; end if;
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then raise exception using message = 'ROOM_NOT_FOUND'; end if;
  if v_room.host_member_id <> v_member then raise exception using message = 'NOT_HOST'; end if;
  if v_room.status <> 'WAITING' then raise exception using message = 'TIMER_LOCKED'; end if;
  update rooms set auction_timer_seconds = p_timer_seconds where id = p_room_id;
  return jsonb_build_object('ok', true, 'timer_seconds', p_timer_seconds);
end;
$$;

create or replace function public.get_auction_snapshot(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare v_member uuid; v_room jsonb; v_state jsonb; v_self jsonb; v_players jsonb; v_members jsonb; v_squads jsonb; v_events jsonb;
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key);
  select to_jsonb(r) - 'host_member_id' into v_room from rooms r where id=p_room_id;
  select to_jsonb(a) into v_state from auction_state a where room_id=p_room_id;
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

create or replace function public.get_tournament_snapshot(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_teams jsonb; v_tournament jsonb; v_matches jsonb; v_standings jsonb; v_released boolean := false;
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key);
  select exists(select 1 from tournaments where room_id=p_room_id and status='COMPLETED') into v_released;
  select coalesce(jsonb_agg(jsonb_build_object('franchise_id',s.franchise_id,'franchise_code',(select code from franchises f where f.id=s.franchise_id),'team_ovr',case when v_released then tr.team_ovr else null end,'squad_count',(select count(*) from squad_players where squad_id=s.id),'qualification_status',s.qualification_status,'xi_locked',s.xi_locked) order by (case when v_released then tr.team_ovr end) desc nulls last,(select code from franchises f where f.id=s.franchise_id)),'[]') into v_teams from squads s left join team_ratings tr on tr.squad_id=s.id where s.room_id=p_room_id;
  select to_jsonb(t) into v_tournament from tournaments t where t.room_id=p_room_id;
  select coalesce(jsonb_agg(to_jsonb(m) order by m.match_number),'[]') into v_matches from matches m join tournaments t on t.id=m.tournament_id where t.room_id=p_room_id;
  select coalesce(jsonb_agg(jsonb_build_object('franchise_id',st.franchise_id,'franchise_code',(select code from franchises f where f.id=st.franchise_id),'played',st.played,'won',st.won,'lost',st.lost,'points',st.points,'net_run_rate',st.net_run_rate) order by st.points desc,st.net_run_rate desc),'[]') into v_standings from standings st join tournaments t on t.id=st.tournament_id where t.room_id=p_room_id;
  return jsonb_build_object('teams',v_teams,'tournament',v_tournament,'matches',v_matches,'standings',v_standings);
end;
$$;

create or replace function public.post_auction_command(p_room_id uuid,p_session_key text,p_command text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_ids uuid[];
begin
  case p_command
    when 'AUTO_PICK_XI' then return public.auto_pick_xi(p_room_id,p_session_key);
    when 'SAVE_XI' then select array_agg(value::text::uuid) into v_ids from jsonb_array_elements_text(coalesce(p_payload->'player_ids','[]'::jsonb)); return public.save_playing_xi(p_room_id,v_ids,p_session_key);
    when 'AUTO_SET_ORDER' then return public.auto_set_batting_order(p_room_id,p_session_key);
    when 'SAVE_BATTING_ORDER' then select array_agg(value::text::uuid) into v_ids from jsonb_array_elements_text(coalesce(p_payload->'player_ids','[]'::jsonb)); return public.save_batting_order(p_room_id,v_ids,p_session_key);
    when 'LOCK_TEAM' then return public.lock_team(p_room_id,p_session_key);
    when 'HOST_AUTO_LOCK' then return public.host_auto_lock_team(p_room_id,(p_payload->>'squad_id')::uuid,p_session_key);
    when 'CALCULATE_OVR' then return public.calculate_team_ovr(p_room_id);
    when 'START_TOURNAMENT' then perform public.calculate_team_ovr(p_room_id); perform public.start_tournament(p_room_id,p_session_key); return public.simulate_tournament(p_room_id,p_session_key);
    when 'SIMULATE_TOURNAMENT' then return public.simulate_tournament(p_room_id,p_session_key);
    else raise exception using message='UNKNOWN_AUCTION_COMMAND';
  end case;
end;
$$;

revoke all on function public.set_auction_timer(uuid,integer,text) from public;
grant execute on function public.set_auction_timer(uuid,integer,text) to anon, authenticated;
revoke execute on function public.create_auction_room(text,text,integer,integer,text), public.get_auction_snapshot(uuid,text) from public;
grant execute on function public.create_auction_room(text,text,integer,integer,text), public.get_auction_snapshot(uuid,text) to anon, authenticated;
revoke execute on function public.post_auction_command(uuid,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.post_auction_command(uuid,text,text,jsonb) to service_role;
