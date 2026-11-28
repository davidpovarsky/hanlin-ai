import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let mcpTGZ = UTType(filenameExtension: "tgz") ?? .gzip
}

struct MCPPackageImportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.mcpTGZ, .gzip] }

    let data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
