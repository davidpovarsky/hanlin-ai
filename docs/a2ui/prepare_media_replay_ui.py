"""Prepare exact production A2UI/media sources in a disposable native UI test host.

This proves component SwiftUI behavior, not the original ChatView/SDK/provider path.
The product project and user data are never opened or modified.
"""
import argparse
import json
from pathlib import Path
import re
import sys
from prepare_exact_pin_proof import REPOSITORY, UPSTREAM, REVISION, sha

APP = 'docs/a2ui/MediaReplayUI/App.swift'
TEST = 'docs/a2ui/MediaReplayUI/MediaReplayUITests.swift'
FIXTURE = 'AI_HLYUITests/Fixtures/A2UIReplayMedia.jsonl'
SWIFTSOUP_URL = 'https://github.com/scinfu/SwiftSoup.git'
SWIFTSOUP_REVISION = 'bba848db50462894e7fc0891d018dfecad4ef11e'


def plan():
    paths = sorted((REPOSITORY / 'AI_HLY/Downstream/ChatPresentation/A2UI').glob('*.swift'))
    paths += sorted((REPOSITORY / 'AI_HLY/Downstream/ChatPresentation/Media').glob('*.swift'))
    paths += [REPOSITORY / path for path in [APP, TEST, FIXTURE]]
    cases = re.findall(r'^    func (test\w+)\(', (REPOSITORY / TEST).read_text(encoding='utf-8'), re.M)
    assert len(cases) == len(set(cases)) == 12, cases
    # Authenticate parseable complete fixture frames before dispatch; SDK validation is native.
    frames = [json.loads(line) for line in (REPOSITORY / FIXTURE).read_text(encoding='utf-8').splitlines()]
    assert len(frames) == 3 and all(frame['version'] == '1.0' for frame in frames)
    return {'scope': 'actual SwiftUI component UI; original ChatView/SDK/provider/physical NOT_RUN',
            'upstream': UPSTREAM, 'revision': REVISION, 'cases': cases,
            'files': [{'path': p.relative_to(REPOSITORY).as_posix(), 'sha256': sha(p.read_bytes())} for p in paths],
            'project_spec_sha256': sha(json.dumps(spec(), indent=2).encode())}


def spec():
    common = {'GENERATE_INFOPLIST_FILE': 'YES', 'SWIFT_VERSION': '6.0',
              'CODE_SIGNING_ALLOWED': 'NO', 'TARGETED_DEVICE_FAMILY': '1,2',
              'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited) DEBUG HANLIN_A2UI_POC'}
    return {'name': 'MediaReplay', 'options': {'deploymentTarget': {'iOS': '27.0'}},
            'settings': {'base': common},
            'packages': {'A2UI': {'url': UPSTREAM, 'revision': REVISION},
                         'SwiftSoup': {'url': SWIFTSOUP_URL, 'revision': SWIFTSOUP_REVISION}},
            'targets': {
                'MediaReplay': {'type': 'application', 'platform': 'iOS',
                    'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'ai.hanlin.media-replay-proof',
                        'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES',
                        'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES'}},
                    'sources': ['Production', {'path': 'App/App.swift'},
                        {'path': 'App/A2UIReplayMedia.jsonl', 'buildPhase': 'resources'}],
                    'dependencies': [{'package': 'A2UI', 'product': product} for product in
                        ['A2UISwiftCore', 'A2UISwiftUI', 'BasicCatalog', 'BasicCatalogSwiftUI']]
                        + [{'package': 'SwiftSoup', 'product': 'SwiftSoup'}]},
                'MediaReplayUITests': {'type': 'bundle.ui-testing', 'platform': 'iOS',
                    'sources': ['UITests'], 'dependencies': [{'target': 'MediaReplay'}],
                    'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'ai.hanlin.media-replay-proof.uitests',
                                         'TEST_TARGET_NAME': 'MediaReplay'}}}},
            'schemes': {'MediaReplay': {'build': {'targets': {'MediaReplay': 'all'}},
                                      'test': {'targets': ['MediaReplayUITests']}}}}


def verify_media_pins(lock):
    from prepare_exact_pin_proof import verify_pin
    verify_pin(lock)
    pins = [p for p in lock['pins'] if p.get('identity') == 'swiftsoup']
    assert len(pins) == 1 and pins[0]['location'] == SWIFTSOUP_URL
    assert pins[0]['state']['revision'] == SWIFTSOUP_REVISION
    product_lock = json.loads((REPOSITORY / 'AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())
    original = [p for p in product_lock['pins'] if p.get('identity') == 'swiftsoup']
    assert len(original) == 1 and original[0]['state']['revision'] == SWIFTSOUP_REVISION


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    inputs = plan()
    if args.output:
        target = args.output.resolve()
        if sys.platform != 'darwin' or target.exists() or target.is_relative_to(REPOSITORY):
            raise ValueError('Use a fresh macOS scratch directory outside the checkout')
        target.mkdir()
        for row in inputs['files']:
            original = REPOSITORY / row['path']
            data = original.read_bytes()
            assert sha(data) == row['sha256'], row['path']
            folder = 'App' if row['path'] in [APP, FIXTURE] else 'UITests' if row['path'] == TEST else 'Production'
            destination = target / folder / original.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
        (target / 'project.json').write_bytes(json.dumps(spec(), indent=2).encode())
        (target / 'proof-inputs.json').write_bytes((json.dumps(inputs, indent=2) + '\n').encode())
    print(json.dumps(inputs, indent=2))


if __name__ == '__main__':
    main()
