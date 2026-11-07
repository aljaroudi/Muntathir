#!/usr/bin/env python3
"""Provision only the dedicated search hostname and remotely managed tunnel."""
import json
from pathlib import Path
import urllib.request
from serve import environment, ROOT

DOMAIN='xn--pgbou4cf.com'
HOST='search.'+DOMAIN
NAME='muntathir-search'

def main():
    env=environment();token=env.get('CLOUDFLARE_API_TOKEN')
    if not token:raise SystemExit('Add CLOUDFLARE_API_TOKEN to backend/.env')
    def call(method,path,body=None):
        request=urllib.request.Request('https://api.cloudflare.com/client/v4'+path,method=method,
            headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'},data=None if body is None else json.dumps(body).encode())
        with urllib.request.urlopen(request,timeout=30) as response:result=json.load(response)
        if not result['success']:raise RuntimeError('Cloudflare operation failed')
        return result['result']
    zones=call('GET','/zones?name='+DOMAIN)
    if len(zones)!=1:raise SystemExit('Token must allow access to the domain zone')
    zone=zones[0];account=zone['account']['id'];base=f'/accounts/{account}/cfd_tunnel'
    matches=[t for t in call('GET',base+'?is_deleted=false&name='+NAME) if t['name']==NAME]
    if len(matches)>1:raise SystemExit('Ambiguous tunnel name')
    tunnel=matches[0] if matches else call('POST',base,{'name':NAME,'config_src':'cloudflare'})
    tunnel_id=tunnel['id'];tunnel_token=call('GET',base+'/'+tunnel_id+'/token')
    call('PUT',base+'/'+tunnel_id+'/configurations',{'config':{'ingress':[
        {'hostname':HOST,'service':'http://127.0.0.1:8788'}, {'service':'http_status:404'}]}})
    records=call('GET',f"/zones/{zone['id']}/dns_records?name={HOST}")
    expected=tunnel_id+'.cfargotunnel.com'
    if records:
        if len(records)!=1 or records[0]['type']!='CNAME' or records[0]['content']!=expected:
            raise SystemExit('Existing DNS record differs; refusing to overwrite unrelated routing')
    else:call('POST',f"/zones/{zone['id']}/dns_records",{'type':'CNAME','name':HOST,'content':expected,'proxied':True,'ttl':1})
    updates={'CLOUDFLARE_TUNNEL_TOKEN':tunnel_token,'SEARCH_TRUST_TUNNEL':'true','SEARCH_PUBLIC_URL':'https://'+HOST+'/v1/search'}
    path=ROOT/'backend/.env';lines=path.read_text().splitlines()
    lines=[line for line in lines if line.partition('=')[0].strip() not in updates]
    path.write_text('\n'.join(lines)+ '\n' + '\n'.join(k+'='+v for k,v in updates.items())+'\n');path.chmod(0o600)
    print('Configured https://'+HOST+'/v1/search; tunnel credentials saved locally')

if __name__=='__main__':main()
