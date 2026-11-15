"""Copy owned sources into a disposable native proof; never vendor upstream parsers."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
PINS = {
    'swift-tree-sitter': ('0.25.0', '08ef81eb8620617b55b08868126707ad72bf754f'),
    'tree-sitter-bash': ('0.25.1', 'a06c2e4415e9bc0346c6b86d401879ffb44058f7'),
    'tree-sitter': ('0.25.10', 'da6fe9beb4f7f67beb75914ca8e0d48ae48d6406'),
}


def manifest():
    dependencies = ',\n'.join(f'        .package(url: "https://github.com/tree-sitter/{name}", exact: "{version}")'
                               for name, (version, _) in PINS.items())
    return '''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "HanlinSkillAnalysisProof",
    platforms: [.macOS(.v13), .iOS("26.0")],
    products: [.library(name: "HanlinSkillAnalysisProof", targets: ["HanlinSkillAnalysisProof"])],
    dependencies: [
''' + dependencies + '''
    ],
    targets: [
        .target(name: "HanlinSkillAnalysisProof", dependencies: [
            .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            .product(name: "TreeSitter", package: "tree-sitter"),
            .product(name: "TreeSitterBash", package: "tree-sitter-bash")],
            swiftSettings: [.define("HANLIN_SKILL_ANALYSIS_POC")]),
        .testTarget(name: "BashSyntaxTests", dependencies: ["HanlinSkillAnalysisProof"],
            resources: [.copy("Fixtures")])
    ])
'''


def files():
    sources = sorted((ROOT/'AI_HLY/Downstream/AgentSkills/Analysis').glob('*.swift'))
    tests = sorted((HERE/'Tests').rglob('*'))
    return sources + [p for p in tests if p.is_file()]


def plan():
    tests = re.findall(r'^    func (test\w+)\(', (HERE/'Tests/BashSyntaxTests.swift').read_text(encoding='utf-8'), re.M)
    fixtures = json.loads((HERE/'Tests/Fixtures/bash.json').read_text(encoding='utf-8'))
    assert len(fixtures) == 20 and len({f['file'] for f in fixtures}) == 20
    assert len(tests) == len(set(tests)) == 9
    paths = files() + [HERE/'prepare_bash_proof.py', HERE/'run_bash_proof.sh']
    return {'scope': 'original Bash parser only; Python/TS/product/readiness NOT_RUN',
            'pins': {name: {'version': version, 'revision': revision} for name, (version, revision) in PINS.items()},
            'cases': tests, 'bash_fixtures': 20,
            'manifest_sha256': hashlib.sha256(manifest().encode()).hexdigest(),
            'files': [{'path': p.relative_to(ROOT).as_posix(), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]}


def verify_pin(path):
    pins = json.loads(path.read_text(encoding='utf-8'))['pins']
    assert len(pins) == 3, pins
    for name, (version, revision) in PINS.items():
        matches = [p for p in pins if p['identity'] == name]
        assert len(matches) == 1, name
        actual = matches[0]
        assert actual['state'] == {'revision': revision, 'version': version}, actual
        assert actual['location'].removesuffix('.git') == f'https://github.com/tree-sitter/{name}', actual


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path)
    parser.add_argument('--verify-pin', type=Path)
    args = parser.parse_args()
    if args.verify_pin:
        verify_pin(args.verify_pin)
        print(json.dumps({'status': 'EXACT_ORIGINAL_PINS_VERIFIED'}))
        return
    result = plan()
    if args.output:
        output = args.output.resolve()
        assert platform.system() == 'Darwin', 'Native preparation requires the Apple authority host'
        assert output != ROOT and ROOT not in output.parents and not output.exists()
        output.mkdir(parents=True)
        for source in files():
            if source.is_relative_to(HERE/'Tests'):
                target = output/'Tests/BashSyntaxTests'/source.relative_to(HERE/'Tests')
            else:
                target = output/'Sources/HanlinSkillAnalysisProof'/source.name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
        (output/'Package.swift').write_bytes(manifest().encode())
        (output/'proof-inputs.json').write_bytes((json.dumps(result, indent=2)+'\n').encode())
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
