#!/usr/bin/env python3
"""Reproducibly build audited T20 stats from Cricsheet archives and registers."""
import csv, datetime as dt, json, os, re, shutil, tempfile, urllib.request, zipfile
from collections import Counter, defaultdict
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]; CACHE=ROOT/'.cache/cricsheet'; OUT=ROOT/'data/player-stats'
OUT.mkdir(parents=True,exist_ok=True)
SOURCES={
 'ipl':('Indian Premier League','ipl_json.zip','IPL'),
 't20':("Men's T20 Internationals",'t20s_male_json.zip','T20'),
 'sma':('Syed Mushtaq Ali Trophy','sma_json.zip','T20'),
 'bbl_male':('Big Bash League','bbl_male_json.zip','T20'),
 'psl':('Pakistan Super League','psl_json.zip','T20'),
 'cpl':('Caribbean Premier League','cpl_json.zip','T20'),
 'sat':('SA20','sat_json.zip','T20'),
 'ilt':('International League T20','ilt_json.zip','T20'),
 'mlc':('Major League Cricket','mlc_json.zip','T20'),
 'lpl':('Lanka Premier League','lpl_json.zip','T20'),
 'ntb':('T20 Blast','ntb_json.zip','T20'),
 'bpl_male':('Bangladesh Premier League','bpl_male_json.zip','T20'),
 'ctc_male':('CSA T20 Challenge','ctc_male_json.zip','T20'),
 'mct':('Major Clubs T20 Tournament','mct_json.zip','T20'),
 'ssm_male':('Super Smash','ssm_male_json.zip','T20'),
}

def download(url,dest):
 dest.parent.mkdir(parents=True,exist_ok=True)
 with tempfile.NamedTemporaryFile(dir=dest.parent,delete=False) as f: temp=Path(f.name)
 try:
  with urllib.request.urlopen(url,timeout=120) as src,temp.open('wb') as out: shutil.copyfileobj(src,out)
  temp.replace(dest)
 finally: temp.unlink(missing_ok=True)

def get_sources():
 CACHE.mkdir(parents=True,exist_ok=True); refresh=os.environ.get('STATS_REFRESH')=='1'
 for name in ('people.csv','names.csv'):
  dest=CACHE/name
  if refresh or not dest.exists(): download(f'https://cricsheet.org/register/{name}',dest)
 result={}
 for slug,(_,archive_name,_) in SOURCES.items():
  folder=CACHE/slug if slug in ('ipl','t20') else CACHE/'competitions'/slug
  archive=CACHE/'archives'/archive_name
  if refresh or not any(folder.glob('*.json')):
   if refresh or not archive.exists(): download(f'https://cricsheet.org/downloads/{archive_name}',archive)
   folder.mkdir(parents=True,exist_ok=True)
   with zipfile.ZipFile(archive) as z: z.extractall(folder)
  result[slug]=folder
 return result

def norm(s): return re.sub(r'[^a-z0-9]','',re.sub(r'\s+',' ',(s or '').lower()).encode('ascii','ignore').decode())
def tokens(s): return re.findall(r'[a-z]+',(s or '').lower())
def fresh(): return {'matches':set(),'batmatches':set(),'bowlmatches':set(),'innings':0,'runs':0,'balls':0,'fours':0,'sixes':0,'outs':0,'wickets':0,'conceded':0,'legalballs':0,'dots':0,'recent':[]}
def rate(n,d): return round(n*100/d,2) if d else None
def avg(n,d): return round(n/d,2) if d else None
def econ(n,d): return round(n*6/d,2) if d else None
def role(p):
 if p.get('wicketkeeper'): return 'WICKET-KEEPER'
 s=p.get('specialism','').upper()
 if 'ALL-ROUNDER' in s:return 'ALL-ROUNDER'
 if 'BOWL' in s:return 'BOWLER'
 return 'BATTER'

