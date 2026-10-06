import json,sys
a=json.load(open('data/player-stats/player-stats.json'))
cols=['source_record_key','cricsheet_player_id','coverage_level','mapping_method','stats_source','stats_as_of','ipl_matches','ipl_innings','ipl_runs','ipl_batting_average','ipl_strike_rate','ipl_wickets','ipl_bowling_average','ipl_economy','ipl_bowling_strike_rate','t20_matches','t20_runs','t20_wickets','t20_strike_rate','t20_economy','recent_form_matches','recent_form_as_of','recent_form_score','batting_score','bowling_score','stats_updated_at']
ints={'ipl_matches','ipl_innings','ipl_runs','ipl_wickets','t20_matches','t20_runs','t20_wickets','recent_form_matches'}; dates={'stats_as_of','recent_form_as_of'}; nums={'ipl_batting_average','ipl_strike_rate','ipl_bowling_average','ipl_economy','ipl_bowling_strike_rate','t20_strike_rate','t20_economy','recent_form_score','batting_score','bowling_score'}
def esc(v): return 'NULL' if v is None else "'"+str(v).replace("'","''")+"'"
def cast(c): return '::date' if c in dates else '::integer' if c in ints else '::numeric' if c in nums else '::timestamptz' if c=='stats_updated_at' else ''
lo=int(sys.argv[1]); hi=int(sys.argv[2]); select=','.join('v.'+c+cast(c) for c in cols[1:]); values=','.join('('+','.join(esc(x.get(c)) for c in cols)+')' for x in a[lo:hi])
print('insert into player_stats(player_id,'+','.join(cols[1:])+') select p.id,'+select+' from (values '+values+') as v('+','.join(cols)+') join players p on p.source_record_key=v.source_record_key on conflict(player_id) do update set '+','.join(c+'=excluded.'+c for c in cols[1:])+';')
