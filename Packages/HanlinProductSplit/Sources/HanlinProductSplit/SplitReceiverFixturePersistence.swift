import Foundation

extension SplitFixtureStore: SplitReceiverPersistence {
    public func transaction(_ operation: @Sendable (inout SplitReceiverDatabase) throws -> SplitReceiverRecord) throws -> SplitReceiverRecord {
        try locked {
            let path = try url(.receiver)
            var database = FileManager.default.fileExists(atPath: path.path)
                ? try read(SplitReceiverDatabase.self, from: .receiver) : SplitReceiverDatabase()
            try database.validate()
            let record = try operation(&database)
            try database.validate()
            try write(database, to: .receiver)
            guard try read(SplitReceiverDatabase.self, from: .receiver) == database else { throw SplitDurabilityError.corruptState }
            return record
        }
    }
}
