-- Deterministic, persisted scorecards and balanced playoff progression.
-- This migration intentionally exposes no new client-executable mutation RPC.

create or replace function public.simulate_one_match(p_match_id uuid, p_tournament_id uuid, p_room_id uuid)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  m matches; home_ovr integer; away_ovr integer; home_score integer; away_score integer;
  home_w integer; away_w integer; seed bigint; winner uuid; condition text;
  home_bat jsonb; away_bat jsonb; home_bowl jsonb; away_bowl jsonb;
begin
  select * into m from matches where id=p_match_id for update;
  if m.home_score is not null then return m.winner_franchise_id; end if;
  select coalesce(team_ovr,70) into home_ovr from team_ratings tr join squads s on s.id=tr.squad_id where s.room_id=p_room_id and s.franchise_id=m.home_franchise_id;
  select coalesce(team_ovr,70) into away_ovr from team_ratings tr join squads s on s.id=tr.squad_id where s.room_id=p_room_id and s.franchise_id=m.away_franchise_id;
  seed := ('x'||substr(md5(p_tournament_id::text||':'||m.match_number::text),1,16))::bit(64)::bigint;
  condition := case abs(seed % 4)::int when 0 then 'Balanced' when 1 then 'Batting friendly' when 2 then 'Pace friendly' else 'Spin friendly' end;
  home_score := greatest(95,least(235,round(154+(home_ovr-75)*1.15+((seed%25)-12))::int));
  away_score := greatest(95,least(235,round(151+(away_ovr-75)*1.15+(((seed/31)%25)-12))::int));
  home_w := least(9,greatest(2,((abs(seed)%6)+3)::int)); away_w := least(9,greatest(2,((abs(seed/7)%6)+3)::int));
  if home_score=away_score then winner := case when seed%2=0 then m.home_franchise_id else m.away_franchise_id end;
  elsif home_score>away_score then winner := m.home_franchise_id; else winner := m.away_franchise_id; end if;
  select coalesce(jsonb_agg(jsonb_build_object('player_id',x.player_id,'runs',greatest(0,(abs(hashtext(x.player_id::text||m.match_number::text))%42)+case when x.batting_position<=3 then 12 else 4 end),'balls',greatest(1,(abs(hashtext('b'||x.player_id::text||m.match_number::text))%28)+5),'dismissed',x.batting_position<=home_w) order by x.batting_position),'[]') into home_bat from playing_xi x join squads s on s.id=x.squad_id where s.room_id=p_room_id and s.franchise_id=m.home_franchise_id and x.locked;
  select coalesce(jsonb_agg(jsonb_build_object('player_id',x.player_id,'runs',greatest(0,(abs(hashtext(x.player_id::text||m.match_number::text))%42)+case when x.batting_position<=3 then 12 else 4 end),'balls',greatest(1,(abs(hashtext('b'||x.player_id::text||m.match_number::text))%28)+5),'dismissed',x.batting_position<=away_w) order by x.batting_position),'[]') into away_bat from playing_xi x join squads s on s.id=x.squad_id where s.room_id=p_room_id and s.franchise_id=m.away_franchise_id and x.locked;
  select coalesce(jsonb_agg(jsonb_build_object('player_id',x.player_id,'overs',case when row_number() over(order by x.player_id)<=5 then 4 else 0 end,'runs',greatest(8,(abs(hashtext('r'||x.player_id::text||m.match_number::text))%42)+18),'wickets',case when row_number() over(order by x.player_id)<=5 then abs(hashtext('w'||x.player_id::text||m.match_number::text))%3 else 0 end) order by x.player_id),'[]') into home_bowl from playing_xi x join squads s on s.id=x.squad_id where s.room_id=p_room_id and s.franchise_id=m.home_franchise_id and x.locked and exists(select 1 from players p where p.id=x.player_id and (p.bowling_style is not null or p.specialism ilike '%BOWL%' or p.specialism ilike '%ALL-ROUNDER%'));
  select coalesce(jsonb_agg(jsonb_build_object('player_id',x.player_id,'overs',case when row_number() over(order by x.player_id)<=5 then 4 else 0 end,'runs',greatest(8,(abs(hashtext('r'||x.player_id::text||m.match_number::text))%42)+18),'wickets',case when row_number() over(order by x.player_id)<=5 then abs(hashtext('w'||x.player_id::text||m.match_number::text))%3 else 0 end) order by x.player_id),'[]') into away_bowl from playing_xi x join squads s on s.id=x.squad_id where s.room_id=p_room_id and s.franchise_id=m.away_franchise_id and x.locked and exists(select 1 from players p where p.id=x.player_id and (p.bowling_style is not null or p.specialism ilike '%BOWL%' or p.specialism ilike '%ALL-ROUNDER%'));
  update matches set home_score=home_score||'/'||home_w, away_score=away_score||'/'||away_w, home_wickets=home_w, away_wickets=away_w, winner_franchise_id=winner, result_text=case when home_score=away_score then 'Super Over: ' else '' end||(select code from franchises where id=winner)||' won', winner_margin=case when home_score=away_score then 'by Super Over' when winner=m.home_franchise_id then (home_score-away_score)||' runs' else 'by '||(10-away_w)||' wickets' end, conditions=condition, toss_winner_franchise_id=case when seed%2=0 then m.home_franchise_id else m.away_franchise_id end, toss_decision=case when seed%2=0 then 'BAT' else 'BOWL' end, simulation_seed=seed, played_at=coalesce(m.played_at,now()), home_batting=home_bat, away_batting=away_bat, home_bowling=home_bowl, away_bowling=away_bowl where id=m.id;
  return winner;
