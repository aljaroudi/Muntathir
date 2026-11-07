#!/usr/bin/env python3
"""Resumable Qdrant import from existing batch artifacts; never calls Gemini."""
import argparse
import json
import math
import os
from pathlib import Path
import urllib.request
import uuid
from ingest import PROFILE, digest, atomic_json, validate_vector

SERVING_PROFILE = 'gemini-embedding-2:1536:search-v1'

class Client:
    def __init__(self, url=None):
        self.url = (url or os.environ.get('QDRANT_URL', 'http://127.0.0.1:56333')).rstrip('/')
    def call(self, method, path, body=None):
        headers = {'Content-Type':'application/json'}
        if os.environ.get('QDRANT_API_KEY'): headers['api-key'] = os.environ['QDRANT_API_KEY']
        request = urllib.request.Request(self.url + path, data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.load(response)['result']

def project(vector):
    validate_vector(vector)
    prefix=vector[:1536];norm=math.sqrt(sum(x*x for x in prefix))
    if not norm: raise ValueError('Zero embedding prefix')
    return [x/norm for x in prefix]

def compact(item):
    nav=item['navigation'];kind=item['kind']
    if kind=='quran': return {'kind':kind,'chapter':nav['chapter'],'verse':nav['verse']}
    if kind=='hadith': return {'kind':kind,'book':nav['book'],'chapter':nav['chapterFile'],'number':nav['number']}
    if kind=='dua': return {'kind':kind,'id':nav['dua_id']}
    raise ValueError('Unknown content kind')

def load_manifest(work):
    manifest=json.loads((work/'manifest.json').read_text())
    if manifest['profile']!=PROFILE: raise ValueError('Profile mismatch')
    uuid.UUID(manifest['revision'])
    return manifest

def import_corpus(work, client):
    manifest=load_manifest(work)
    fingerprint=digest(json.dumps({k:manifest[k] for k in ('revision','profile','items','sources','texts','passages')},sort_keys=True,ensure_ascii=False))
    collection='search_'+manifest['revision'].replace('-','')+'_'+fingerprint[:12]
    items={r['id']:r for r in manifest['items']};texts={r['id']:r for r in manifest['texts']};sources={r['id']:r for r in manifest['sources']}
    path=work/'qdrant-progress.json';progress=json.loads(path.read_text()) if path.exists() else {}
    if progress and (progress['hash']!=fingerprint or progress['url']!=client.url): raise ValueError('Manifest or destination changed; use a new work directory')
    collections=client.call('GET','/collections')['collections']
    exists=any(c['name']==collection for c in collections)
    if not exists:
        client.call('PUT','/collections/'+collection,{'vectors':{'size':1536,'distance':'Cosine','on_disk':False},'hnsw_config':{'m':0},'optimizers_config':{'indexing_threshold':0},'on_disk_payload':True})
        progress={}
    offset=progress.get('offset',0)
    for start in range(offset,len(manifest['passages']),128):
        points=[]
        for p in manifest['passages'][start:start+128]:
            text=texts[p['text_id']];item=items[text['item_id']]
            if text['revision_id']!=manifest['revision'] or text['full_text'][p['start_offset']:p['end_offset']]!=p['text']:raise ValueError('Invalid passage offsets/revision')
            if digest(PROFILE+':'+p['input'])!=p['input_hash']:raise ValueError('Changed embedding input')
            vector=project(json.loads((work/'vectors'/(p['input_hash']+'.json')).read_text()))
            payload={**p,'item_id':item['id'],'kind':item['kind'],'source_id':item['source_id'],'language':text['language'],
                'ref':compact(item),'revision':manifest['revision'],'profile':SERVING_PROFILE,'manifest_hash':fingerprint,
                'text_revision':text,'source':sources[item['source_id']],'title':item['title'],'reference':item['reference']}
            points.append({'id':p['id'],'vector':vector,'payload':payload})
        client.call('PUT',f'/collections/{collection}/points?wait=true',{'points':points})
        progress={'hash':fingerprint,'url':client.url,'collection':collection,'offset':start+len(points),'validated':False}
        atomic_json(path,progress)
        if start%4096==0:print(f"Imported {progress['offset']}/{len(manifest['passages'])}",flush=True)
    for field,schema in [('kind','keyword'),('source_id','keyword'),('language','keyword'),('item_id','keyword'),('ref.book','keyword'),('ref.chapter','integer'),('ref.verse','integer'),('ref.number','integer'),('search_text',{'type':'text','tokenizer':'word','lowercase':True,'scoring':True})]:
        # ref.chapter is numeric for Quran, string for Hadith; only Quran reference lookup uses this index.
        client.call('PUT',f'/collections/{collection}/index?wait=true',{'field_name':field,'field_schema':schema})
    expected={p['id']:p['input_hash'] for p in manifest['passages']};seen=set();cursor=None
    while True:
        page=client.call('POST',f'/collections/{collection}/points/scroll',{'limit':1000,'offset':cursor,'with_payload':['input_hash','manifest_hash','profile'],'with_vector':False})
        for p in page['points']:
            if expected.get(p['id'])!=p['payload']['input_hash'] or p['payload']['manifest_hash']!=fingerprint or p['payload']['profile']!=SERVING_PROFILE:raise ValueError('Collection verification failed')
            seen.add(p['id'])
        cursor=page['next_page_offset']
        if cursor is None:break
    if seen!=set(expected):raise ValueError('Collection incomplete')
    progress['validated']=True;atomic_json(path,progress)
    print(json.dumps({'collection':collection,'points':len(seen),'validated':True}),flush=True)
    return collection

def activate(work,client):
    state=json.loads((work/'qdrant-progress.json').read_text())
    if not state['validated'] or state['url']!=client.url:raise ValueError('Import must validate before activation')
    manifest=load_manifest(work)
    fingerprint=digest(json.dumps({k:manifest[k] for k in ('revision','profile','items','sources','texts','passages')},sort_keys=True,ensure_ascii=False))
    if fingerprint!=state['hash']:raise ValueError('Manifest changed since validation')
    count=client.call('POST',f"/collections/{state['collection']}/points/count",{'exact':True})['count']
    if count!=len(manifest['passages']):raise ValueError('Collection count changed')
    aliases=client.call('GET','/aliases')['aliases']
    actions=[{'delete_alias':{'alias_name':'search'}}] if any(a['alias_name']=='search' for a in aliases) else []
    actions.append({'create_alias':{'alias_name':'search','collection_name':state['collection']}})
    client.call('POST','/collections/aliases',{'actions':actions})
    print('Activated '+state['collection'])

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['import','activate']);parser.add_argument('--workdir',required=True);parser.add_argument('--url')
    args=parser.parse_args();client=Client(args.url)
    (import_corpus if args.command=='import' else activate)(Path(args.workdir),client)
