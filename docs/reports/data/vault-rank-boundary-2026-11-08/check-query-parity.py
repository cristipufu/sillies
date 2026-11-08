import json
import sqlite3
import time
from pathlib import Path

root = Path('build/vault-ranking-2026-11-08')
baseline = Path('build/app-acceptance-2026-11-08/baseline.sql').read_text()
bounded = (root / 'bound.sql').read_text()
database = sqlite3.connect('file:build/app-acceptance-2026-11-08/adaptive-e5/vault.sqlite?mode=ro', uri=True)
cases = []
for text in ['study', 'clinical', 'cells', 'human', 'meeting', 'code', 'randomized trial', 'nonexistentquasar']:
    for table, expression in [('content_search', ' OR '.join('"'+word+'"*' for word in text.split())),
                              ('content_search', '"'+text+'"'),
                              ('content_substrings', '"'+text+'"')]:
        deadline = time.monotonic() + 15
        database.set_progress_handler(lambda: int(time.monotonic() > deadline), 10000)
        original = database.execute(baseline.replace('content_search', table), [expression]).fetchall()
        candidate = database.execute(bounded.replace('content_search', table), [expression]).fetchall()
        if candidate != original:
            raise RuntimeError(f'Ranking mismatch: {table}, {expression}')
        cases.append({'table': table, 'expression': expression, 'returned': len(original), 'exactRowsAndScores': True})
(root / 'public-corpus-query-parity.json').write_text(json.dumps({'sqlite':sqlite3.sqlite_version,'cases':cases}, indent=2)+'\n')
print(f'Exact record, score and block parity: {len(cases)} public-corpus queries')
