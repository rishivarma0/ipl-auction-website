-- Score only from the imported match performance metrics; never fall back to
-- unverified placeholders or pre-import seeded ratings.
create or replace function public.player_hidden_score(p_player_id uuid)
returns numeric language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
  p players;
  s player_stats;
  v_role numeric;
  v_recent numeric;
  v_ipl numeric;
  v_t20 numeric;
  v_selected numeric;
  v_t20_bat numeric;
  v_t20_bowl numeric;
begin
  select * into p from public.players where id=p_player_id;
  select * into s from public.player_stats where player_id=p_player_id;
  if not found or s.coverage_level not in ('IPL','T20') or s.stats_source is null
    or s.stats_as_of is null or s.stats_updated_at is null then return null; end if;

  v_role := case when p.wicketkeeper then 78
    when p.specialism ilike '%ALL-ROUNDER%' then 76
    when p.specialism ilike '%BOWL%' then 72 else 74 end;
  v_selected := case
    when p.specialism ilike '%ALL-ROUNDER%' then
      case when s.batting_score is not null and s.bowling_score is not null then (s.batting_score+s.bowling_score)/2
        else coalesce(s.batting_score,s.bowling_score) end
    when p.specialism ilike '%BOWL%' and not p.wicketkeeper then s.bowling_score
    else s.batting_score end;
  v_recent := coalesce(s.recent_form_score,v_selected);

  if coalesce(s.t20_matches,0)>0 then
    v_t20_bat := case when s.t20_runs is not null and s.t20_strike_rate is not null
      then least(100,greatest(0,35+s.t20_strike_rate*.30+(s.t20_runs::numeric/s.t20_matches)*.35)) end;
    v_t20_bowl := case when s.t20_economy is not null and s.t20_wickets is not null
      then least(100,greatest(0,110-s.t20_economy*8+least(30,s.t20_wickets*.4))) end;
    v_t20 := case
      when p.specialism ilike '%ALL-ROUNDER%' then
        case when v_t20_bat is not null and v_t20_bowl is not null then (v_t20_bat+v_t20_bowl)/2
          else coalesce(v_t20_bat,v_t20_bowl,v_selected) end
      when p.specialism ilike '%BOWL%' and not p.wicketkeeper then coalesce(v_t20_bowl,v_selected)
      else coalesce(v_t20_bat,v_selected) end;
  else v_t20 := v_selected; end if;

  if s.coverage_level='IPL' then v_ipl := v_selected; end if;
  if coalesce(s.ipl_matches,0)>=20 and v_ipl is not null then
    return round(coalesce(v_recent,v_role)*.45+v_ipl*.35+coalesce(v_t20,v_ipl)*.15+v_role*.05,2);
  end if;
  return round(coalesce(v_recent,v_role)*.60+coalesce(v_t20,v_recent,v_role)*.35+v_role*.05,2);
end;
$$;
revoke execute on function public.player_hidden_score(uuid) from public,anon,authenticated;
