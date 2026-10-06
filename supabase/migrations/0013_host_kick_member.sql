-- Host-only lobby moderation. Kicking is intentionally limited to WAITING so
-- auction ownership, bids, and squads cannot be mutated mid-auction.

create or replace function public.kick_room_member(p_room_id uuid, p_target_member_id uuid, p_session_key text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_host uuid;
  v_room rooms;
  v_target room_members;
begin
  v_host := public.assert_room_session(p_room_id, p_session_key);
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then raise exception using message = 'ROOM_NOT_FOUND'; end if;
  if v_room.host_member_id <> v_host then raise exception using message = 'NOT_HOST'; end if;
  if v_room.status <> 'WAITING' then raise exception using message = 'KICK_LOCKED'; end if;
  select * into v_target from room_members where id = p_target_member_id and room_id = p_room_id and status <> 'LEFT' for update;
  if v_target.id is null then raise exception using message = 'MEMBER_NOT_FOUND'; end if;
  if v_target.id = v_room.host_member_id then raise exception using message = 'CANNOT_KICK_HOST'; end if;

  delete from squads where room_id = p_room_id and member_id = v_target.id;
  update room_members
    set status = 'LEFT', franchise_id = null, last_seen_at = now()
    where id = v_target.id;
  insert into auction_events(room_id, event_type, payload)
    values (p_room_id, 'MEMBER_KICKED', jsonb_build_object('display_name', v_target.display_name));
  return jsonb_build_object('ok', true, 'member_id', v_target.id);
end;
$$;

revoke all on function public.kick_room_member(uuid, uuid, text) from public;
grant execute on function public.kick_room_member(uuid, uuid, text) to anon, authenticated;
