-- Final product phase: qualified-team XI selection, hidden-stat-aware team
-- evaluation, deterministic tournament persistence, and safe public snapshots.

alter table player_stats add column if not exists stats_source text;
alter table player_stats add column if not exists stats_as_of date;
alter table squads add column if not exists xi_locked boolean not null default false;
alter table squads add column if not exists xi_auto_selected boolean not null default false;

alter table matches add column if not exists toss_winner_franchise_id uuid references franchises(id);
alter table matches add column if not exists toss_decision text;
alter table matches add column if not exists conditions text;
alter table matches add column if not exists home_wickets integer;
alter table matches add column if not exists away_wickets integer;
alter table matches add column if not exists winner_margin text;
alter table matches add column if not exists home_batting jsonb not null default '[]'::jsonb;
alter table matches add column if not exists away_batting jsonb not null default '[]'::jsonb;
alter table matches add column if not exists home_bowling jsonb not null default '[]'::jsonb;
alter table matches add column if not exists away_bowling jsonb not null default '[]'::jsonb;
alter table matches add column if not exists simulation_seed bigint;

create index if not exists playing_xi_locked_idx on playing_xi(squad_id, locked);
create index if not exists squads_room_qualification_idx on squads(room_id, qualification_status, xi_locked);

alter table player_stats enable row level security;
alter table team_ratings enable row level security;
alter table tournaments enable row level security;
alter table matches enable row level security;
alter table standings enable row level security;
revoke insert, update, delete, truncate on player_stats, team_ratings, tournaments, matches, standings from anon, authenticated;

create or replace function public.assert_valid_xi(p_room_id uuid, p_squad_id uuid, p_player_ids uuid[])
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_count integer; v_overseas integer; v_wk integer; v_bowling integer; v_frontline integer;
begin
  if coalesce(array_length(p_player_ids,1),0) <> 11 then raise exception using message='XI_MUST_HAVE_11'; end if;
  select count(*) into v_count from (select distinct unnest(p_player_ids) as id) ids;
  if v_count <> 11 then raise exception using message='XI_DUPLICATE_PLAYER'; end if;
  if (select count(*) from squad_players where squad_id=p_squad_id and player_id=any(p_player_ids)) <> 11 then raise exception using message='XI_PLAYER_NOT_OWNED'; end if;
  select count(*) filter (where p.overseas), count(*) filter (where p.wicketkeeper), count(*) filter (where p.bowling_style is not null or p.specialism ilike '%BOWL%' or p.specialism ilike '%ALL-ROUNDER%'), count(*) filter (where p.specialism ilike '%BOWL%') into v_overseas,v_wk,v_bowling,v_frontline from players p where p.id=any(p_player_ids);
  if v_overseas > 4 then raise exception using message='XI_OVERSEAS_LIMIT'; end if;
  if v_wk < 1 then raise exception using message='XI_WICKETKEEPER_REQUIRED'; end if;
  if v_bowling < 4 or v_frontline < 1 then raise exception using message='XI_BOWLING_CAPABILITY_REQUIRED'; end if;
end;
$$;

