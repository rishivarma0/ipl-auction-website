-- The Edge Function gateway uses the authoritative session assertion before
-- reading room membership. Keep it unavailable to browser roles.
grant execute on function public.assert_room_session(uuid, text) to service_role;
revoke execute on function public.assert_room_session(uuid, text) from anon, authenticated, public;
