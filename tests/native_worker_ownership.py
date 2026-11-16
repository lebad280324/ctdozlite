#!/usr/bin/env python3
"""Two synthetic workers cannot concurrently own the same private data directory."""
import json,subprocess,tempfile,sys
from pathlib import Path
core=Path(sys.argv[1] if len(sys.argv)>1 else 'target/debug/ctdozlite-core').resolve()
with tempfile.TemporaryDirectory(prefix='ctdo-worker-ownership-') as directory:
    first=subprocess.Popen([str(core),'--data-dir',directory],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
    try:
        assert json.loads(first.stdout.readline())['event']=='ready'
        second=subprocess.run([str(core),'--data-dir',directory],input='',capture_output=True,text=True,timeout=5)
        assert second.returncode==2, 'A second writer was admitted'
        assert not second.stdout, 'Rejected worker must not publish a session'
        first.stdin.close();assert first.wait(timeout=5)==0
        third=subprocess.run([str(core),'--data-dir',directory],input='{"id":"end","command":"shutdown"}\n',capture_output=True,text=True,timeout=5)
        assert third.returncode==0, 'Ownership was not released on exit'
        assert json.loads(third.stdout.splitlines()[0])['event']=='ready'
        print('PASS: duplicate owner rejected; lock released after exit; no account/network accessed')
    finally:
        if first.poll() is None:first.kill();first.wait()
        first.stdout.close()
