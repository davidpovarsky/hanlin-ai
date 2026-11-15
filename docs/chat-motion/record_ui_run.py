"""Bound recording to120s, finalize with SIGINT; recording does not drive UI actions."""
import argparse,json,signal,subprocess,threading
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('--device',required=True);p.add_argument('--evidence',type=Path,required=True);p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args()
command=a.command[1:] if a.command[0]=='--' else a.command
log=(a.evidence/'video.log').open('wb')
video=subprocess.Popen(['xcrun','simctl','io',a.device,'recordVideo','--codec=h264',str(a.evidence/'motion-first120s.mp4')],stdout=log,stderr=log)
def stop():
    if video.poll() is None:
        try:video.send_signal(signal.SIGINT)
        except ProcessLookupError:pass
timer=threading.Timer(120,stop);timer.start()
try:
    result=subprocess.run(command)
finally:
    timer.cancel();stop()
    try:video.wait(timeout=15)
    except subprocess.TimeoutExpired:video.kill();video.wait();(a.evidence/'motion-first120s.mp4').unlink(missing_ok=True)
    log.close()
    (a.evidence/'video-status.json').write_text(json.dumps({'exit_code':video.returncode,'maximum_recording_seconds':120,'scope':'first120s of native component UI execution, not every preset or original app'}))
raise SystemExit(result.returncode)
