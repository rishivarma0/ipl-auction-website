#!/usr/bin/env python3
"""Build provenance-carrying statistics from cached Cricsheet JSON."""
import csv,datetime as dt,glob,json,re,unicodedata
from collections import defaultdict
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; CACHE=ROOT/'.cache/cricsheet'; OUT=ROOT/'data/player-stats'; OUT.mkdir(parents=True,exist_ok=True)
def norm(s): return re.sub(r'[^a-z0-9]','',unicodedata.normalize('NFKD',s or '').encode('ascii','ignore').decode().lower())
def toks(s): return re.findall(r'[a-z]+',unicodedata.normalize('NFKD',s or '').encode('ascii','ignore').decode().lower())
def empty(): return {'matches':set(),'bat_matches':set(),'bowl_matches':set(),'innings':0,'runs':0,'balls':0,'fours':0,'sixes':0,'outs':0,'wickets':0,'rc':0,'bb':0,'dots':0,'recent':[]}
def rate(n,d): return round(n*100/d,2) if d else None
def avg(n,d): return round(n/d,2) if d else None
def econ(n,d): return round(n*6/d,2) if d else None
players=json.load(open(ROOT/'data/ipl-2025-auction/game_players.json'))
alias=defaultdict(set)
raw_names=defaultdict(set)
for fn in ['people.csv','names.csv']:
    for r in csv.DictReader(open(CACHE/fn,newline='')):
        alias[norm(r['name'])].add(r['identifier']); raw_names[r['name']].add(r['identifier'])
for path in glob.glob(str(CACHE/'ipl/*.json'))+glob.glob(str(CACHE/'t20/*.json')):
    try: d=json.load(open(path))
    except Exception: continue
    for n,i in d.get('info',{}).get('registry',{}).get('people',{}).items(): alias[norm(n)].add(i); raw_names[n].add(i)
def resolve(name):
    c=alias.get(norm(name),set())
    if len(c)==1:return next(iter(c)),'exact'
    nt=toks(name); c=set()
    for key,ids in raw_names.items():
        kt=toks(key)
        if kt and nt and kt[-1]==nt[-1] and (kt[0]==nt[0] or kt[0][:1]==nt[0][:1]): c.update(ids)
    return (next(iter(c)),'surname_initial') if len(c)==1 else (None,'ambiguous' if c else 'unresolved')
mapping=[]
for p in players:
    i,m=resolve(p['full_name']); mapping.append({'source_record_key':p['source_record_key'],'full_name':p['full_name'],'cricsheet_id':i,'method':m})
# One Cricsheet identity must never be assigned to two auction rows. Keep the
# first deterministic assignment and mark later collisions unresolved.
seen={}
for row in mapping:
    ident=row['cricsheet_id']
    if not ident: continue
    if ident in seen:
        row['cricsheet_id']=None; row['method']='duplicate_identity_rejected'
    else: seen[ident]=row['source_record_key']
stats=defaultdict(empty)
def parse(path, source):
    try:d=json.load(open(path))
    except Exception:return None
    info=d.get('info',{})
    if info.get('gender')!='male' or info.get('match_type') not in ('T20','IT20'):return None
    date=(info.get('dates') or [None])[0]; key=Path(path).stem
    bat=defaultdict(lambda:[0,0,0,0,0]); bowl=defaultdict(lambda:[0,0,0,0,0])
    for inn in d.get('innings',[]):
        for over in inn.get('overs',[]):
            for b in over.get('deliveries',[]):
                r=b.get('runs',{}); ex=b.get('extras',{}); br=int(r.get('batter',0)); total=int(r.get('total',0)); wide=int(ex.get('wides',0)); nb=int(ex.get('noballs',0)); by=int(ex.get('byes',0)); lb=int(ex.get('legbyes',0))
                if b.get('batter'):
                    x=bat[b['batter']]; x[0]+=br; x[1]+=0 if wide else 1; x[2]+=br==4; x[3]+=br==6
                if b.get('bowler'):
                    x=bowl[b['bowler']]; x[0]+=total-by-lb; x[1]+=0 if wide or nb else 1; x[4]+=total==0
                for w in b.get('wickets',[]):
                    if w.get('player_out') in bat: bat[w['player_out']][4]+=1
                    if b.get('bowler') and w.get('kind') not in {'run out','retired hurt','retired out','obstructing the field'}: bowl[b['bowler']][2]+=1
    reg=info.get('registry',{}).get('people',{})
    for n,i in reg.items():
        if n in bat:
            x=bat[n]; s=stats[(i,source)]; s['matches'].add(key); s['bat_matches'].add(key); s['innings']+=1; s['runs']+=x[0]; s['balls']+=x[1]; s['fours']+=x[2]; s['sixes']+=x[3]; s['outs']+=x[4]; s['recent'].append({'date':date,'runs':x[0],'balls':x[1],'wickets':0,'rc':0,'bb':0})
        if n in bowl:
            x=bowl[n]; s=stats[(i,source)]; s['matches'].add(key); s['bowl_matches'].add(key); s['wickets']+=x[2]; s['rc']+=x[0]; s['bb']+=x[1]; s['dots']+=x[4]; s['recent'].append({'date':date,'runs':0,'balls':0,'wickets':x[2],'rc':x[0],'bb':x[1]})
    return date