def parse(path,kind,stats,active,aliases,raw_names,failures):
 try:d=json.loads(path.read_text())
 except (OSError,json.JSONDecodeError): failures.append(str(path.relative_to(ROOT))); return None
 info=d.get('info',{})
 if info.get('gender')!='male' or info.get('match_type') not in ('T20','IT20'): return None
 date=(info.get('dates') or [None])[0]; mk=path.stem
 bat=defaultdict(lambda:[0,0,0,0,0]); bowl=defaultdict(lambda:[0,0,0,0])
 for inn in d.get('innings',[]):
  for over in inn.get('overs',[]):
   for ball in over.get('deliveries',[]):
    r=ball.get('runs',{}); ex=ball.get('extras',{}); br=int(r.get('batter',0)); total=int(r.get('total',0)); wide=int(ex.get('wides',0)); nb=int(ex.get('noballs',0))
    if ball.get('batter'):
     x=bat[ball['batter']]; x[0]+=br; x[1]+=not wide; x[2]+=br==4; x[3]+=br==6
    if ball.get('bowler'):
     x=bowl[ball['bowler']]; x[0]+=total-int(ex.get('byes',0))-int(ex.get('legbyes',0)); x[1]+=not(wide or nb); x[2]+=total==0
    for w in ball.get('wickets',[]):
     if w.get('player_out') in bat:bat[w['player_out']][4]+=1
     if ball.get('bowler') and w.get('kind') not in {'run out','retired hurt','retired out','obstructing the field'}:bowl[ball['bowler']][3] += 1
 registry=info.get('registry',{}).get('people',{})
 for name,ident in registry.items():
  aliases[norm(name)].add(ident); raw_names[name].add(ident)
  if name not in bat and name not in bowl: continue
  active.add(ident); s=stats[(ident,kind)]; s['matches'].add(mk)
  b=bat.get(name,[0,0,0,0,0]); q=bowl.get(name,[0,0,0,0])
  if name in bat:
   s['batmatches'].add(mk); s['innings']+=1; s['runs']+=b[0]; s['balls']+=b[1]; s['fours']+=b[2]; s['sixes']+=b[3]; s['outs']+=b[4]
  if name in bowl:
   s['bowlmatches'].add(mk); s['conceded']+=q[0]; s['legalballs']+=q[1]; s['dots']+=q[2]; s['wickets']+=q[3]
  s['recent'].append({'date':date,'runs':b[0],'balls':b[1],'wickets':q[3],'conceded':q[0],'legalballs':q[1]})
 return date

def resolve(name,aliases,raw,active):
 exact=aliases.get(norm(name),set()); ea=exact&active
 if len(ea)==1:return next(iter(ea)),'exact_active'
 if len(exact)==1:return next(iter(exact)),'exact'
 nt=tokens(name); candidates=set()
 for alias,ids in raw.items():
  at=tokens(alias)
  if at and nt and at[-1]==nt[-1] and (at[0]==nt[0] or at[0][:1]==nt[0][:1]): candidates.update(ids)
 active_candidates=candidates&active
 if len(active_candidates)==1:return next(iter(active_candidates)),'surname_initial_active'
 if len(candidates)==1:return next(iter(candidates)),'surname_initial'
 return None,'ambiguous' if exact or candidates else 'unresolved'

def recent_metric(items,player_role):
 if not items:return None
 vals=[]
 for x in items:
  measures=[]
  if x['balls']:
   measures.append(min(100,x['runs']*1.5+max(0,(rate(x['runs'],x['balls']) or 0)-100)*.15))
  if x['legalballs']:
   measures.append(min(100,x['wickets']*24+max(0,9-(econ(x['conceded'],x['legalballs']) or 9))*7))
  if player_role=='BOWLER': measures=[measures[-1]] if x['legalballs'] and measures else []
  elif player_role!='ALL-ROUNDER': measures=measures[:1]
  if measures: vals.append(sum(measures)/len(measures))
 if not vals:return None
 return round(sum(v*.88**i for i,v in enumerate(vals))/sum(.88**i for i in range(len(vals))),2)

