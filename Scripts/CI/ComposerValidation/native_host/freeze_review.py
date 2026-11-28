"""Freeze/check small source-review metadata; canonical Swift stays in memory."""
import argparse
import json
import sys

sys.dont_write_bytecode = True
import prepare_native as native
from validate_packet import validate, controls


def review_files():
    originals = native.frozen_inputs(native.REPO)
    generated, staged, manifest = native.make_packet(originals, (native.HERE / 'ComposerNativeUnitHost.swift').read_bytes())
    manifest['read_only_pattern_provenance'] = native.provenance(native.REPO)
    receipt = validate(generated, staged, manifest, originals)
    receipt['rejected_mutations'] = controls(generated, staged, manifest, originals)
    manifest['review_materialization'] = 'PBX/scheme/metadata only; canonical Swift held in memory and not copied locally'
    manifest['source_tool_sha256'] = {p: native.digest((native.HERE / p).read_bytes()) for p in
                                     ['prepare_native.py', 'validate_packet.py', 'freeze_review.py', 'ComposerNativeUnitHost.swift']}
    files = dict(generated)
    files['native-inputs.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    files['source-controls.json'] = (json.dumps(receipt, indent=2) + '\n').encode()
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='compare reviewed bytes without writes')
    args = parser.parse_args()
    files = review_files()
    root = native.HERE / 'review'
    for path, raw in files.items():
        dest = root / path
        if args.check:
            if not dest.is_file() or dest.read_bytes() != raw:
                raise SystemExit('review drift: ' + path)
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(raw)
    if args.check and {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()} != set(files):
        raise SystemExit('unexpected review files')
    print(json.dumps({'status': 'SOURCE_REVIEW_MATCH' if args.check else 'SOURCE_REVIEW_FROZEN',
                      'files': {p: native.digest(raw) for p, raw in files.items()},
                      'apple_build_or_test': 'NOT_RUN', 'full_app_acceptance': False}, indent=2))


if __name__ == '__main__':
    main()
