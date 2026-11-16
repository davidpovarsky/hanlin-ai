"""Seed only the isolated original renderer test lock from authenticated app pins.

Original app lock, renderer source/manifest and upstream pin/pruning policy are untouched.
Original SwiftPM resolves/adopts the supplied states and verification rejects any drift.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT/'docs/chat-diagnostics/markdown-consumer-closure-2026-11-15.json'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def verify(actual, contract):
    pins = actual['pins']
    assert len({p['identity'] for p in pins}) == len(pins)
    expected = {p['identity']: p for p in contract['original_renderer_lock']['pins']}
    expected.update({p['identity']: p for p in contract['runtime_pin_projection']})
    assert {p['identity'] for p in pins} == set(expected), 'Unknown or missing proof dependency'
    for pin in pins:
        wanted = expected[pin['identity']]
        assert pin['state'] == wanted['state'], (pin['identity'], pin['state'], wanted['state'])
        assert pin['location'].removesuffix('.git') == wanted['location'].removesuffix('.git'), pin['identity']


def verify_checkouts(actual, contract):
    expected = {p['identity']: p for p in contract['original_renderer_lock']['pins']}
    expected.update({p['identity']: p for p in contract['runtime_pin_projection']})
    found = {}
    for item in actual:
        identity = item['directory'].lower()
        if identity not in expected:
            continue  # A cached unused directory is not a resolved dependency.
        assert identity not in found
        assert item['revision'] == expected[identity]['state']['revision'], identity
        found[identity] = item['revision']
    assert set(found) == set(expected), 'Missing actual source checkout evidence'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--renderer', type=Path)
    parser.add_argument('--evidence', type=Path)
    parser.add_argument('--verify-lock', type=Path)
    args = parser.parse_args()
    contract = json.loads(CONTRACT.read_text(encoding='utf-8'))
    if args.verify_lock:
        verify(json.loads(args.verify_lock.read_text(encoding='utf-8')), contract)
        print(json.dumps({'status': 'EXACT_CONSUMER_CLOSURE_VERIFIED', 'dependencies': 10}))
        return
    assert args.renderer and args.evidence
    renderer = args.renderer.resolve(); evidence = args.evidence.resolve()
    assert renderer != ROOT and renderer.is_relative_to(ROOT/'build')
    revision = subprocess.check_output(['git', '-C', str(renderer), 'rev-parse', 'HEAD'], text=True).strip()
    assert revision == contract['renderer_revision']
    assert not subprocess.check_output(['git', '-C', str(renderer), 'status', '--porcelain']), 'Fresh original checkout required'
    original = json.loads((renderer/'Package.resolved').read_text(encoding='utf-8'))
    assert original == contract['original_renderer_lock']
    evidence.mkdir(parents=True, exist_ok=True)
    (evidence/'closure-contract.json').write_bytes(CONTRACT.read_bytes())
    (evidence/'renderer-Package.swift').write_bytes((renderer/'Package.swift').read_bytes())
    (evidence/'original-renderer-Package.resolved').write_bytes((renderer/'Package.resolved').read_bytes())
    projection = {p['identity']: p for p in contract['runtime_pin_projection']}
    for pin in original['pins']:
        if pin['identity'] in projection:
            wanted = projection[pin['identity']]
            assert pin['location'].removesuffix('.git') == wanted['location'].removesuffix('.git')
            # Keep the original package URL spelling/identity. Change only test lock states,
            # to already-resolved app versions; upstream SwiftPM must admit the unmodified manifests.
            pin['state'] = wanted['state']
    verify(original, contract)
    (renderer/'Package.resolved').write_bytes((json.dumps(original, indent=2)+'\n').encode())
    (evidence/'seeded-consumer-Package.resolved').write_bytes((renderer/'Package.resolved').read_bytes())
    tracked = subprocess.check_output(['git', '-C', str(renderer), 'ls-tree', '-r', 'HEAD'], text=True)
    (evidence/'renderer-tree.txt').write_text(tracked, encoding='utf-8')
    subprocess.run(['git', '-C', str(renderer), 'archive', '--format=tar.gz', '-o',
                    str(evidence/'original-renderer-source.tar.gz'), 'HEAD'], check=True)
    expected = {suite+'/'+name for suite, names in contract['expected_cases'].items() for name in names}
    assert len(expected) == 6
    test_files = list((renderer/'Tests').rglob('CodeBlockRendererTests.swift')) + list((renderer/'Tests').rglob('CodeBlockConfigTests.swift'))
    assert len(test_files) == 2
    (evidence/'test-inputs.json').write_text(json.dumps({'renderer': revision,
        'contract_sha256': sha(CONTRACT.read_bytes()), 'files': [
            {'path': p.relative_to(renderer).as_posix(), 'sha256': sha(p.read_bytes())} for p in test_files]}, indent=2), encoding='utf-8')
    print(json.dumps({'status': 'ISOLATED_TEST_LOCK_SEEDED', 'runtime_states_from': contract['app_evidence'],
                      'changed': list(contract['affected_transitive_changes'])}))


if __name__ == '__main__':
    main()
