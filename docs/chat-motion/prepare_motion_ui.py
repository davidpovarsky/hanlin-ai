"""Disposable native UI host for exact Motion components; original app acceptance is separate."""
import argparse, hashlib, json, shutil, sys, textwrap
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
PRODUCTION=[f'AI_HLY/Downstream/ChatPresentation/{name}.swift' for name in
    ['ChatMotionConfiguration','ChatMotionPreferences','HanlinAnimatedDisclosure','ChatShimmerEffect']]
SOURCE='AI_HLY/Views/Components/ChatViewComponents.swift'
APP='docs/chat-motion/MotionUI/App.swift'; TEST='docs/chat-motion/MotionUI/MotionUITests.swift'
ASSET='AI_HLY/Assets.xcassets/HLBluefont.colorset/Contents.json'
STRINGS='AI_HLY/Resource/Localizable.xcstrings'
sha=lambda data:hashlib.sha256(data).hexdigest()

def snippets():
    source=(ROOT/SOURCE).read_text(encoding='utf-8')
    loading=source[source.index('struct LoadingGradientText:'):source.index('struct ChatBubbleView:')].strip()
    start=source.index('    private struct ToggleButton:')
    end=source.index('    @ViewBuilder\n    private func chatBubbleImage()',start)
    toggle=textwrap.dedent(source[start:end]).strip().replace('private struct ToggleButton:', 'struct ToggleButton:',1)
    return 'import SwiftUI\n\n'+loading+'\n\n'+toggle+'\n'

def spec():
    common={'GENERATE_INFOPLIST_FILE':'YES','SWIFT_VERSION':'6.0','CODE_SIGNING_ALLOWED':'NO',
        'TARGETED_DEVICE_FAMILY':'1,2','ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS':'YES'}
    return {'name':'ChatMotionProof','options':{'deploymentTarget':{'iOS':'26.0'}},'settings':{'base':common},
        'targets':{
            'ChatMotionProof':{'type':'application','platform':'iOS','sources':['Production','App'],
                'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':'ai.hanlin.motion-proof',
                    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES',
                    'INFOPLIST_KEY_UILaunchScreen_Generation':'YES',
                    'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad':'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'}}},
            'ChatMotionProofUITests':{'type':'bundle.ui-testing','platform':'iOS','sources':['UITests'],
                'dependencies':[{'target':'ChatMotionProof'}],
                'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':'ai.hanlin.motion-proof.uitests','TEST_TARGET_NAME':'ChatMotionProof'}}}},
        'schemes':{'ChatMotionProof':{'build':{'targets':{'ChatMotionProof':'all'}},'test':{'targets':['ChatMotionProofUITests']}}}}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path);a=p.parse_args()
    files=PRODUCTION+[SOURCE,APP,TEST,ASSET,STRINGS]
    receipt={'scope':'Motion components; original app/renderer/engine/scroll regression NOT_RUN',
        'files':[{'path':path,'sha256':sha((ROOT/path).read_bytes())} for path in files],
        'extracted_snippets_sha256':sha(snippets().encode()),
        'extraction':'Exact LoadingGradientText and original nested ToggleButton; imports narrowed to SwiftUI, outer ToggleButton access changed private to internal only; no body edits',
        'project_spec_sha256':sha(json.dumps(spec(),indent=2).encode())}
    if a.output:
        dest=a.output.resolve()
        if sys.platform!='darwin' or dest.exists() or dest.is_relative_to(ROOT):raise ValueError('Fresh macOS scratch path outside checkout required')
        for directory in ['Production','App','UITests']: (dest/directory).mkdir(parents=True,exist_ok=True)
        for path in PRODUCTION:shutil.copyfile(ROOT/path,dest/'Production'/Path(path).name)
        (dest/'Production/OriginalChatSnippets.swift').write_text(snippets())
        shutil.copyfile(ROOT/APP,dest/'App/App.swift');shutil.copyfile(ROOT/TEST,dest/'UITests/MotionUITests.swift')
        shutil.copyfile(ROOT/STRINGS,dest/'App/Localizable.xcstrings')
        assets=dest/'App/Colors.xcassets';(assets/'HLBluefont.colorset').mkdir(parents=True)
        (assets/'Contents.json').write_text('{"info":{"author":"xcode","version":1}}')
        shutil.copyfile(ROOT/ASSET,assets/'HLBluefont.colorset/Contents.json')
        (dest/'project.json').write_text(json.dumps(spec(),indent=2))
        (dest/'proof-inputs.json').write_text(json.dumps(receipt,indent=2))
    print(json.dumps(receipt,indent=2))

if __name__=='__main__':main()
