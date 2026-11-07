#!/usr/bin/env python3
"""Prepare private search configuration; enable app URL only after public smoke test."""
import argparse
import json
from pathlib import Path
import plistlib
import secrets
import urllib.request
from urllib.parse import urlparse
from serve import environment, ROOT


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--app',action='store_true');args=parser.parse_args()
    env=environment();path=ROOT/'backend/.env'
    if not env.get('SEARCH_RATE_SALT'):
        with path.open('a') as file:file.write('\nSEARCH_RATE_SALT='+secrets.token_hex(32)+'\n')
    path.chmod(0o600)
    if args.app:
        url=env.get('SEARCH_PUBLIC_URL','');parsed=urlparse(url)
        if parsed.scheme!='https' or parsed.path!='/v1/search' or not parsed.hostname:raise SystemExit('Set the full HTTPS SEARCH_PUBLIC_URL')
        request=urllib.request.Request(url,data=json.dumps({'query':'2:255','kinds':['quran']}).encode(),headers={'Content-Type':'application/json','User-Agent':'Muntathir/1.0'})
        with urllib.request.urlopen(request,timeout=15) as response:result=json.load(response)
        if result!={'results':[{'kind':'quran','chapter':2,'verse':255,'score':None}]}:raise SystemExit('Public compact-reference smoke test failed')
        config=ROOT/'apple/Muntathir/Resources/SemanticSearchConfiguration.plist'
        config.write_bytes(plistlib.dumps({'url':url}));print('App configured for '+url)
    else:print('Private configuration ready; public app URL is unchanged')

if __name__=='__main__':main()