create or replace function public.complete_qualification(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_room rooms;
begin
  select * into v_room from rooms where id=p_room_id for update;
  update squads s set qualification_status=case when (select count(*) from squad_players sp where sp.squad_id=s.id)>=v_room.minimum_squad_size then 'QUALIFIED' else 'ELIMINATED' end where s.room_id=p_room_id;
  update rooms set status='XI_SELECTION' where id=p_room_id and status in ('QUALIFICATION','ENDED');
  update auction_state set status='XI_SELECTION',updated_at=now() where room_id=p_room_id and status in ('QUALIFICATION','ENDED');
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.end_auction(p_room_id uuid,p_session_key text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_room rooms;
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_room from rooms where id=p_room_id for update;
  if v_room.host_member_id<>v_member then raise exception using message='NOT_HOST'; end if;
  if v_room.status not in ('RUNNING','PAUSED') then raise exception using message='INVALID_STATE_TRANSITION'; end if;
  update rooms set status='XI_SELECTION' where id=p_room_id;
  update auction_state set status='XI_SELECTION',timer_ends_at=null,updated_at=now() where room_id=p_room_id;
  update squads set qualification_status=case when (select count(*) from squad_players sp where sp.squad_id=squads.id)>=v_room.minimum_squad_size then 'QUALIFIED' else 'ELIMINATED' end where room_id=p_room_id;
  insert into auction_events(room_id,event_type,payload) values(p_room_id,'AUCTION_ENDED',jsonb_build_object('reason','HOST_ENDED'));
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.get_team_workspace(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_squad squads; v_room jsonb; v_players jsonb; v_xi jsonb;
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key);
  select * into v_squad from squads where room_id=p_room_id and member_id=v_member;
  select to_jsonb(r)-'host_member_id' into v_room from rooms r where id=p_room_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'country',p.country,'specialism',p.specialism,'overseas',p.overseas,'wicketkeeper',p.wicketkeeper,'batting_style',p.batting_style,'bowling_style',p.bowling_style,'purchase_price_lakh',sp.purchase_price_lakh,'batting_position',coalesce(x.batting_position,0),'selected',x.id is not null) order by coalesce(x.batting_position,99),lower(p.full_name)),'[]') into v_players from squad_players sp join players p on p.id=sp.player_id left join playing_xi x on x.squad_id=sp.squad_id and x.player_id=sp.player_id where sp.squad_id=v_squad.id;
  select coalesce(jsonb_agg(jsonb_build_object('player_id',x.player_id,'batting_position',x.batting_position,'locked',x.locked) order by x.batting_position),'[]') into v_xi from playing_xi x where x.squad_id=v_squad.id;
  return jsonb_build_object('room',v_room,'squad',jsonb_build_object('id',v_squad.id,'franchise_id',v_squad.franchise_id,'purse_remaining_lakh',v_squad.purse_remaining_lakh,'squad_count',(select count(*) from squad_players where squad_id=v_squad.id),'overseas_count',v_squad.overseas_count,'qualification_status',v_squad.qualification_status,'xi_locked',v_squad.xi_locked,'xi_auto_selected',v_squad.xi_auto_selected),'players',v_players,'xi',v_xi);
end;
$$;

