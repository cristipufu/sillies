import json
import subprocess
from pathlib import Path

root=Path('build/vault-ranking-2026-11-08')
binaries={
 'baseline':Path('build/vault-search-refinement-2026-11-08/VaultScaleBenchmark-baseline').resolve(),
 'boundary':(root/'VaultScaleBenchmark-boundary').resolve()
}
fixtures=[('100k',Path('build/vault-search-refinement-2026-11-08/scale-random').resolve(),100000),
          ('1m',Path('build/vault-qualification-2026-11-07/scale-production').resolve(),1000000)]
for scale,directory,count in fixtures:
 for iteration,variant in enumerate(['baseline','boundary','boundary','baseline']):
  label=f'{scale}-{iteration}-{variant}'
  with (root/f'{label}.jsonl').open('w') as out,(root/f'{label}-stderr.log').open('w') as err:
   subprocess.run([str(binaries[variant]),'query',str(directory),str(count),'20'],stdout=out,stderr=err,timeout=180,check=True)
  values=[json.loads(line) for line in (root/f'{label}.jsonl').read_text().splitlines()]
  expected={'recent','broad_newest','recently_edited','broad_relevance','rare'}
  assert {value['name'] for value in values}==expected
  assert all(value['records']==count and len(value['samplesMilliseconds'])==15 and value['loadedBodies']==0 for value in values)
  print(json.dumps({'run':label,'complete':True,'medians':{value['name']:value['medianMilliseconds'] for value in values}}),flush=True)