end;
$$;

create or replace function public.simulate_tournament(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare member_id uuid; t tournaments; m matches; v_winner uuid; v_ids uuid[]; first_id uuid; second_id uuid; third_id uuid; fourth_id uuid; q1_winner uuid; elim_winner uuid; q2_winner uuid; final_winner uuid; q1_loser uuid; q2_loser uuid;
begin
  member_id:=public.assert_room_session(p_room_id,p_session_key);
  select * into t from tournaments where room_id=p_room_id for update;
  if t.id is null then raise exception using message='TOURNAMENT_NOT_STARTED'; end if;
  if t.status='COMPLETED' then return jsonb_build_object('ok',true,'already_complete',true); end if;
  for m in select * from matches where tournament_id=t.id and stage='LEAGUE' and home_score is null order by match_number loop perform public.simulate_one_match(m.id,t.id,p_room_id); end loop;
  delete from standings where tournament_id=t.id;
  insert into standings(tournament_id,franchise_id,played,won,lost,points,net_run_rate)
    select t.id,s.franchise_id,count(m.id),count(m.id) filter(where m.winner_franchise_id=s.franchise_id),count(m.id) filter(where m.winner_franchise_id is not null and m.winner_franchise_id<>s.franchise_id),2*count(m.id) filter(where m.winner_franchise_id=s.franchise_id),coalesce(sum(case when m.home_franchise_id=s.franchise_id then split_part(m.home_score,'/',1)::numeric/20-split_part(m.away_score,'/',1)::numeric/20 else split_part(m.away_score,'/',1)::numeric/20-split_part(m.home_score,'/',1)::numeric/20 end),0) from squads s left join matches m on m.tournament_id=t.id and m.stage='LEAGUE' and (m.home_franchise_id=s.franchise_id or m.away_franchise_id=s.franchise_id) where s.room_id=p_room_id and s.qualification_status='QUALIFIED' group by s.franchise_id;
  select array_agg(franchise_id order by points desc,net_run_rate desc,franchise_id) into v_ids from standings where tournament_id=t.id;
  if coalesce(array_length(v_ids,1),0)=2 then first_id:=v_ids[1]; second_id:=v_ids[2];
  elsif array_length(v_ids,1)=3 then first_id:=v_ids[1]; second_id:=v_ids[2];
  else first_id:=v_ids[1]; second_id:=v_ids[2]; third_id:=v_ids[3]; fourth_id:=v_ids[4];
    insert into matches(tournament_id,stage,match_number,home_franchise_id,away_franchise_id) select t.id,'QUALIFIER_1',1001,first_id,second_id where not exists(select 1 from matches where tournament_id=t.id and match_number=1001);
    insert into matches(tournament_id,stage,match_number,home_franchise_id,away_franchise_id) select t.id,'ELIMINATOR',1002,third_id,fourth_id where not exists(select 1 from matches where tournament_id=t.id and match_number=1002);
    select * into m from matches where tournament_id=t.id and match_number=1001; q1_winner:=public.simulate_one_match(m.id,t.id,p_room_id); q1_loser:=case when m.home_franchise_id=q1_winner then m.away_franchise_id else m.home_franchise_id end;
    select * into m from matches where tournament_id=t.id and match_number=1002; elim_winner:=public.simulate_one_match(m.id,t.id,p_room_id);
    insert into matches(tournament_id,stage,match_number,home_franchise_id,away_franchise_id) select t.id,'QUALIFIER_2',1003,q1_loser,elim_winner where not exists(select 1 from matches where tournament_id=t.id and match_number=1003);
    select * into m from matches where tournament_id=t.id and match_number=1003; q2_winner:=public.simulate_one_match(m.id,t.id,p_room_id); first_id:=q1_winner; second_id:=q2_winner;
  end if;
  insert into matches(tournament_id,stage,match_number,home_franchise_id,away_franchise_id) select t.id,'FINAL',1004,first_id,second_id where not exists(select 1 from matches where tournament_id=t.id and match_number=1004);
  select * into m from matches where tournament_id=t.id and match_number=1004; final_winner:=public.simulate_one_match(m.id,t.id,p_room_id);
  update tournaments set status='COMPLETED',completed_at=coalesce(completed_at,now()),champion_franchise_id=final_winner where id=t.id;
  update rooms set status='COMPLETED' where id=p_room_id; update auction_state set status='COMPLETED',updated_at=now() where room_id=p_room_id;
  return jsonb_build_object('ok',true,'completed',true,'champion_franchise_id',final_winner);
end;
$$;

revoke execute on function public.simulate_one_match(uuid,uuid,uuid), public.simulate_tournament(uuid,text) from public,anon,authenticated;
grant execute on function public.simulate_tournament(uuid,text) to service_role;