ipl=[parse(p,'IPL') for p in glob.glob(str(CACHE/'ipl/*.json'))]; t20=[parse(p,'T20') for p in glob.glob(str(CACHE/'t20/*.json'))]
asof=max([x for x in ipl+t20 if x] or [dt.date.today().isoformat()]); cutoff=(dt.date.fromisoformat(asof)-dt.timedelta(days=365)).isoformat()
rows=[]
for m in mapping:
    ip=stats.get((m['cricsheet_id'],'IPL'),empty()) if m['cricsheet_id'] else empty(); t2=stats.get((m['cricsheet_id'],'T20'),empty()) if m['cricsheet_id'] else empty(); s=ip
    rec=sorted([x for x in ip['recent']+t2['recent'] if x['date'] and x['date']>=cutoff],key=lambda x:x['date'],reverse=True)[:15]
    wsum=rs=0
    for j,x in enumerate(rec): w=.88**j; wsum+=w; rs+=w*x['runs']
    recent=round(rs/wsum,2) if wsum else None; iplm=len(ip['bat_matches']|ip['bowl_matches']); t20m=len(t2['matches'])
    row={'source_record_key':m['source_record_key'],'full_name':m['full_name'],'cricsheet_player_id':m['cricsheet_id'],'stats_source':'Cricsheet IPL + men’s T20 JSON','stats_as_of':asof,'coverage_level':'IPL' if iplm else 'T20' if t20m else 'NO_VERIFIED_DATA','ipl_matches':iplm or None,'ipl_innings':len(ip['bat_matches']) or None,'ipl_runs':ip['runs'] or None,'ipl_batting_average':avg(ip['runs'],ip['outs']),'ipl_strike_rate':rate(ip['runs'],ip['balls']),'ipl_wickets':ip['wickets'] or None,'ipl_bowling_average':avg(ip['rc'],ip['wickets']),'ipl_economy':econ(ip['rc'],ip['bb']),'ipl_bowling_strike_rate':round(ip['bb']/ip['wickets'],2) if ip['wickets'] else None,'t20_matches':t20m or None,'t20_runs':t2['runs'] or None,'t20_wickets':t2['wickets'] or None,'t20_strike_rate':rate(t2['runs'],t2['balls']),'t20_economy':econ(t2['rc'],t2['bb']),'recent_form_score':recent,'recent_form_matches':len(rec),'recent_form_as_of':asof if rec else None,'stats_updated_at':dt.datetime.now(dt.timezone.utc).isoformat(),'mapping_method':m['method'],'batting_score':round(min(100,max(0,45+(rate(ip['runs'],ip['balls']) or rate(t2['runs'],t2['balls']) or 0)*.22+(avg(ip['runs'],ip['outs']) or 0)*.25)),2) if ip['runs'] or t2['runs'] else None,'bowling_score':round(min(100,max(0,100-(econ(ip['rc'],ip['bb']) or econ(t2['rc'],t2['bb']) or 0)*8+(ip['wickets'] or t2['wickets'])*1.6)),2) if ip['wickets'] or t2['wickets'] else None}
    rows.append(row)
json.dump(mapping,open(OUT/'player-map.json','w'),indent=2); json.dump(rows,open(OUT/'player-stats.json','w'),indent=2)
report={'generated_at':dt.datetime.now(dt.timezone.utc).isoformat(),'stats_as_of':asof,'cutoff':cutoff,'auction_players':len(players),'mapped':sum(bool(x['cricsheet_id']) for x in mapping),'unresolved':sum(x['method']=='unresolved' for x in mapping),'ambiguous':sum(x['method']=='ambiguous' for x in mapping),'coverage':{k:sum(x['coverage_level']==k for x in rows) for k in ['IPL','T20','NO_VERIFIED_DATA']},'unresolved_players':[x for x in mapping if x['method']=='unresolved'],'ambiguous_players':[x for x in mapping if x['method']=='ambiguous'],'source':'Cricsheet JSON/register data'}
json.dump(report,open(OUT/'validation-report.json','w'),indent=2); print(json.dumps({k:report[k] for k in ['stats_as_of','auction_players','mapped','unresolved','ambiguous','coverage']},indent=2))
