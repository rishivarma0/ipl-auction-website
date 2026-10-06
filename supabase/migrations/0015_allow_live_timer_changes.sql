-- Allow the host to change the bid timer from Settings during a live auction.
-- The new value is used for the next bid/reset; the current countdown remains authoritative.
create or replace function public.set_auction_timer(p_room_id uuid, p_timer_seconds integer, p_session_key text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_member uuid; v_room rooms;
begin
  v_member := public.assert_room_session(p_room_id, p_session_key);
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then raise exception using message = 'ROOM_NOT_FOUND'; end if;
  if v_room.host_member_id <> v_member then raise exception using message = 'NOT_HOST'; end if;
  if v_room.status not in ('WAITING', 'RUNNING', 'PAUSED') then raise exception using message = 'TIMER_CHANGE_LOCKED'; end if;
  if p_timer_seconds not in (5, 8, 10, 15, 20, 25) then raise exception using message = 'INVALID_AUCTION_TIMER'; end if;
  update rooms set auction_timer_seconds = p_timer_seconds where id = p_room_id;
  return jsonb_build_object('ok', true, 'timer_seconds', p_timer_seconds);
end;
$$;

revoke all on function public.set_auction_timer(uuid, integer, text) from public;
grant execute on function public.set_auction_timer(uuid, integer, text) to anon, authenticated;
