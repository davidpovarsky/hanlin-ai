"""Check explicit target boundaries; this is source validation, never an iOS pass."""
from pathlib import Path
import json
import plistlib
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def main():
    project = (ROOT / 'AI_HLY.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
    membership = json.loads((ROOT / 'docs/product-split/target-membership.json').read_text())
    sources = membership['shared_sources']
    assert len(sources) == len(set(sources)), 'duplicate shared sources'
    for source in sources:
        assert (ROOT / source).is_file(), source
        assert f'path = "{source}";' in project, source
        assert not any(part in source for part in ['/ChatInput/', '/ChatView.swift', '/Views/Components/Chat'])
    for source in membership['excludes']:
        assert source not in sources, source
    for resource in membership.get('shared_resources', []):
        assert f'path = "{resource}";' in project or f'path = {resource};' in project, resource
        if resource != 'AI_HLY/RuntimeHostResources.zip':
            assert (ROOT / resource).is_file(), resource
    assert 'PRODUCT_BUNDLE_IDENTIFIER = com.itorah.chavrusachat;' in project
    assert 'PRODUCT_BUNDLE_IDENTIFIER = com.itorah.hanlinminiapps;' in project
    assert 'name = HanlinMiniApps;' in project
    assert 'name = AI_Hanlin;' in project
    scheme = ET.parse(ROOT / 'AI_HLY.xcodeproj/xcshareddata/xcschemes/HanlinMiniApps.xcscheme')
    assert scheme.find('.//Testables//BuildableReference').attrib['BlueprintName'] == 'HanlinMiniAppsUITests'
    assert {node.attrib['BlueprintName'] for node in scheme.findall('.//Testables//BuildableReference')} == {
        'HanlinMiniAppsUITests', 'HanlinMiniAppsTests'}
    entitlements = plistlib.loads((ROOT / 'HanlinMiniAppsApp/HanlinMiniApps.entitlements').read_bytes())
    assert set(entitlements['com.apple.security.application-groups']) == {
        'group.com.itorah.chavrusachat', 'group.com.itorah.shared'}
    assert 'com.apple.developer.icloud-container-identifiers' not in entitlements
    info = plistlib.loads((ROOT / 'HanlinMiniAppsApp/Info.plist').read_bytes())
    assert info['UTImportedTypeDeclarations']
    assert info['CFBundleDocumentTypes'][0]['LSItemContentTypes'] == [
        'com.hanlin.scripting-package', 'public.zip-archive']
    manifest = (ROOT / 'Packages/HanlinProductSplit/Package.swift').read_text()
    for name in ['SplitFixtureStore.swift', 'SplitReceiverFixturePersistence.swift', 'SplitMigrationFixturePersistence.swift']:
        assert name in manifest, name
    # Every object declaration must have a unique identity. References repeat.
    identities = re.findall(r'^\s*([A-F0-9]{24})(?: /\*.*?\*/)? = \{\s*isa = ', project, re.M)
    assert len(identities) == len(set(identities)), 'duplicate PBX objects'
    print(json.dumps({'status': 'SOURCE_VALIDATED', 'shared_source_count': len(sources),
                      'ios_build': 'NOT_RUN', 'ios_ui': 'NOT_RUN'}))


if __name__ == '__main__':
    main()
