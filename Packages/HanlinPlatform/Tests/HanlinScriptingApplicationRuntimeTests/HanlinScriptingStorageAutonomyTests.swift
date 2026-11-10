import Foundation
import HanlinPlatformContracts
import Testing
@testable import HanlinScriptingApplicationRuntime

@MainActor
@Suite("Scripting canonical KV migration and explicit sharing", .serialized)
struct HanlinScriptingStorageAutonomyTests {
    @Test func largeRecordsSurviveReinstallationAndClearPreservesMigrationIntent() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "scripting-kv-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = UUID().uuidString.lowercased()
        let first = try HanlinInstalledPackageID(validating: "storage-first-\(identity)")
        let second = try HanlinInstalledPackageID(validating: "storage-second-\(identity)")
        let other = try HanlinInstalledPackageID(validating: "storage-other-\(identity)")
        let app = try HanlinAppID(validating: "canonical-\(identity)")
        let otherApp = try HanlinAppID(validating: "other-\(identity)")
        let suite = "com.hanlin.scripting.storage.\(first.rawValue)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("\"legacy-kept\"", forKey: "legacy")
        defaults.set(Data([0,127,255]), forKey: "__hanlin_data__:old-bytes")
        func run(_ id: HanlinInstalledPackageID, _ appID: HanlinAppID, _ program: String) throws {
            let session = try HanlinScriptingApplicationSession(installedPackageID: id, canonicalAppID: appID,
                program: program, filename: "compiled/storage.js", storageAllowed: true, runtimeRoot: root)
            defer { session.dispose() }
            #expect(session.model.root.properties["text"] == .string("passed"))
        }
        let present = "Navigation.present({element:createElement(Text,null,'passed')});"
        try run(first, app, #"""
        if(Storage.get('legacy')!=='legacy-kept' || Storage.getData('old-bytes').toHexString()!=='007fff')throw Error('legacy migration');
        const text='שלום'.repeat(180000);
        Storage.set('large',{text});
        if(Storage.get('large').text!==text)throw Error('large JSON was truncated');
        Storage.setData('large-bytes',Data.fromString(text));
        if(Storage.getData('large-bytes').size!==1440000 || Storage.getData('large-bytes').toRawString()!==text)throw Error('large binary was truncated');
        Storage.set('private','first');Storage.set('shared-record','intentional',{shared:true});
        """# + present)
        try run(other, otherApp, #"""
        if(Storage.get('private')!==null)throw Error('private identity leak');
        if(Storage.get('shared-record',{shared:true})!=='intentional')throw Error('shared namespace unavailable');
        Storage.set('private','other');Storage.clear();
        if(Storage.get('shared-record',{shared:true})!=='intentional')throw Error('private clear removed shared state');
        """# + present)
        try run(second, app, #"""
        if(Storage.get('large').text!=='שלום'.repeat(180000))throw Error('canonical JSON did not survive reinstall');
        if(Storage.getData('large-bytes').toRawString()!=='שלום'.repeat(180000))throw Error('canonical data did not survive reinstall');
        Storage.clear();
        """# + present)
        try run(first, app, #"""
        if(Storage.keys().length!==0)throw Error('clear resurrected preserved legacy defaults');
        if(Storage.get('shared-record',{shared:true})!=='intentional')throw Error('shared state lost on reopen');
        Storage.remove('shared-record',{shared:true});
        if(Storage.contains('shared-record',{shared:true}))throw Error('explicit shared removal failed');
        """# + present)
        #expect(defaults.string(forKey: "legacy") == "\"legacy-kept\"")
        #expect(defaults.data(forKey: "__hanlin_data__:old-bytes") == Data([0,127,255]))
    }

    @Test func storagePayloadPolicyIsExplicit() throws {
        let data = try JSONSerialization.data(withJSONObject: ["value":String(repeating:"x",count:21*1_024*1_024)])
        let json = String(decoding:data,as:UTF8.self)
        #expect(throws: HanlinScriptingNativeError.self) { try HanlinScriptingNativeJSON.decodeObject(json, maximumBytes: 20*1_024*1_024) }
        let decoded = try HanlinScriptingNativeJSON.decodeObject(json, maximumBytes:nil)
        #expect((decoded["value"] as? String)?.utf8.count == 21*1_024*1_024)
    }
}
