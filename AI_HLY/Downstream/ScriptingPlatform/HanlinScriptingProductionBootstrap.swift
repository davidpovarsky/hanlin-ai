import Foundation

/// Downstream bootstrap for Scripting / ScriptUI production runtime and acceptance staging.
enum HanlinScriptingProductionBootstrap {
    private static let validFixtureBase64 = "UEsDBBQAAAAAAAAAIVwLij/GSgEAAEoBAAAJAAAAaW5kZXgudHN4aW1wb3J0IHsgQnV0dG9uLCBOYXZpZ2F0aW9uLCBUZXh0LCBWU3RhY2ssIHVzZVN0YXRlLCBmZXRjaCB9IGZyb20gInNjcmlwdGluZyIKCmZ1bmN0aW9uIEFwcCgpIHsKICBjb25zdCBbY291bnQsIHNldENvdW50XSA9IHVzZVN0YXRlKDApCiAgcmV0dXJuIDxWU3RhY2sgc3BhY2luZz17OH0+CiAgICA8VGV4dD5Db3VudCB7Y291bnR9PC9UZXh0PgogICAgPEJ1dHRvbiB0aXRsZT0iSW5jcmVtZW50IiBhY3Rpb249eygpID0+IHNldENvdW50KHZhbHVlID0+IHZhbHVlICsgMSl9IC8+CiAgPC9WU3RhY2s+Cn0KCk5hdmlnYXRpb24ucHJlc2VudCh7IGVsZW1lbnQ6IDxBcHAgLz4gfSkKUEsDBBQAAAAAAAAAIVyA0AD3aAAAAGgAAAALAAAAc2NyaXB0Lmpzb257CiAgIm5hbWUiOiAiSGFubGluIFNjcmlwdFVJIFZhbGlkIiwKICAidmVyc2lvbiI6ICIxLjAuMCIsCiAgImVudHJ5IjogImluZGV4LnRzeCIsCiAgInJ1bkluQXBwIjogdHJ1ZQp9ClBLAQIUABQAAAAAAAAAIVwLij/GSgEAAEoBAAAJAAAAAAAAAAAAAACkAQAAAABpbmRleC50c3hQSwECFAAUAAAAAAAAACFcgNAA92gAAABoAAAACwAAAAAAAAAAAAAApAFxAQAAc2NyaXB0Lmpzb25QSwUGAAAAAAIAAgBwAAAAAgIAAAAA"

    private static let malformedFixtureBase64 = "UEsDBBQAAAAAAAAAIVw+a53lVAAAAFQAAAALAAAAc2NyaXB0Lmpzb257CiAgIm5hbWUiOiAiSGFubGluIFNjcmlwdFVJIE1hbGZvcm1lZCIsCiAgInZlcnNpb24iOiAiMS4wLjAiLAogICJydW5JbkFwcCI6IHRydWUKfQpQSwECFAAUAAAAAAAAACFcPmud5VQAAABUAAAACwAAAAAAAAAAAAAApAEAAAAAc2NyaXB0Lmpzb25QSwUGAAAAAAEAAQA5AAAAfQAAAAAA"

    @MainActor
    static func prepareTestFixturesIfNeeded() {
        guard ProcessInfo.processInfo.environment["HANLIN_SCRIPTUI_E2E"] != nil else { return }
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let validURL = documentsURL.appending(path: "HanlinScriptUIValid.scripting")
        if !FileManager.default.fileExists(atPath: validURL.path(percentEncoded: false)),
           let data = Data(base64Encoded: validFixtureBase64) {
            try? data.write(to: validURL, options: .atomic)
        }

        let malformedURL = documentsURL.appending(path: "HanlinScriptUIMalformed.scripting")
        if !FileManager.default.fileExists(atPath: malformedURL.path(percentEncoded: false)),
           let data = Data(base64Encoded: malformedFixtureBase64) {
            try? data.write(to: malformedURL, options: .atomic)
        }
    }
}
