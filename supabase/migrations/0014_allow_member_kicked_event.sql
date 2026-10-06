-- Allow the host moderation event emitted by kick_room_member.
alter table auction_events drop constraint if exists auction_events_event_type_check;
alter table auction_events add constraint auction_events_event_type_check check (event_type = any (array[
  'AUCTION_STARTED','BID','SOLD','UNSOLD','AUCTION_PAUSED','AUCTION_RESUMED',
  'SET_COMPLETED','AUCTION_ENDED','MEMBER_JOINED','MEMBER_RECONNECTED','MEMBER_KICKED'
]));