def main():
 dirs=get_sources(); players=json.loads((ROOT/'data/ipl-2025-auction/game_players.json').read_text())
 db_ids_path=OUT/'player-database-ids.json'
 db_ids={x['source_record_key']:x['player_id'] for x in json.loads(db_ids_path.read_text())} if db_ids_path.exists() else {}
 aliases=defaultdict(set); raw=defaultdict(set)
 for f in ('people.csv','names.csv'):
  with (CACHE/f).open(newline='') as h:
   for r in csv.DictReader(h):aliases[norm(r['name'])].add(r['identifier']);raw[r['name']].add(r['identifier'])
 stats=defaultdict(fresh);active=set();failures=[];dates=[];match_counts={}
 for slug,folder in dirs.items():
  n=0
  for path in sorted(folder.glob('*.json')):
   date=parse(path,SOURCES[slug][2],stats,active,aliases,raw,failures)
   if date:dates.append(date);n+=1
  match_counts[slug]=n
 mapping=[]
 for p in players:
  ident,method=resolve(p['full_name'],aliases,raw,active)
  mapping.append({'source_record_key':p['source_record_key'],'full_name':p['full_name'],'cricsheet_id':ident,'method':method})
 used=set()
 for m in mapping:
  if m['cricsheet_id'] in used:m['cricsheet_id']=None;m['method']='duplicate_identity_rejected'
  elif m['cricsheet_id']:used.add(m['cricsheet_id'])
 asof=max(dates or [dt.date.today().isoformat()]); cutoff=(dt.date.fromisoformat(asof)-dt.timedelta(days=365)).isoformat(); updated=dt.datetime.now(dt.timezone.utc).isoformat()
 bykey={p['source_record_key']:p for p in players}; rows=[]; missing=[]
 source_names=[x[0] for x in SOURCES.values()]
 for m in mapping:
  p=bykey[m['source_record_key']]; ident=m['cricsheet_id']; ip=stats.get((ident,'IPL'),fresh()) if ident else fresh(); t=stats.get((ident,'T20'),fresh()) if ident else fresh()
  im=len(ip['matches']); tm=len(t['matches']); cov='IPL' if im else 'T20' if tm else 'NO_VERIFIED_DATA'; valid=cov!='NO_VERIFIED_DATA'; r=role(p)
  recent=sorted([x for x in ip['recent']+t['recent'] if x['date'] and x['date']>=cutoff and (x['legalballs']>0 if r=='BOWLER' else (x['balls']>0 or x['legalballs']>0) if r=='ALL-ROUNDER' else x['balls']>0)],key=lambda x:x['date'],reverse=True)[:15]
  performance=ip if im else t
  row={'source_record_key':m['source_record_key'],'full_name':p['full_name'],'cricsheet_player_id':ident,'coverage_level':cov,
   'mapping_method':m['method'],'stats_source':("Cricsheet IPL and men's T20 JSON: "+', '.join(source_names)) if valid else None,
   'stats_as_of':asof if valid else None,'stats_updated_at':updated if valid else None,
   'ipl_matches':im or None,'ipl_innings':ip['innings'] or None,'ipl_runs':ip['runs'] or None,'ipl_batting_average':avg(ip['runs'],ip['outs']),
   'ipl_strike_rate':rate(ip['runs'],ip['balls']),'ipl_wickets':ip['wickets'] or None,'ipl_bowling_average':avg(ip['conceded'],ip['wickets']),
   'ipl_economy':econ(ip['conceded'],ip['legalballs']),'ipl_bowling_strike_rate':round(ip['legalballs']/ip['wickets'],2) if ip['wickets'] else None,
   't20_matches':tm or None,'t20_runs':t['runs'] or None,'t20_wickets':t['wickets'] or None,
   't20_strike_rate':rate(t['runs'],t['balls']),'t20_economy':econ(t['conceded'],t['legalballs']),
   'recent_form_matches':len(recent) or None,'recent_form_from':min((x['date'] for x in recent),default=None),
   'recent_form_as_of':max((x['date'] for x in recent),default=None),'recent_form_score':recent_metric(recent,r)}
  row['batting_score']=round(min(100,max(0,35+(rate(performance['runs'],performance['balls']) or 0)*.30+(avg(performance['runs'],performance['outs']) or 0)*.35)),2) if valid and performance['runs'] else None
  row['bowling_score']=round(min(100,max(0,110-(econ(performance['conceded'],performance['legalballs']) or 12)*8+min(30,performance['wickets']*.4))),2) if valid and performance['legalballs'] else None
  rows.append(row)
  if not valid:
   method=m['method']
   if method=='unresolved':reason='NO_IDENTITY_MATCH'; detail='No Cricsheet identity can be mapped from the supplied name and aliases.'
   elif method=='ambiguous':reason='NAME_ALIAS_MISSING';detail='Multiple Cricsheet identities match; automatic fuzzy matching was rejected as ambiguous.'
   elif method=='duplicate_identity_rejected':reason='OTHER';detail='The mapped identity was already assigned to another auction row and was rejected to prevent duplicate player identity.'
   elif ident:reason='NO_MATCHES_IN_DOWNLOADED_DATA';detail='Identity is known, but no batting or bowling appearance is present in the downloaded male T20 data.'
   else:reason='NO_IDENTITY_MATCH';detail='No safe unique identity match was found.'
   missing.append({'player_id':db_ids.get(m['source_record_key']),'source_record_key':m['source_record_key'],'full_name':p['full_name'],'country':p['country'],'public_role':r,'cricsheet_mapping_status':'MAPPED' if ident else 'UNMAPPED','cricsheet_player_id':ident,'mapping_method':method,'missing_reason':reason,'reason_detail':detail})
 cov=Counter(x['coverage_level'] for x in rows)
 report={'generated_at':updated,'stats_as_of':asof,'recent_window_start':cutoff,'auction_players':len(players),'mapped':sum(bool(x['cricsheet_id']) for x in mapping),'unresolved':sum(x['method']=='unresolved' for x in mapping),'ambiguous':sum(x['method']=='ambiguous' for x in mapping),'coverage':{x:cov[x] for x in ('IPL','T20','NO_VERIFIED_DATA')},'verified_profiles':cov['IPL']+cov['T20'],'missing_profiles':cov['NO_VERIFIED_DATA'],'missing_reason_breakdown':dict(sorted(Counter(x['missing_reason'] for x in missing).items())),'source_match_counts':match_counts,'sources':source_names,'parse_failures':failures,'source':'Cricsheet JSON and people/names registers'}
 for filename,data in [('player-map.json',mapping),('player-stats.json',rows),('missing-profiles.json',missing),('validation-report.json',report)]:
  (OUT/filename).write_text(json.dumps(data,indent=2)+'\n')
 print(json.dumps({k:report[k] for k in ('stats_as_of','auction_players','mapped','unresolved','ambiguous','coverage','missing_reason_breakdown','source_match_counts')},indent=2))

if __name__=='__main__':main()
