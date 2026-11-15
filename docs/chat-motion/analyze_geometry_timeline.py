"""Summarize native geometry samples; sample frequency is not display-frame/FPS evidence."""
import argparse,json,math,statistics
from pathlib import Path

def analyze(samples):
    groups=[]
    for sample in samples:
        key=(sample['preset'],sample['expanded'])
        if not groups or groups[-1]['key']!=key:groups.append({'key':key,'samples':[]})
        row={name:float(sample[name]) for name in ['seconds','height','natural']}
        assert all(math.isfinite(value) for value in row.values())
        groups[-1]['samples'].append(row)
    result={}
    presets=['v1.relaxed','v1.height-reveal','v1.gentle-squeeze','v1.quiet-fade','v1.none']
    for preset in presets:
        directions={}
        for direction in ['true','false']:
            matches=[g for g in groups if g['key']==(preset,direction)]
            completed=[]
            for group in matches:
                rows=group['samples'];last=rows[-1];target=last['natural']+6
                is_complete=(last['natural']>0 and abs(last['height']-target)<0.5) if direction=='true' else last['height']<0.25
                # Ignore an initial collapsed observation before the first user action.
                if direction=='false' and not any(row['height']>=0.25 for row in rows) and preset!='v1.none':continue
                if is_complete:
                    completed.append({'elapsed_seconds':last['seconds'],'sample_count':len(rows),
                        'intermediate_height_samples':sum(0.25<row['height']<target-0.5 for row in rows)})
            durations=[row['elapsed_seconds'] for row in completed]
            directions['opening' if direction=='true' else 'closing']={
                'completed_groups':len(completed),
                'median_seconds':statistics.median(durations) if durations else None,
                'min_seconds':min(durations) if durations else None,
                'max_seconds':max(durations) if durations else None,
                'groups_with_intermediate_heights':sum(row['intermediate_height_samples']>0 for row in completed),
                'sample_count':sum(row['sample_count'] for row in completed)}
        result[preset]=directions
    return {'source':'Actual onGeometryChange samples from instrumented disposable iPad host',
        'presets':result,'sample_count':len(samples),
        'limits':['Geometry sampling is not rendered-frame/FPS measurement',
            'Instrumentation changes update cost; this is not uninstrumented app performance',
            'Elapsed time is measured from the fixture expanded-binding change, not just configured duration',
            'Original app/Markdown/AgentRun/paused scrolling/iPad26/physical acceptance remains separate']}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('timeline',type=Path);p.add_argument('--output',type=Path);a=p.parse_args()
    result=analyze(json.loads(a.timeline.read_text(encoding='utf-8')))
    data=json.dumps(result,indent=2)+'\n'
    if a.output:a.output.write_bytes(data.encode())
    else:print(data)
