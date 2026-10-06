-- Phase 2: official auction metadata refinements. No room queue is generated here.
alter table auction_sets rename column set_no to official_set_no;
alter table auction_sets rename column set_name to display_name;
alter table auction_sets rename column display_order to set_order;
alter table auction_sets add column if not exists player_count integer not null default 0 check (player_count >= 0);
alter table auction_sets add constraint auction_sets_official_no_code_unique unique (official_set_no, official_set_code);

alter table players add column if not exists first_name text;
alter table players add column if not exists surname text;
alter table players add column if not exists normalized_search_name text;
update players set first_name = split_part(full_name, ' ', 1), surname = nullif(substr(full_name, length(split_part(full_name, ' ', 1)) + 2), '') where first_name is null;
alter table players add constraint players_official_identity_unique unique (official_list_sr_no, full_name);
alter table players add constraint players_base_price_allowed check (base_price_lakh in (30,40,50,75,100,125,150,200));
alter table players add constraint players_country_overseas_consistency check ((country = 'India' and overseas = false) or (country <> 'India' and overseas = true));
create index if not exists players_set_code_name_idx on players(official_set_code, full_name);
create index if not exists players_overseas_idx on players(overseas);
create index if not exists squad_players_squad_overseas_idx on squad_players(squad_id, player_id);
