from pathlib import Path
import json, subprocess, time
run=Path('build/conversation-scale-20261103-validated')
directory=Path(json.loads((run/'summary.json').read_text())['databases'][1])
base="SELECT m.sequence,m.created,m.body,c.id,c.name FROM conversation_search JOIN conversation_messages m ON m.sequence=conversation_search.rowid JOIN conversations c ON c.id=m.owner WHERE conversation_search MATCH 'project' AND m.owner='scale-pogo' ORDER BY bm25(conversation_search),m.sequence DESC LIMIT 20"
ranked="WITH matches AS MATERIALIZED (SELECT rowid,bm25(conversation_search) AS relevance FROM conversation_search WHERE conversation_search MATCH 'project' AND owner='scale-pogo' ORDER BY relevance,rowid DESC LIMIT 20) SELECT m.sequence,m.created,m.body,c.id,c.name FROM matches JOIN conversation_messages m ON m.sequence=matches.rowid JOIN conversations c ON c.id=m.owner ORDER BY matches.relevance,m.sequence DESC"
metadata="WITH matches AS MATERIALIZED (SELECT m.sequence,bm25(conversation_search) AS relevance FROM conversation_search JOIN conversation_messages m ON m.sequence=conversation_search.rowid WHERE conversation_search MATCH 'project' AND m.owner='scale-pogo' ORDER BY relevance,m.sequence DESC LIMIT 20) SELECT m.sequence,m.created,m.body,c.id,c.name FROM matches JOIN conversation_messages m ON m.sequence=matches.sequence JOIN conversations c ON c.id=m.owner ORDER BY matches.relevance,m.sequence DESC"
report={'sqlite_version':subprocess.check_output(['/usr/bin/sqlite3','--version'],text=True).strip(),'variants':[]}
reference=None
for name,query in [('sequence_join',base),('fts_filter_then_bodies',ranked),('metadata_filter_then_bodies',metadata)]:
 start=time.perf_counter()
 result=subprocess.run(['/usr/bin/sqlite3','-readonly','-json',str(directory/'conversations.sqlite'),query],capture_output=True,text=True,check=True,timeout=20)
 elapsed=time.perf_counter()-start
 rows=json.loads(result.stdout)
 if reference is None: reference=rows
 assert rows==reference, name
 plan=subprocess.check_output(['/usr/bin/sqlite3','-readonly',str(directory/'conversations.sqlite'),'EXPLAIN QUERY PLAN '+query],text=True,timeout=5)
 item=dict(name=name,sql=query,elapsed_seconds=elapsed,sequences=[r['sequence'] for r in rows],plan=plan)
 report['variants'].append(item);print(json.dumps(item),flush=True)
(run/'native-sql-query-diagnostic.json').write_text(json.dumps(report,indent=2)+'\n')
