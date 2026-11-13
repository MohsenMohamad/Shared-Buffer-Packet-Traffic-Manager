from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import json
import re
import subprocess

root=Path.cwd(); directory=root/'work/final-campaign';directory.mkdir(parents=True,exist_ok=True)

def campaign(profile):
    records=[]
    for index,seed in enumerate([17,31,53,17]):
        modes=['memory-tx-oracle','memory-tx-bench'] if index==0 else ['memory-tx-oracle']
        command=['python3','tools/run.py','regression','--profile',profile,'--seed',str(seed),'--timeout','120','--build-timeout','600']
        for mode in modes:command+=['--test',mode]
        log=directory/(profile+'-'+str(index)+'.log')
        print('START '+profile+' '+str(index)+' '+str(seed),flush=True)
        with log.open('w') as output:
            result=subprocess.run(command,stdout=output,stderr=output)
        text=log.read_text();summary=re.findall(r'^(?:PASS|FAIL|TOOL_ERROR|TIMEOUT|NOT_IMPLEMENTED): (.+/summary.json)$',text,re.M)
        record=dict(profile=profile,seed=seed,modes=modes,command=command,returncode=result.returncode,
                    log=str(log),summary=summary[-1] if summary else None)
        records.append(record)
        (directory/(profile+'.json')).write_text(json.dumps(records,indent=2)+'\n')
        print(('PASS ' if result.returncode==0 else 'FAIL ')+profile+' '+str(index),flush=True)
        if result.returncode:return records
    return records

all_records=[]
with ThreadPoolExecutor(max_workers=2) as executor:
    pending={executor.submit(campaign,profile):profile for profile in ['E0','I1','I0','E1','F0','F1']}
    for future in as_completed(pending):all_records+=future.result()
(directory/'campaign.json').write_text(json.dumps(all_records,indent=2)+'\n')
ok=len(all_records)==24 and all(row['returncode']==0 for row in all_records)
print('FINAL_PREPARATION_CAMPAIGN_'+('PASS' if ok else 'FAIL'),flush=True)
raise SystemExit(0 if ok else 1)
