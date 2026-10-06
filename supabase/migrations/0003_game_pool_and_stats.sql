-- Phase 2: 46 additional normal auction players in the M0 marquee set.
alter table players alter column official_list_sr_no drop not null;
alter table players alter column capped_status drop not null;
alter table players add column if not exists source_type text not null default 'OFFICIAL_AUCTION' check (source_type in ('OFFICIAL_AUCTION','ADDITIONAL_MARQUEE'));
alter table players add column if not exists source_record_key text;
update players set source_record_key = 'OFFICIAL-' || official_list_sr_no where source_record_key is null;
alter table players alter column source_record_key set not null;
alter table players add constraint players_source_record_key_unique unique (source_record_key);
alter table players add constraint players_official_serial_required_for_official check (source_type <> 'OFFICIAL_AUCTION' or official_list_sr_no is not null);
alter table auction_sets drop constraint if exists auction_sets_official_no_code_unique;
alter table auction_sets add constraint auction_sets_official_no_code_unique unique (official_set_no, official_set_code);

alter table player_stats add column if not exists ipl_matches integer;
alter table player_stats add column if not exists ipl_innings integer;
alter table player_stats add column if not exists ipl_runs integer;
alter table player_stats add column if not exists ipl_batting_average numeric;
alter table player_stats add column if not exists ipl_strike_rate numeric;
alter table player_stats add column if not exists ipl_wickets integer;
alter table player_stats add column if not exists ipl_bowling_average numeric;
alter table player_stats add column if not exists ipl_economy numeric;
alter table player_stats add column if not exists ipl_bowling_strike_rate numeric;
alter table player_stats add column if not exists recent_ipl_score numeric;
alter table player_stats add column if not exists overall_ipl_score numeric;
alter table player_stats add column if not exists overall_t20_score numeric;
alter table player_stats add column if not exists hidden_overall_score numeric;
