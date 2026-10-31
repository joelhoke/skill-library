import Foundation

public enum SkillStatus: String, Codable, CaseIterable { case ready = "Ready", draft = "Draft", repair = "Needs repair" }
public enum Origin: String, Codable, CaseIterable { case personal = "Personal", project = "Project-specific", thirdParty = "Third-party", unknown = "Unknown" }
public struct Source: Codable, Hashable, Identifiable {
    public var id: String { location + (taskID ?? "") }
    public var location: String
    public var taskID: String?
    public var notes: String
    public init(location: String, taskID: String? = nil, notes: String = "") { self.location = location; self.taskID = taskID; self.notes = notes }
}
public struct Revision: Codable, Identifiable, Hashable {
    public var id: String
    public var hash: String
    public var date: Date
    public var note: String
}
public struct Skill: Codable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    public var category: String
    public var origin: Origin
    public var status: SkillStatus
    public var dependencies: [String]
    public var sources: [Source]
    public var issues: [String]
    public var revisions: [Revision]
    public var currentRevision: String
    public var isRecovered: Bool
    public var hidden: Bool = false
}
public struct SkillPin: Codable, Hashable, Identifiable {
    public var id: String { skillID + ":" + revisionID }
    public var skillID: String
    public var revisionID: String
    public init(skillID: String, revisionID: String) { self.skillID = skillID; self.revisionID = revisionID }
}
public struct StarterKit: Codable, Identifiable {
    public var id: String
    public var name: String
    public var skills: [SkillPin]
    public var templateFolder: String?
}
public struct Coverage: Codable, Identifiable {
    public var id: String
    public var source: String
    public var status: String
    public var detail: String
    public var date: Date
    public init(source: String, status: String, detail: String) { id = UUID().uuidString; self.source = source; self.status = status; self.detail = detail; date = Date() }
}
public struct ProjectRecord: Codable, Identifiable {
    public var id: String
    public var path: String
    public var date: Date
    public var transactionID: String
}
public struct Catalog: Codable {
    public var schemaVersion = 1
    public var skills: [Skill] = []
    public var kits: [StarterKit] = []
    public var projects: [ProjectRecord] = []
    public var coverage: [Coverage] = []
    public var scanRoots: [String] = []
    public init() {}
}
public struct RecoveryPackage: Codable {
    public var schemaVersion: Int
    public var packageID: String
    public var skills: [RecoveryItem]
    public var coverage: [RecoveryCoverage]
}
public struct RecoveryItem: Codable {
    public var folder: String
    public var category: String
    public var origin: Origin
    public var dependencies: [String]
    public var sources: [Source]
}
public struct RecoveryCoverage: Codable { public var source: String; public var status: String; public var detail: String }
public struct FileBlob: Codable, Equatable {
    public var data: Data
    public var executable: Bool
    public var permissions: Int
    public init(data: Data, executable: Bool = false, permissions: Int? = nil) { self.data = data; self.executable = executable; self.permissions = permissions ?? (executable ? 0o755 : 0o644) }
}
public struct InstalledSkill: Codable {
    public var skillID: String; public var revisionID: String; public var name: String; public var hash: String
}
public struct ProjectManifest: Codable {
    public var schemaVersion = 1
    public var skills: [InstalledSkill] = []
    public var files: [String: String] = [:]
    public init() {}
}
public enum ChangeKind: String { case add = "Add", replace = "Conflict", unchanged = "Unchanged" }
public struct FileChange: Identifiable {
    public var id: String { path }
    public var path: String
    public var before: FileBlob?
    public var after: FileBlob
    public var kind: ChangeKind { before == nil ? .add : (before == after ? .unchanged : .replace) }
}
public struct Preparation {
    public var root: URL
    public var changes: [FileChange]
    public var installed: [InstalledSkill]
    public var previousManifest: FileBlob?
}
public enum ConflictChoice: String, CaseIterable { case keep = "Keep existing", replace = "Replace with selected" }
public struct JournalEntry: Codable {
    public var path: String
    public var before: FileBlob?
    public var after: FileBlob
    public var applied: Bool
    public var reverted: Bool = false
}
public struct Transaction: Codable, Identifiable {
    public var id: String
    public var root: String
    public var date: Date
    public var state: String
    public var entries: [JournalEntry]
}
public struct LibraryError: LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public enum JSONFiles {
    public static func read<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
    public static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    public static func write<T: Encodable>(_ value: T, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data(value).write(to: url, options: .atomic)
    }
}
