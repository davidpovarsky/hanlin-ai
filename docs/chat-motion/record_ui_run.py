"""Bound recording to120s, finalize with SIGINT; recording does not drive UI actions."""
import argparse,json,signal,subprocess,threading
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('--device',required=True);p.add_argument('--evidence',type=Path,required=True);p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args()
command=a.command[1:] if a.command[0]=='--' else a.command
log=(a.evidence/'video.log').open('wb');video=None;timer=None
def stop():
    if video is not None and video.poll() is None:
        try:video.send_signal(signal.SIGINT)
        except ProcessLookupError:pass
test=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',bufsize=1)
try:
    for line in test.stdout:
        print(line,end='',flush=True)
        lower=line.lower()
        # xcodebuild owns simulator startup. Capture starts only on an actual
        # XCTest case event, never on an assumed boot delay or private state.
        if video is None and (('test case' in lower and 'started' in lower) or 'start test at' in lower):
            video=subprocess.Popen(['xcrun','simctl','io',a.device,'recordVideo','--codec=h264',str(a.evidence/'motion-first120s.mp4')],stdout=log,stderr=log)
            timer=threading.Timer(120,stop);timer.start()
    result=test.wait()
finally:
    if timer is not None:timer.cancel()
    stop()
    if video is not None:
        try:video.wait(timeout=15)
        except subprocess.TimeoutExpired:video.kill();video.wait();(a.evidence/'motion-first120s.mp4').unlink(missing_ok=True)
    log.close()
    (a.evidence/'video-status.json').write_text(json.dumps({'exit_code':video.returncode if video is not None else None,
        'status':'CAPTURE_ATTEMPTED' if video is not None else 'NOT_STARTED_NO_XCTEST_CASE_EVENT',
        'maximum_recording_seconds':120,'scope':'first120s from an actual XCTest case event, not every preset or original app'}))
raise SystemExit(result)
