-- One authoritative definition of a source-verified player profile. The
-- workspace and tournament assertion both call this function.
alter table public.player_stats add column if not exists recent_form_from date;

create or replace function public.get_player_stats_readiness()
returns jsonb
language sql stable security definer set search_path=public,pg_temp as $$
  with counts as (
    select
      (select count(*)::integer from public.players) as total_profiles,
      (select count(*)::integer from public.player_stats
       where coverage_level in ('IPL','T20')
         and stats_source is not null
         and stats_as_of is not null
         and stats_updated_at is not null) as verified_profiles
  )
  select jsonb_build_object(
    'stats_total_profiles', total_profiles,
    'stats_verified_profiles', verified_profiles,
    'stats_missing_profiles', greatest(total_profiles - verified_profiles, 0),
    'stats_ready', total_profiles >= 620 and verified_profiles = total_profiles
  ) from counts;
$$;
revoke execute on function public.get_player_stats_readiness() from public,anon,authenticated;

create or replace function public.assert_verified_player_stats_ready()
returns void language plpgsql stable security definer set search_path=public,pg_temp as $$
declare readiness jsonb;
begin
  readiness := public.get_player_stats_readiness();
  if not coalesce((readiness->>'stats_ready')::boolean, false) then
    raise exception using message='PLAYER_STATS_NOT_READY',
      detail=format('verified=%s total=%s missing=%s',
        readiness->>'stats_verified_profiles', readiness->>'stats_total_profiles',
        readiness->>'stats_missing_profiles');
  end if;
end;
$$;
revoke execute on function public.assert_verified_player_stats_ready() from public,anon,authenticated;

create or replace function public.get_team_workspace(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_member uuid;
  v_squad squads;
  v_room jsonb;
  v_players jsonb;
  v_xi jsonb;
  v_qualified jsonb;
  v_qualified_count integer;
  v_locked_count integer;
  v_stats jsonb;
begin
  v_member := public.assert_room_session(p_room_id,p_session_key);
  select * into v_squad from squads where room_id=p_room_id and member_id=v_member;
  select to_jsonb(r)-'host_member_id' into v_room from rooms r where id=p_room_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'full_name',p.full_name,'country',p.country,'specialism',p.specialism,
    'overseas',p.overseas,'wicketkeeper',p.wicketkeeper,'batting_style',p.batting_style,
    'bowling_style',p.bowling_style,'purchase_price_lakh',sp.purchase_price_lakh,
    'batting_position',coalesce(x.batting_position,0),'selected',x.id is not null
  ) order by coalesce(x.batting_position,99),lower(p.full_name)),'[]')
  into v_players from squad_players sp join players p on p.id=sp.player_id
  left join playing_xi x on x.squad_id=sp.squad_id and x.player_id=sp.player_id
  where sp.squad_id=v_squad.id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'player_id',x.player_id,'batting_position',x.batting_position,'locked',x.locked
  ) order by x.batting_position),'[]') into v_xi
  from playing_xi x where x.squad_id=v_squad.id;
  select count(*) into v_qualified_count from squads
    where room_id=p_room_id and qualification_status='QUALIFIED';
  select count(*) into v_locked_count from squads
    where room_id=p_room_id and qualification_status='QUALIFIED' and xi_locked;
  select coalesce(jsonb_agg(jsonb_build_object(
    'squad_id',s.id,'franchise_id',s.franchise_id,
    'franchise_code',(select code from franchises f where f.id=s.franchise_id),
    'owner_name',(select display_name from room_members m where m.id=s.member_id),
    'qualification_status',s.qualification_status,'xi_locked',s.xi_locked
  ) order by (case when s.xi_locked then 0 else 1 end),
    (select code from franchises f where f.id=s.franchise_id)),'[]') into v_qualified
  from squads s where s.room_id=p_room_id and s.qualification_status='QUALIFIED';
  v_stats := public.get_player_stats_readiness();
  return jsonb_build_object(
    'room',v_room,
    'squad',jsonb_build_object('id',v_squad.id,'franchise_id',v_squad.franchise_id,
      'purse_remaining_lakh',v_squad.purse_remaining_lakh,
      'squad_count',(select count(*) from squad_players where squad_id=v_squad.id),
      'overseas_count',v_squad.overseas_count,'qualification_status',v_squad.qualification_status,
      'xi_locked',v_squad.xi_locked,'xi_auto_selected',v_squad.xi_auto_selected),
    'players',v_players,'xi',v_xi,'qualified_teams',v_qualified,
    'qualified_count',v_qualified_count,'locked_qualified_count',v_locked_count,
    'all_ready',v_qualified_count>=2 and v_locked_count=v_qualified_count,
    'verified_profiles',(v_stats->>'stats_verified_profiles')::integer,
    'total_profiles',(v_stats->>'stats_total_profiles')::integer,
    'missing_profiles',(v_stats->>'stats_missing_profiles')::integer,
    'stats_ready',(v_stats->>'stats_ready')::boolean
  );