create or replace function public.save_playing_xi(p_room_id uuid,p_player_ids uuid[],p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_squad squads; i integer;
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_squad from squads where room_id=p_room_id and member_id=v_member for update;
  if v_squad.qualification_status<>'QUALIFIED' then raise exception using message='TEAM_NOT_QUALIFIED'; end if;
  if v_squad.xi_locked then raise exception using message='TEAM_ALREADY_LOCKED'; end if;
  perform public.assert_valid_xi(p_room_id,v_squad.id,p_player_ids);
  delete from playing_xi where squad_id=v_squad.id;
  for i in 1..11 loop insert into playing_xi(squad_id,player_id,batting_position,locked) values(v_squad.id,p_player_ids[i],i,false); end loop;
  return jsonb_build_object('ok',true,'selected',11);
end;
$$;

create or replace function public.auto_pick_xi(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_squad squads; v_ids uuid[];
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_squad from squads where room_id=p_room_id and member_id=v_member for update;
  if v_squad.qualification_status<>'QUALIFIED' then raise exception using message='TEAM_NOT_QUALIFIED'; end if;
  if v_squad.xi_locked then raise exception using message='TEAM_ALREADY_LOCKED'; end if;
  select array_agg(id) into v_ids from (select p.id from squad_players sp join players p on p.id=sp.player_id left join player_stats ps on ps.player_id=p.id where sp.squad_id=v_squad.id order by p.wicketkeeper desc, (p.specialism ilike '%BOWL%') desc, (p.specialism ilike '%ALL-ROUNDER%') desc, ps.overall_hidden_score desc nulls last, p.base_price_lakh desc, p.full_name limit 11) chosen;
  perform public.assert_valid_xi(p_room_id,v_squad.id,v_ids);
  delete from playing_xi where squad_id=v_squad.id;
  insert into playing_xi(squad_id,player_id,batting_position,locked) select v_squad.id,id,row_number() over(),false from unnest(v_ids) id;
  update squads set xi_auto_selected=true where id=v_squad.id;
  return jsonb_build_object('ok',true,'selected',11);
end;
$$;

create or replace function public.save_batting_order(p_room_id uuid,p_player_ids uuid[],p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_squad squads; i integer;
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_squad from squads where room_id=p_room_id and member_id=v_member for update;
  if v_squad.xi_locked then raise exception using message='TEAM_ALREADY_LOCKED'; end if;
  if coalesce(array_length(p_player_ids,1),0)<>11 then raise exception using message='XI_MUST_HAVE_11'; end if;
  if (select count(*) from playing_xi where squad_id=v_squad.id and player_id=any(p_player_ids))<>11 then raise exception using message='BATTING_ORDER_REQUIRES_XI'; end if;
  for i in 1..11 loop update playing_xi set batting_position=i where squad_id=v_squad.id and player_id=p_player_ids[i]; end loop;
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.lock_team(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_squad squads; v_ids uuid[];
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_squad from squads where room_id=p_room_id and member_id=v_member for update;
  if v_squad.xi_locked then return jsonb_build_object('ok',true,'already_locked',true); end if;
  select array_agg(player_id order by batting_position) into v_ids from playing_xi where squad_id=v_squad.id;
  perform public.assert_valid_xi(p_room_id,v_squad.id,v_ids);
  if (select count(*) from playing_xi where squad_id=v_squad.id and batting_position between 1 and 11)<>11 then raise exception using message='BATTING_ORDER_REQUIRED'; end if;
  update playing_xi set locked=true where squad_id=v_squad.id;
  update squads set xi_locked=true where id=v_squad.id;
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.host_auto_lock_team(p_room_id uuid,p_target_squad_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_room rooms; v_squad squads; v_ids uuid[]; v_order uuid[];
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_room from rooms where id=p_room_id; if v_room.host_member_id<>v_member then raise exception using message='NOT_HOST'; end if;
  select * into v_squad from squads where id=p_target_squad_id and room_id=p_room_id for update; if v_squad.qualification_status<>'QUALIFIED' then raise exception using message='TEAM_NOT_QUALIFIED'; end if;
  select array_agg(id) into v_ids from (select p.id from squad_players sp join players p on p.id=sp.player_id left join player_stats ps on ps.player_id=p.id where sp.squad_id=v_squad.id order by p.wicketkeeper desc,(p.specialism ilike '%BOWL%') desc,ps.overall_hidden_score desc nulls last,p.base_price_lakh desc limit 11) q;
  perform public.assert_valid_xi(p_room_id,v_squad.id,v_ids); delete from playing_xi where squad_id=v_squad.id; insert into playing_xi(squad_id,player_id,batting_position,locked) select v_squad.id,id,row_number() over(),true from unnest(v_ids) id; update squads set xi_locked=true,xi_auto_selected=true where id=v_squad.id; return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.calculate_team_ovr(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_squad squads; v_quality numeric; v_balance numeric; v_depth numeric;
begin
  for v_squad in select * from squads where room_id=p_room_id and qualification_status='QUALIFIED' loop
    if not v_squad.xi_locked then raise exception using message='QUALIFIED_TEAM_NOT_LOCKED'; end if;
    select coalesce(avg(coalesce(ps.overall_hidden_score,case when p.wicketkeeper then 72 when p.specialism ilike '%BOWL%' then 70 when p.specialism ilike '%ALL-ROUNDER%' then 74 else 71 end)),70) into v_quality from playing_xi x join players p on p.id=x.player_id left join player_stats ps on ps.player_id=p.id where x.squad_id=v_squad.id;
    select least(100, greatest(40, 70 + (count(*) filter(where p.wicketkeeper)>0)::int*5 + (count(*) filter(where p.specialism ilike '%BOWL%')>=4)::int*8 + (count(*) filter(where p.overseas)<=4)::int*2)) into v_balance from playing_xi x join players p on p.id=x.player_id where x.squad_id=v_squad.id;
    v_depth:=least(100,60+(select count(*) from squad_players where squad_id=v_squad.id)*1.5);
    insert into team_ratings(squad_id,team_ovr,xi_quality,balance_score,depth_score,released_at) values(v_squad.id,round(v_quality*.85+v_balance*.10+v_depth*.05)::int,v_quality,v_balance,v_depth,now()) on conflict(squad_id) do update set team_ovr=excluded.team_ovr,xi_quality=excluded.xi_quality,balance_score=excluded.balance_score,depth_score=excluded.depth_score,released_at=excluded.released_at;
  end loop;
  update rooms set status='TOURNAMENT_READY' where id=p_room_id;
  update auction_state set status='TOURNAMENT_READY',updated_at=now() where room_id=p_room_id;
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.get_tournament_snapshot(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_teams jsonb; v_tournament jsonb; v_matches jsonb; v_standings jsonb;
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key);
  select coalesce(jsonb_agg(jsonb_build_object('franchise_id',s.franchise_id,'franchise_code',(select code from franchises f where f.id=s.franchise_id),'team_ovr',tr.team_ovr,'squad_count',(select count(*) from squad_players where squad_id=s.id),'qualification_status',s.qualification_status,'xi_locked',s.xi_locked) order by tr.team_ovr desc nulls last),'[]') into v_teams from squads s left join team_ratings tr on tr.squad_id=s.id where s.room_id=p_room_id;
  select to_jsonb(t) into v_tournament from tournaments t where t.room_id=p_room_id;
  select coalesce(jsonb_agg(to_jsonb(m) order by m.match_number),'[]') into v_matches from matches m join tournaments t on t.id=m.tournament_id where t.room_id=p_room_id;
  select coalesce(jsonb_agg(jsonb_build_object('franchise_id',st.franchise_id,'franchise_code',(select code from franchises f where f.id=st.franchise_id),'played',st.played,'won',st.won,'lost',st.lost,'points',st.points,'net_run_rate',st.net_run_rate) order by st.points desc,st.net_run_rate desc),'[]') into v_standings from standings st join tournaments t on t.id=st.tournament_id where t.room_id=p_room_id;
  return jsonb_build_object('teams',v_teams,'tournament',v_tournament,'matches',v_matches,'standings',v_standings);
end;
$$;

create or replace function public.start_tournament(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_room rooms; v_count integer; v_tournament tournaments; v_ids uuid[]; i integer; j integer; v_match_no integer:=0;
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_room from rooms where id=p_room_id for update; if v_room.host_member_id<>v_member then raise exception using message='NOT_HOST'; end if;
  if v_room.status not in ('TOURNAMENT_READY','SIMULATING') then raise exception using message='TOURNAMENT_NOT_READY'; end if;
  select count(*) into v_count from squads where room_id=p_room_id and qualification_status='QUALIFIED'; if v_count<2 then raise exception using message='TWO_QUALIFIED_TEAMS_REQUIRED'; end if;
  if exists(select 1 from squads where room_id=p_room_id and qualification_status='QUALIFIED' and not xi_locked) then raise exception using message='QUALIFIED_TEAM_NOT_LOCKED'; end if;
  insert into tournaments(room_id,status,started_at) values(p_room_id,'SIMULATING',now()) on conflict(room_id) do update set status=case when tournaments.status='READY' then 'SIMULATING' else tournaments.status end returning * into v_tournament;
  if exists(select 1 from matches where tournament_id=v_tournament.id) then return jsonb_build_object('ok',true,'already_started',true,'tournament_id',v_tournament.id); end if;
  select array_agg(franchise_id order by franchise_id) into v_ids from squads where room_id=p_room_id and qualification_status='QUALIFIED';
  for i in 1..array_length(v_ids,1) loop for j in i+1..array_length(v_ids,1) loop v_match_no:=v_match_no+1; insert into matches(tournament_id,stage,match_number,home_franchise_id,away_franchise_id) values(v_tournament.id,'LEAGUE',v_match_no,v_ids[i],v_ids[j]); v_match_no:=v_match_no+1; insert into matches(tournament_id,stage,match_number,home_franchise_id,away_franchise_id) values(v_tournament.id,'LEAGUE',v_match_no,v_ids[j],v_ids[i]); end loop; end loop;
  update rooms set status='SIMULATING' where id=p_room_id; update auction_state set status='SIMULATING',updated_at=now() where room_id=p_room_id;
  return jsonb_build_object('ok',true,'tournament_id',v_tournament.id,'league_matches',v_match_no);
end;
$$;

create or replace function public.simulate_tournament(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_tournament tournaments; v_match matches; v_home_ovr integer; v_away_ovr integer; v_home_score integer; v_away_score integer; v_winner uuid; v_home_w integer; v_away_w integer; v_seed bigint;
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_tournament from tournaments where room_id=p_room_id for update; if v_tournament.id is null then raise exception using message='TOURNAMENT_NOT_STARTED'; end if; if v_tournament.status='COMPLETED' then return jsonb_build_object('ok',true,'already_complete',true); end if;
  for v_match in select * from matches where tournament_id=v_tournament.id and home_score is null order by match_number for update loop
    select team_ovr into v_home_ovr from team_ratings tr join squads s on s.id=tr.squad_id where s.room_id=p_room_id and s.franchise_id=v_match.home_franchise_id;
    select team_ovr into v_away_ovr from team_ratings tr join squads s on s.id=tr.squad_id where s.room_id=p_room_id and s.franchise_id=v_match.away_franchise_id;
    v_seed:=('x'||substr(md5(v_tournament.id::text||':'||v_match.match_number::text),1,16))::bit(64)::bigint;
    v_home_score:=greatest(85,least(245,round(145+(coalesce(v_home_ovr,70)-75)*1.2+((v_seed%31)-15))::int));
    v_away_score:=greatest(85,least(245,round(145+(coalesce(v_away_ovr,70)-75)*1.2+(((v_seed/31)%31)-15))::int));
    v_home_w:=least(9,greatest(2,((abs(v_seed)%6)+3)::int)); v_away_w:=least(9,greatest(2,((abs(v_seed/7)%6)+3)::int));
    if v_home_score>=v_away_score then v_winner:=v_match.home_franchise_id; else v_winner:=v_match.away_franchise_id; end if;
    update matches set home_score=v_home_score||'/'||v_home_w,away_score=v_away_score||'/'||v_away_w,winner_franchise_id=v_winner,result_text=(select code from franchises where id=v_winner)||' won',winner_margin=abs(v_home_score-v_away_score)||' runs',conditions=(array['Balanced','Batting friendly','Pace friendly','Spin friendly'])[1+(abs(v_seed)%4)::int],toss_winner_franchise_id=case when v_seed%2=0 then v_match.home_franchise_id else v_match.away_franchise_id end,toss_decision=case when v_seed%2=0 then 'BAT' else 'BOWL' end,simulation_seed=v_seed,played_at=now(),home_batting='[]',away_batting='[]',home_bowling='[]',away_bowling='[]' where id=v_match.id;
  end loop;
  delete from standings where tournament_id=v_tournament.id;
  insert into standings(tournament_id,franchise_id,played,won,lost,points,net_run_rate) select v_tournament.id,s.franchise_id,count(m.id),count(m.id) filter(where m.winner_franchise_id=s.franchise_id),count(m.id) filter(where m.winner_franchise_id is not null and m.winner_franchise_id<>s.franchise_id),2*count(m.id) filter(where m.winner_franchise_id=s.franchise_id),coalesce(sum(case when m.home_franchise_id=s.franchise_id then split_part(m.home_score,'/',1)::numeric/nullif(split_part(m.away_score,'/',1)::numeric,0) else split_part(m.away_score,'/',1)::numeric/nullif(split_part(m.home_score,'/',1)::numeric,0) end - 1),0) from squads s left join matches m on m.tournament_id=v_tournament.id and (m.home_franchise_id=s.franchise_id or m.away_franchise_id=s.franchise_id) where s.room_id=p_room_id and s.qualification_status='QUALIFIED' group by s.franchise_id;
  update tournaments set status='COMPLETED',completed_at=now() where id=v_tournament.id; update rooms set status='COMPLETED' where id=p_room_id; update auction_state set status='COMPLETED',updated_at=now() where room_id=p_room_id;
  return jsonb_build_object('ok',true,'completed',true);
end;
$$;

create or replace function public.post_auction_command(p_room_id uuid,p_session_key text,p_command text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_ids uuid[];
begin
  case p_command
    when 'AUTO_PICK_XI' then return public.auto_pick_xi(p_room_id,p_session_key);
    when 'SAVE_XI' then select array_agg(value::text::uuid) into v_ids from jsonb_array_elements_text(coalesce(p_payload->'player_ids','[]'::jsonb)); return public.save_playing_xi(p_room_id,v_ids,p_session_key);
    when 'SAVE_BATTING_ORDER' then select array_agg(value::text::uuid) into v_ids from jsonb_array_elements_text(coalesce(p_payload->'player_ids','[]'::jsonb)); return public.save_batting_order(p_room_id,v_ids,p_session_key);
    when 'LOCK_TEAM' then return public.lock_team(p_room_id,p_session_key);
    when 'HOST_AUTO_LOCK' then return public.host_auto_lock_team(p_room_id,(p_payload->>'squad_id')::uuid,p_session_key);
    when 'CALCULATE_OVR' then return public.calculate_team_ovr(p_room_id);
    when 'START_TOURNAMENT' then return public.start_tournament(p_room_id,p_session_key);
    when 'SIMULATE_TOURNAMENT' then return public.simulate_tournament(p_room_id,p_session_key);
    else raise exception using message='UNKNOWN_AUCTION_COMMAND';
  end case;
end;
$$;

revoke execute on function public.assert_valid_xi(uuid,uuid,uuid[]), public.complete_qualification(uuid), public.save_playing_xi(uuid,uuid[],text), public.auto_pick_xi(uuid,text), public.save_batting_order(uuid,uuid[],text), public.lock_team(uuid,text), public.host_auto_lock_team(uuid,uuid,text), public.calculate_team_ovr(uuid), public.start_tournament(uuid,text), public.simulate_tournament(uuid,text) from anon,authenticated,public;
revoke execute on function public.post_auction_command(uuid,text,text,jsonb), public.get_team_workspace(uuid,text), public.get_tournament_snapshot(uuid,text) from public,anon,authenticated;
grant execute on function public.post_auction_command(uuid,text,text,jsonb), public.get_team_workspace(uuid,text), public.get_tournament_snapshot(uuid,text) to service_role;
