from pathlib import Path
import json,sqlite3,time
manifest=json.loads(Path('build/conversation-scale-20261103-baseline/summary.json').read_text())
directory=Path(manifest['databases'][1])
connection=sqlite3.connect(f'file:{directory}/conversations.sqlite?mode=ro',uri=True)
base='SELECT m.sequence,m.created,m.body,c.id,c.name FROM conversation_search JOIN conversation_messages m ON m.id=conversation_search.id JOIN conversations c ON c.id=m.owner WHERE conversation_search MATCH ? AND m.owner=? ORDER BY bm25(conversation_search),m.sequence DESC LIMIT ?'
rowid=base.replace('m.id=conversation_search.id','m.sequence=conversation_search.rowid')
ranked='WITH matches AS MATERIALIZED (SELECT rowid,bm25(conversation_search) AS relevance FROM conversation_search WHERE conversation_search MATCH ? AND owner=? ORDER BY relevance,rowid DESC LIMIT ?) SELECT m.sequence,m.created,m.body,c.id,c.name FROM matches JOIN conversation_messages m ON m.sequence=matches.rowid JOIN conversations c ON c.id=m.owner ORDER BY matches.relevance,m.sequence DESC'
report={'sqlite_version':sqlite3.sqlite_version,'variants':[]}
reference=None
for name,query in [('uuid_join',base),('sequence_join',rowid),('rank_before_body',ranked)]:
 times=[]
 for term in ['project','résumé']:
  start=time.perf_counter(); rows=connection.execute(query,(term,'scale-pogo',20)).fetchall(); elapsed=time.perf_counter()-start
  ids=[r[0] for r in rows]
  if reference is None: reference=ids
  assert ids==reference, (name,term,ids,reference)
  times.append(dict(query=term,elapsed_seconds=elapsed,result_sequences=ids))
 item=dict(name=name,sql=query,plan=connection.execute('EXPLAIN QUERY PLAN '+query,('project','scale-pogo',20)).fetchall(),measurements=times)
 report['variants'].append(item)
 print(json.dumps(item),flush=True)
Path('build/conversation-scale-20261103-baseline/search-query-diagnostic.json').write_text(json.dumps(report,indent=2)+'\n')
