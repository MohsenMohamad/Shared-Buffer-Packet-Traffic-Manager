"""Public-action wire encoding for sealed monitor replay; no expected behavior."""
from pathlib import Path
import json

FIELDS=[('reserve_v',32),('desc',32),('length',32),('qid',32),('tag',32),('source',32),
        ('alloc_v',32),('alloc_cell',32),('alloc_desc',32),
        ('write_v',32),('write_addr',32),('write_data',64),
        ('info_v',32),('info_desc',32),('info_length',32),('info_qid',32),('info_tag',32),('info_source',32),('info_head',32),('info_ncell',32),
        ('link_v',32),('link_cell',32),('link_next',32),('commit_v',32),('commit_desc',32),
        ('dispatch_v',32),('dispatch_desc',32),('read_v',32),('read_addr',32),
        ('response_v',32),('response_data',64),('query_v',32),('query_cell',32),('query_next',32),
        ('free_v',32),('free_cell',32),('done_v',32),('done_desc',32)]+[(event+'_'+key,32) for event in ('commit_info','dispatch_info') for key in ('v','desc','length','qid','tag','source','head','ncell')]


def encode_actions(actions):
    values={name:0 for name,_ in FIELDS}
    mapping={'reserve':{'desc':'desc','length':'length','qid':'qid','tag':'tag','source':'source'},
             'allocate':{'cell':'alloc_cell','desc':'alloc_desc'},'write':{'addr':'write_addr','data':'write_data'},
             'info':{key:'info_'+key for key in ('desc','length','qid','tag','source','head','ncell')},
             'link':{'cell':'link_cell','next':'link_next'},'response':{'data':'response_data'},
             'query':{'cell':'query_cell','next':'query_next'}}
    for event in ('commit_info','dispatch_info'):
        mapping[event]={key:event+'_'+key for key in ('desc','length','qid','tag','source','head','ncell')}
    for action,fields in mapping.items():
        if action not in actions:continue
        values[{'allocate':'alloc'}.get(action,action)+'_v']=1
        for key,target in fields.items():values[target]=actions[action][key]
    for action,key in [('commit','desc'),('dispatch','desc'),('read','addr'),('free','cell'),('done','desc')]:
        if action in actions:values[action+'_v']=1;values[action+'_'+key]=actions[action]
    word=0
    for name,width in FIELDS:word=(word<<width)|values[name]
    return word


def decode_actions(word):
    values={}
    for name,width in reversed(FIELDS):values[name]=word&((1<<width)-1);word>>=width
    actions={}
    for action,prefix,keys in [('reserve','',('desc','length','qid','tag','source')),('allocate','alloc_',('cell','desc')),
                               ('write','write_',('addr','data')),('info','info_',('desc','length','qid','tag','source','head','ncell')),
                               ('link','link_',('cell','next')),('response','response_',('data',)),('query','query_',('cell','next'))]:
        if values[{'allocate':'alloc'}.get(action,action)+'_v']:
            actions[action]={key:values[prefix+key] for key in keys}
    for event in ('commit_info','dispatch_info'):
        if values[event+'_v']:
            actions[event]={key:values[event+'_'+key] for key in ('desc','length','qid','tag','source','head','ncell')}
    for action,key in [('commit','desc'),('dispatch','desc'),('read','addr'),('free','cell'),('done','desc')]:
        if values[action+'_v']:actions[action]=values[action+'_'+key]
    return actions


def write_replay(path,samples):
    lines=[]
    for s in samples:
        o=s['out']
        lines.append(f"{int(s['reset'])} {encode_actions(s['actions']):x} {int(o['valid'])} {int(o['ready'])} {o['data']:x} {o['keep']:x} {int(o['last'])} {o['user']:x}\n")
    Path(path).write_text(''.join(lines))


def read_observed(path):
    result=[]
    for line in Path(path).read_text().splitlines():
        raw=json.loads(line)
        result.append(dict(epoch=raw['epoch'],cycle=raw['cycle'],reset=bool(raw['reset']),
                           actions=decode_actions(int(raw['actions'],16)),
                           out=dict(valid=bool(raw['valid']),ready=bool(raw['ready']),
                                    data=int(raw['data'],16),keep=int(raw['keep'],16),
                                    last=bool(raw['last']),user=int(raw['user'],16))))
    return result
