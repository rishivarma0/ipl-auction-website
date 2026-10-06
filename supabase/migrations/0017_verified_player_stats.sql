-- Verified Cricsheet-derived metrics. NULL means the source did not provide the metric.
alter table player_stats add column if not exists cricsheet_player_id text;
alter table player_stats add column if not exists coverage_level text check (coverage_level in ('IPL','T20','NO_VERIFIED_DATA'));
alter table player_stats add column if not exists mapping_method text;
alter table player_stats add column if not exists t20_matches integer;
alter table player_stats add column if not exists t20_runs integer;
alter table player_stats add column if not exists t20_wickets integer;
alter table player_stats add column if not exists t20_strike_rate numeric;
alter table player_stats add column if not exists t20_economy numeric;
alter table player_stats add column if not exists recent_form_matches integer;
alter table player_stats add column if not exists recent_form_as_of date;
alter table player_stats add column if not exists recent_form_score numeric;
alter table player_stats add column if not exists batting_score numeric;
alter table player_stats add column if not exists bowling_score numeric;
create unique index if not exists player_stats_cricsheet_id_idx on player_stats(cricsheet_player_id) where cricsheet_player_id is not null;

create or replace function public.assert_verified_player_stats_ready()
returns void language plpgsql stable security definer set search_path=public,pg_temp as $$
declare total_players integer; verified_players integer;
begin
  select count(*) into total_players from players;
  select count(*) into verified_players from player_stats where coverage_level in ('IPL','T20') and stats_source is not null and stats_as_of is not null and stats_updated_at is not null;
  if total_players < 620 or verified_players < total_players then
    raise exception using message='PLAYER_STATS_NOT_READY', detail=format('verified=%s total=%s',verified_players,total_players);
  end if;
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
    when 'START_TOURNAMENT' then perform public.assert_verified_player_stats_ready(); perform public.calculate_team_ovr(p_room_id); perform public.start_tournament(p_room_id,p_session_key); return public.simulate_tournament(p_room_id,p_session_key);
    when 'SIMULATE_TOURNAMENT' then perform public.assert_verified_player_stats_ready(); return public.simulate_tournament(p_room_id,p_session_key);
    else raise exception using message='UNKNOWN_AUCTION_COMMAND';
  end case;
end;
$$;
revoke execute on function public.assert_verified_player_stats_ready() from public,anon,authenticated;
revoke execute on function public.post_auction_command(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.post_auction_command(uuid,text,text,jsonb) to service_role;
