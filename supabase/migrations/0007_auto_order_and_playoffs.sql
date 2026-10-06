create or replace function public.auto_set_batting_order(p_room_id uuid,p_session_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid; v_squad squads; v_ids uuid[];
begin
  v_member:=public.assert_room_session(p_room_id,p_session_key); select * into v_squad from squads where room_id=p_room_id and member_id=v_member for update;
  if v_squad.xi_locked then raise exception using message='TEAM_ALREADY_LOCKED'; end if;
  select array_agg(p.id order by case when p.specialism ilike '%BATTER%' and p.specialism not ilike '%ALL-ROUNDER%' then 1 when p.specialism ilike '%ALL-ROUNDER%' then 2 when p.wicketkeeper then 3 else 4 end,p.wicketkeeper desc,p.full_name) into v_ids from playing_xi x join players p on p.id=x.player_id where x.squad_id=v_squad.id;
  if coalesce(array_length(v_ids,1),0)<>11 then raise exception using message='XI_MUST_HAVE_11'; end if;
  return public.save_batting_order(p_room_id,v_ids,p_session_key);
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
    when 'START_TOURNAMENT' then return public.start_tournament(p_room_id,p_session_key);
    when 'SIMULATE_TOURNAMENT' then return public.simulate_tournament(p_room_id,p_session_key);
    else raise exception using message='UNKNOWN_AUCTION_COMMAND';
  end case;
end;
$$;

revoke execute on function public.auto_set_batting_order(uuid,text) from public,anon,authenticated;
revoke execute on function public.post_auction_command(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.post_auction_command(uuid,text,text,jsonb) to service_role;
