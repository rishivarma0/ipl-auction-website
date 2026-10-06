-- Some official auction set numbers contain multiple set codes (for example 72 / AL10 and 72 / FA10).
-- Set code is therefore part of the immutable set identity.
alter table room_auction_queue drop constraint if exists room_auction_queue_set_no_fkey;
alter table auction_state drop constraint if exists auction_state_current_set_no_fkey;
alter table auction_sets drop constraint if exists auction_sets_pkey;
alter table auction_sets add column if not exists id uuid default gen_random_uuid();
update auction_sets set id = gen_random_uuid() where id is null;
alter table auction_sets alter column id set not null;
alter table auction_sets add constraint auction_sets_pkey primary key (id);
alter table room_auction_queue add column if not exists official_set_code text;
update room_auction_queue q set official_set_code = s.official_set_code from auction_sets s where s.official_set_no = q.set_no and q.official_set_code is null;
alter table room_auction_queue add constraint room_queue_official_set_fk foreign key (set_no, official_set_code) references auction_sets(official_set_no, official_set_code);
alter table auction_state add constraint auction_state_official_set_fk foreign key (current_set_no, current_set_code) references auction_sets(official_set_no, official_set_code);
