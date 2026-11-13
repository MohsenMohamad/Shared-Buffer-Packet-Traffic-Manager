import json
from pathlib import Path
records=json.loads(Path('work/final-campaign-fixed/campaign.json').read_text())
row=next(r for r in records if r['profile']=='F0' and 'memory-tx-bench' in r['modes'])
summary=json.loads(Path(row['summary']).read_text())
case=next(c for c in summary['cases'] if c['test']=='memory-tx-bench-legal')
manifest=json.loads(Path(case['manifest']).read_text())
qids=set();sources=set()
for line in Path(manifest['artifacts']['observed']).read_text().splitlines():
 sample=json.loads(line)
 if sample['valid'] and sample['ready']:
  user=int(sample['user'],16);qids.add(user&255);sources.add((user>>40)&255)
print('observed queues',sorted(qids),'sources',sorted(sources))
assert qids==set(range(manifest['parameters']['queues'])),'METADATA_COVERAGE_MISSING_QUEUE'
assert sources==set(range(manifest['parameters']['sources'])),'METADATA_COVERAGE_MISSING_SOURCE'
print('METADATA_COVERAGE_PROBE_PASS')
