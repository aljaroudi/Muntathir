#!/usr/bin/env python3
"""Supervise the private search API, Apple Container, and optional Cloudflare tunnel."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time
import urllib.request

ROOT=Path(__file__).resolve().parent.parent

def environment():
    result=dict(os.environ)
    # Read dotenv as data; never execute credential files as shell scripts.
    path=ROOT/'backend/.env'
    if path.exists():
        for line in path.read_text().splitlines():
            line=line.strip()
            if not line or line.startswith('#'):continue
            key,sep,value=line.partition('=')
            if sep and key.strip().isidentifier():result[key.strip()]=value.strip().strip('\"\'')
    return result

def main():
    env=environment();env.setdefault('PATH','/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin')
    name=env.get('QDRANT_CONTAINER','muntathir-search-qdrant')
    bun=shutil.which('bun',path=env['PATH']);container=shutil.which('container',path=env['PATH'])
    if not bun or not container:raise RuntimeError('Install Bun and Apple Container first')
    children=[];stopping=False
    def stop(*_):
        nonlocal stopping
        stopping=True
        for child in children:
            if child.poll() is None:child.terminate()
    signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
    subprocess.run([container,'system','start'],env=env,check=False)
    api=None;tunnel=None;failures=0
    try:
        while not stopping:
            try:
                with urllib.request.urlopen(env.get('QDRANT_URL','http://127.0.0.1:56333')+'/healthz',timeout=5) as response:
                    if response.status!=200:raise OSError('Qdrant not healthy')
            except OSError:
                subprocess.run([container,'start',name],env=env,check=False)
            if api is None or api.poll() is not None:
                api_env={k:v for k,v in env.items() if not k.startswith(('SUPABASE_', 'CLOUDFLARE_', 'SEARCH_SUPABASE_'))}
                api=subprocess.Popen([bun,'backend/api/server.ts'],cwd=ROOT,env=api_env);children.append(api)
            if env.get('CLOUDFLARE_TUNNEL_TOKEN') and (tunnel is None or tunnel.poll() is not None):
                binary=shutil.which('cloudflared',path=env['PATH'])
                if not binary:raise RuntimeError('Install cloudflared before enabling tunnel')
                token=ROOT/'backend/work/tunnel-token';token.touch(mode=0o600);token.chmod(0o600);token.write_text(env['CLOUDFLARE_TUNNEL_TOKEN'])
                tunnel=subprocess.Popen([binary,'tunnel','--no-autoupdate','run','--token-file',str(token)],cwd=ROOT,env=env);children.append(tunnel)
            try:
                with urllib.request.urlopen('http://127.0.0.1:'+env.get('SEARCH_PORT','8788')+'/healthz',timeout=8) as response:
                    failures=0 if response.status==200 else failures+1
            except OSError:failures+=1
            if failures>=3 and api.poll() is None:api.terminate();failures=0
            for _ in range(15):
                if stopping:break
                time.sleep(1)
    finally:
        stop()
        for child in children:
            try:child.wait(timeout=10)
            except subprocess.TimeoutExpired:child.kill()

if __name__=='__main__':main()