end;
$$;

-- A profile without source-verified performance data has no hidden strength.
create or replace function public.player_hidden_score(p_player_id uuid)
returns numeric language plpgsql stable security definer set search_path=public,pg_temp as $$
declare p players; s player_stats; recent numeric; ipl numeric; t20 numeric; role numeric;
begin
  select * into p from players where id=p_player_id;
  select * into s from player_stats where player_id=p_player_id;
  if not found or s.coverage_level not in ('IPL','T20') or s.stats_source is null
    or s.stats_as_of is null or s.stats_updated_at is null then return null; end if;
  role:=case when p.wicketkeeper then 78 when p.specialism ilike '%ALL-ROUNDER%' then 76 when p.specialism ilike '%BOWL%' then 72 else 74 end;
  recent:=coalesce(s.recent_ipl_score,s.overall_t20_score,s.overall_ipl_score,role);
  ipl:=coalesce(s.overall_ipl_score,s.overall_t20_score,recent);
  t20:=coalesce(s.overall_t20_score,s.recent_ipl_score,s.overall_ipl_score,role);
  if coalesce(s.ipl_matches,0)>=20 and s.overall_ipl_score is not null then return round(recent*.45+ipl*.35+t20*.15+role*.05,2); end if;
  return round(recent*.60+t20*.35+role*.05,2);
end;
$$;
revoke execute on function public.player_hidden_score(uuid) from public,anon,authenticated;

create or replace function public.get_tournament_snapshot(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_teams jsonb; v_tournament jsonb; v_matches jsonb; v_standings jsonb; v_released boolean := false; v_stats jsonb;
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key);
  select exists(select 1 from tournaments where room_id=p_room_id and status='COMPLETED') into v_released;
  select coalesce(jsonb_agg(jsonb_build_object(
    'franchise_id',s.franchise_id,'franchise_code',(select code from franchises f where f.id=s.franchise_id),
    'team_ovr',case when v_released then tr.team_ovr else null end,
    'squad_count',(select count(*) from squad_players where squad_id=s.id),
    'qualification_status',s.qualification_status,'xi_locked',s.xi_locked
  ) order by (case when v_released then tr.team_ovr end) desc nulls last,
    (select code from franchises f where f.id=s.franchise_id)),'[]') into v_teams
  from squads s left join team_ratings tr on tr.squad_id=s.id where s.room_id=p_room_id;
  select to_jsonb(t) into v_tournament from tournaments t where t.room_id=p_room_id;
  select coalesce(jsonb_agg(to_jsonb(m) order by m.match_number),'[]') into v_matches
    from matches m join tournaments t on t.id=m.tournament_id where t.room_id=p_room_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'franchise_id',st.franchise_id,'franchise_code',(select code from franchises f where f.id=st.franchise_id),
    'played',st.played,'won',st.won,'lost',st.lost,'points',st.points,'net_run_rate',st.net_run_rate
  ) order by st.points desc,st.net_run_rate desc),'[]') into v_standings
    from standings st join tournaments t on t.id=st.tournament_id where t.room_id=p_room_id;
  v_stats:=public.get_player_stats_readiness();
  return jsonb_build_object('teams',v_teams,'tournament',v_tournament,'matches',v_matches,'standings',v_standings,
    'stats_total_profiles',(v_stats->>'stats_total_profiles')::integer,
    'stats_verified_profiles',(v_stats->>'stats_verified_profiles')::integer,
    'stats_missing_profiles',(v_stats->>'stats_missing_profiles')::integer,
    'stats_ready',(v_stats->>'stats_ready')::boolean);
end;
$$;
