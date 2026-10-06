-- Hidden score composition. Inputs remain nullable and source-attributed; no stats are fabricated.
alter table player_stats add column if not exists stats_updated_at timestamptz;

create or replace function public.player_hidden_score(p_player_id uuid)
returns numeric language plpgsql stable security definer set search_path=public,pg_temp as $$
declare p players; s player_stats; recent numeric; ipl numeric; t20 numeric; role numeric;
begin
  select * into p from players where id=p_player_id; select * into s from player_stats where player_id=p_player_id;
  role:=case when p.wicketkeeper then 78 when p.specialism ilike '%ALL-ROUNDER%' then 76 when p.specialism ilike '%BOWL%' then 72 else 74 end;
  recent:=coalesce(s.recent_ipl_score,s.overall_t20_score,s.overall_ipl_score,role);
  ipl:=coalesce(s.overall_ipl_score,s.overall_t20_score,recent);
  t20:=coalesce(s.overall_t20_score,s.recent_ipl_score,s.overall_ipl_score,role);
  if coalesce(s.ipl_matches,0)>=20 and s.overall_ipl_score is not null then return round(recent*.45+ipl*.35+t20*.15+role*.05,2); end if;
  return round(recent*.60+t20*.35+role*.05,2);
end;
$$;

create or replace function public.auto_pick_xi(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; s squads; ids uuid[];
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key); select * into s from squads where room_id=p_room_id and squads.member_id=v_member for update;
  if s.qualification_status<>'QUALIFIED' then raise exception using message='TEAM_NOT_QUALIFIED'; end if;
  if s.xi_locked then raise exception using message='TEAM_ALREADY_LOCKED'; end if;
  select array_agg(id) into ids from (select p.id from squad_players sp join players p on p.id=sp.player_id where sp.squad_id=s.id order by p.wicketkeeper desc,(p.specialism ilike '%BOWL%') desc,public.player_hidden_score(p.id) desc,p.base_price_lakh desc,p.full_name limit 11) q;
  perform public.assert_valid_xi(p_room_id,s.id,ids); delete from playing_xi where squad_id=s.id; insert into playing_xi(squad_id,player_id,batting_position,locked) select s.id,id,row_number() over(),false from unnest(ids) id; update squads set xi_auto_selected=true where id=s.id; return jsonb_build_object('ok',true,'selected',11);
end;
$$;

create or replace function public.calculate_team_ovr(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare s squads; quality numeric; balance numeric; depth numeric;
begin
  for s in select * from squads where room_id=p_room_id and qualification_status='QUALIFIED' loop
    if not s.xi_locked then raise exception using message='QUALIFIED_TEAM_NOT_LOCKED'; end if;
    select coalesce(avg(public.player_hidden_score(x.player_id)),70) into quality from playing_xi x where x.squad_id=s.id;
    select least(100,greatest(40,70+(count(*) filter(where p.wicketkeeper)>0)::int*5+(count(*) filter(where p.specialism ilike '%BOWL%')>=4)::int*8+(count(*) filter(where p.specialism ilike '%ALL-ROUNDER%')>=2)::int*3)) into balance from playing_xi x join players p on p.id=x.player_id where x.squad_id=s.id;
    depth:=least(100,60+(select count(*) from squad_players where squad_id=s.id)*1.5);
    insert into team_ratings(squad_id,team_ovr,xi_quality,balance_score,depth_score,released_at) values(s.id,round(quality*.85+balance*.10+depth*.05)::int,quality,balance,depth,now()) on conflict(squad_id) do update set team_ovr=excluded.team_ovr,xi_quality=excluded.xi_quality,balance_score=excluded.balance_score,depth_score=excluded.depth_score,released_at=excluded.released_at;
  end loop;
  update rooms set status='TOURNAMENT_READY' where id=p_room_id; update auction_state set status='TOURNAMENT_READY',updated_at=now() where room_id=p_room_id; return jsonb_build_object('ok',true);
end;
$$;

revoke execute on function public.player_hidden_score(uuid) from public,anon,authenticated;
revoke execute on function public.auto_pick_xi(uuid,text), public.calculate_team_ovr(uuid) from public,anon,authenticated;
