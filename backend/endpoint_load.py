#!/usr/bin/env python3
"""Measure full HTTP endpoint latency. Uncached runs incur Gemini embedding charges."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import time
import urllib.request
import urllib.error


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--url',required=True);p.add_argument('--rate',type=int,default=2);p.add_argument('--seconds',type=int,default=60);p.add_argument('--output',required=True)
    args=p.parse_args();queries=json.loads(Path('backend/evaluation.json').read_text())['queries']
    def one(index,scheduled):
        q=queries[index%len(queries)];body={k:q[k] for k in ('query','kinds','sources','languages') if q.get(k) is not None};body['limit']=20
        request=urllib.request.Request(args.url,data=json.dumps(body).encode(),headers={'Content-Type':'application/json','User-Agent':'Muntathir/1.0'})
        try:
            with urllib.request.urlopen(request,timeout=15) as response:
                result=json.load(response)
                return {'status':response.status,'ms':(time.monotonic()-scheduled)*1000,'items':len(result['results']),'timing':response.headers.get('Server-Timing')}
        except urllib.error.HTTPError as error:return {'status':error.code,'ms':(time.monotonic()-scheduled)*1000}
        except Exception as error:return {'status':0,'ms':(time.monotonic()-scheduled)*1000,'error':type(error).__name__}
    futures=[];start=time.monotonic()
    with ThreadPoolExecutor(max_workers=64) as executor:
        for i in range(args.rate*args.seconds):
            scheduled=start+i/args.rate;time.sleep(max(0,scheduled-time.monotonic()));futures.append(executor.submit(one,i,scheduled))
        details=[future.result() for future in futures]
    values=sorted(d['ms'] for d in details)
    report={'url':args.url,'rate':args.rate,'seconds':args.seconds,'requests':len(details),'errors':sum(d['status']!=200 for d in details),'p95_ms':values[max(0,__import__('math').ceil(len(values)*.95)-1)],'details':details}
    Path(args.output).write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k!='details'}))

if __name__=='__main__':main()
