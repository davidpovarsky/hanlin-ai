"""Materialize only the already-pinned Host compiler lock entry for portable tests.

No dependency/engine is added to Hanlin. npm ci is a separate explicit proof command.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HOST_LOCK = ROOT/'AI_HLY/Downstream/RuntimeCore/Node/Host/package-lock.json'


def main():
    original = json.loads(HOST_LOCK.read_text(encoding='utf-8'))
    compiler = original['packages']['node_modules/typescript']
    assert compiler['version'] == '6.0.3'
    assert compiler['resolved'] == 'https://registry.npmjs.org/typescript/-/typescript-6.0.3.tgz'
    assert compiler['integrity'].startswith('sha512-')
    manifest = {'name': 'hanlin-existing-ts-ast-proof', 'private': True, 'version': '0.0.0',
                'dependencies': {'typescript': compiler['version']}}
    lock = {'name': manifest['name'], 'version': manifest['version'], 'lockfileVersion': 3, 'requires': True,
            'packages': {'': {'name': manifest['name'], 'version': manifest['version'],
                             'dependencies': manifest['dependencies']}, 'node_modules/typescript': compiler}}
    output = ROOT/'build/ast-ts-proof'
    output.mkdir(parents=True, exist_ok=True)
    for name, value in [('package.json', manifest), ('package-lock.json', lock)]:
        destination = output/name
        if destination.exists():
            assert json.loads(destination.read_text(encoding='utf-8')) == value, 'Preserve a different existing proof'
        else:
            destination.write_bytes((json.dumps(value, indent=2)+'\n').encode())
    print(json.dumps({'compiler': compiler['version'], 'integrity': compiler['integrity'],
                      'scope': 'portable exact compiler only; embedded Node JITless NOT_RUN'}))


if __name__ == '__main__':
    main()
