#!/usr/bin/env python3
"""Install the search supervisor as a per-user launch agent (starts after login)."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

root=Path(__file__).resolve().parent.parent
label='com.muntathir.search'
path=Path.home()/'Library/LaunchAgents'/f'{label}.plist'
logs=root/'backend/work'
logs.mkdir(exist_ok=True)
path.parent.mkdir(parents=True,exist_ok=True)
content={'Label':label,'ProgramArguments':[sys.executable,str(root/'backend/serve.py')],
    'WorkingDirectory':str(root),'RunAtLoad':True,'KeepAlive':True,'ThrottleInterval':10,
    'EnvironmentVariables':{'PATH':os.environ['PATH']},
    'StandardOutPath':str(logs/'service.log'),'StandardErrorPath':str(logs/'service-error.log')}
with path.open('wb') as file:plistlib.dump(content,file)
subprocess.run(['launchctl','bootout',f'gui/{os.getuid()}',str(path)],check=False,capture_output=True)
subprocess.run(['launchctl','bootstrap',f'gui/{os.getuid()}',str(path)],check=True)
print('Installed '+label+'; starts after user login')
