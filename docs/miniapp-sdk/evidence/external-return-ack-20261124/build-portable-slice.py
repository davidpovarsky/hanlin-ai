#!/usr/bin/env python3
"""Compile exact return/mailbox methods and the existing native failed-callback case.
This excludes UIKit/SwiftUI setup and substitutes cleanup bookkeeping only; it
cannot prove native scene teardown or UIApplication.open behavior.
"""
from pathlib import Path
import sys, json, hashlib
root=Path(sys.argv[1]).resolve(); destination=Path(sys.argv[2]).resolve()
destination.mkdir(parents=True, exist_ok=False)
session_path=root/'AI_HLY/Downstream/ProductSplitIntegration/HanlinExternalMiniAppSession.swift'
test_path=root/'HanlinMiniAppsTests/CrossAppInvocationTests.swift'
session=session_path.read_text(); tests=test_path.read_text(); bindings=[]
def block(text, marker, path):
    assert text.count(marker)==1, marker
    start=text.index(marker); brace=text.index('{',start); depth=1; end=brace+1
    while depth:
        assert end<len(text), marker
        if text[end]=='{': depth+=1
        elif text[end]=='}': depth-=1
        end+=1
    result=text[start:end]
    bindings.append({'source':str(path.relative_to(root)), 'marker':marker,
        'sourceSHA256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'startLine':text[:start].count('\n')+1,
        'excerptSHA256':hashlib.sha256(result.encode()).hexdigest(),
        'verbatim':True})
    return result
methods=[block(session, marker, session_path) for marker in [
    '    private func mailbox()', '    func restoreRequest()',
    '    func perform(', '    func returnToSource()',
    '    private func completeJSON(', '    private func finish(',
    '    private func failure(', '    static func localized(']]
if '    enum SourceReturnOutcome:' in session:
    methods.insert(0,block(session,'    enum SourceReturnOutcome:',session_path))
header="""import Foundation

// Foundation-only projection. Methods below are verbatim production excerpts.
// No native engine/presenter implementation is replaced or claimed to execute.
@MainActor
final class HanlinExternalMiniAppSession {
    let requestID: UUID
    private(set) var request: MiniAppInvocation?
    private(set) var result: MiniAppResult?
    private(set) var returning = false
    var error: String?
    private let storeOverride: MiniAppBridgeStore?
    private let openSource: @MainActor (URL) async -> Bool
    private(set) var cleanupCalls = 0
    init(requestID: UUID, store: MiniAppBridgeStore?,
         openSource: @escaping @MainActor (URL) async -> Bool) {
        self.requestID = requestID; self.storeOverride = store; self.openSource = openSource
    }
    private func releaseEngine() { cleanupCalls += 1 }
"""
source_dir=destination/'Sources/ReturnAckSlice';source_dir.mkdir(parents=True)
(source_dir/'SessionSlice.swift').write_text(header+'\n\n'.join(methods)+'\n}\n')
for name in ['MiniAppContracts.swift','MiniAppPreferences.swift','MiniAppBridgeStore.swift']:
    original=root/'Packages/HanlinMiniAppsBridge/Sources/HanlinMiniAppsBridge'/name
    (source_dir/name).write_bytes(original.read_bytes())
    bindings.append({'source':str(original.relative_to(root)), 'sourceSHA256':hashlib.sha256(original.read_bytes()).hexdigest(),'completeOriginalFile':True})
test_dir=destination/'Tests/ReturnAckSliceTests';test_dir.mkdir(parents=True)
selected=[block(tests,marker,test_path) for marker in [
    '    private func fixture()', '    private func request(',
    '    func testUnavailableCallbackRetainsResultForSourceRecovery()']]
(test_dir/'ExistingReturnAckCase.swift').write_text('import Foundation\nimport XCTest\n@testable import ReturnAckSlice\n\n@MainActor\nfinal class CrossAppInvocationTests: XCTestCase {\n'+'\n\n'.join(selected)+'\n}\n')
(destination/'Package.swift').write_text('// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: "ReturnAckSlice", targets: [\n    .target(name: "ReturnAckSlice"),\n    .testTarget(name: "ReturnAckSliceTests", dependencies: ["ReturnAckSlice"]),\n], swiftLanguageModes: [.v6])\n')
(destination/'source-bindings.json').write_text(json.dumps({'scope':'Exact original Foundation contracts/store plus verbatim selected session methods and existing failed-callback XCTest. Cleanup counter is harness-only; no UIKit, engine, OS-opening or native acceptance claim.','bindings':bindings},indent=2)+'\n')
print(json.dumps({'project':str(destination),'verbatimExcerpts':len([b for b in bindings if b.get('verbatim')]),'originalFiles':len([b for b in bindings if b.get('completeOriginalFile')]),'boundaries':['No UIKit/SwiftUI compilation','No UIApplication.open execution','No engine or scene teardown proof']}))
