import Foundation

public final class ProjectPreparer {
    public let library: Library
    public init(_ library: Library) { self.library = library }
    public func preview(pins: [SkillPin], root: URL, templateFolder: String? = nil) throws -> Preparation {
        let project = root.standardizedFileURL
        guard project.path != "/", project.path != SafeFiles.fm.homeDirectoryForCurrentUser.path,
              !project.path.hasPrefix(library.root.path + "/"), project.path != library.root.path else { throw LibraryError("Choose a project folder outside the library.") }
        var desired: [String: FileBlob] = [:], installed: [InstalledSkill] = [], names: Set<String> = []
        for pin in pins {
            guard let skill = library.catalog.skills.first(where: { $0.id == pin.skillID }), skill.status == .ready else { throw LibraryError("Review selected drafts and fix validation issues before preparing a project.") }
            let files = try library.files(pin), meta = SkillValidation.inspect(files, fallback: skill.name)
            guard meta.issues.isEmpty else { throw LibraryError("The selected revision needs repair: \(meta.issues.joined(separator: "; "))") }
            guard names.insert(meta.name.lowercased()).inserted else { throw LibraryError("Two selected skills use the name \(meta.name). Choose one version.") }
            for (path, blob) in files { desired[".agents/skills/\(meta.name)/\(path)"] = blob }
            installed.append(InstalledSkill(skillID: pin.skillID, revisionID: pin.revisionID, name: meta.name, hash: SafeFiles.hash(files)))
        }
        if let templateFolder {
            for (path, blob) in try SafeFiles.tree(SafeFiles.target(library.root, templateFolder)) {
                guard !path.hasPrefix(".agents/"), path != ".skill-library.json" else { throw LibraryError("Starter files cannot replace skill folders or the manifest.") }
                desired[path] = blob
            }
        }
        guard !desired.isEmpty else { throw LibraryError("Select at least one skill or a kit with starter files.") }
        var canonical: Set<String> = []
        for path in desired.keys {
            guard canonical.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw LibraryError("File names collide on a Mac filesystem: \(path)") }
            for other in desired.keys where other.hasPrefix(path + "/") { throw LibraryError("A file is also used as a folder: \(other)") }
        }
        let changes = try desired.keys.sorted().map { path in FileChange(path: path, before: try SafeFiles.blob(SafeFiles.target(project, path)), after: desired[path]!) }
        let manifest = try SafeFiles.blob(SafeFiles.target(project, ".skill-library.json"))
        if manifest != nil { _ = try readManifest(project) }
        return Preparation(root: project, changes: changes, installed: installed, previousManifest: manifest)
    }
    public func apply(_ preview: Preparation, choices: [String: ConflictChoice], failAfter: Int? = nil) throws -> Transaction {
        let manifestURL = try SafeFiles.target(preview.root, ".skill-library.json")
        guard try SafeFiles.blob(manifestURL) == preview.previousManifest else { throw LibraryError("The project changed after preview. Review a fresh preview.") }
        // Recheck all files before writing any of them.
        for change in preview.changes {
            guard try SafeFiles.blob(SafeFiles.target(preview.root, change.path)) == change.before else { throw LibraryError("\(change.path) changed after preview. Review again before applying.") }
            if change.kind == .replace && choices[change.path] == nil { throw LibraryError("Choose Keep existing or Replace for every conflict.") }
        }
        var manifest = try readManifest(preview.root)
        var entries: [JournalEntry] = []
        for change in preview.changes {
            let keep = change.kind == .replace && choices[change.path] == .keep
            if !keep {
                manifest.files[change.path] = SafeFiles.hash(change.after)
                if change.kind != .unchanged { entries.append(JournalEntry(path: change.path, before: change.before, after: change.after, applied: false)) }
            }
        }
        for installed in preview.installed {
            manifest.skills.removeAll(where: { $0.name == installed.name })
            manifest.skills.append(installed)
        }
        manifest.skills.sort { $0.name < $1.name }
        let manifestBlob = FileBlob(data: try JSONFiles.data(manifest))
        if manifestBlob != preview.previousManifest { entries.append(JournalEntry(path: ".skill-library.json", before: preview.previousManifest, after: manifestBlob, applied: false)) }
        var transaction = Transaction(id: UUID().uuidString, root: preview.root.path, date: Date(), state: "Applying", entries: entries)
        try saveJournal(transaction)
        do {
            for i in transaction.entries.indices {
                if failAfter == i { throw LibraryError("Simulated interrupted write") }
                let entry = transaction.entries[i]
                let target = try SafeFiles.target(preview.root, entry.path)
                guard try SafeFiles.blob(target) == entry.before else { throw LibraryError("A file changed during preparation: \(entry.path)") }
                try SafeFiles.write(entry.after, target)
                transaction.entries[i].applied = true
                try saveJournal(transaction)
            }
            transaction.state = "Applied"; try saveJournal(transaction)
            try library.recordProject(path: preview.root.path, transaction: transaction.id)
            return transaction
        } catch {
            _ = try? rollback(transaction.id)
            throw error
        }
    }
    public func journals() throws -> [Transaction] {
        let folder = library.root.appendingPathComponent("transactions")
        guard SafeFiles.fm.fileExists(atPath: folder.path) else { return [] }
        return try SafeFiles.fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map { try JSONFiles.read(Transaction.self, $0) }.sorted { $0.date > $1.date }
    }
    public func rollback(_ id: String) throws -> [String] {
        guard UUID(uuidString: id) != nil else { throw LibraryError("Invalid transaction identifier.") }
        var transaction = try JSONFiles.read(Transaction.self, library.root.appendingPathComponent("transactions/\(id).json"))
        let root = URL(fileURLWithPath: transaction.root)
        var preserved: [String] = []
        // Roll back content before the manifest. Never replace edits made since installation.
        let indices = transaction.entries.indices.filter { transaction.entries[$0].path != ".skill-library.json" }.reversed() + transaction.entries.indices.filter { transaction.entries[$0].path == ".skill-library.json" }
        for i in indices {
            let entry = transaction.entries[i]
            if entry.reverted { continue }
            if entry.path == ".skill-library.json" && !preserved.isEmpty { preserved.append(entry.path); continue }
            do {
                let url = try SafeFiles.target(root, entry.path), current = try SafeFiles.blob(url)
                if current == entry.before { transaction.entries[i].reverted = true; try saveJournal(transaction); continue }
                guard current == entry.after else { preserved.append(entry.path); continue }
                if let before = entry.before { try SafeFiles.write(before, url) }
                else {
                    try SafeFiles.fm.removeItem(at: url)
                    var parent = url.deletingLastPathComponent()
                    while parent.path != root.path && parent.path.hasPrefix(root.path + "/") {
                        guard (try? SafeFiles.fm.contentsOfDirectory(atPath: parent.path).isEmpty) == true else { break }
                        try SafeFiles.fm.removeItem(at: parent); parent.deleteLastPathComponent()
                    }
                }
                transaction.entries[i].reverted = true
                try saveJournal(transaction)
            } catch { preserved.append(entry.path + " (" + error.localizedDescription + ")") }
        }
        transaction.state = preserved.isEmpty ? "Rolled back" : "Partially rolled back — later edits preserved"
        try saveJournal(transaction)
        return preserved
    }
    private func saveJournal(_ value: Transaction) throws { try JSONFiles.write(value, library.root.appendingPathComponent("transactions/\(value.id).json")) }
    public func readManifest(_ root: URL) throws -> ProjectManifest {
        let url = try SafeFiles.target(root, ".skill-library.json")
        guard SafeFiles.fm.fileExists(atPath: url.path) else { return ProjectManifest() }
        let manifest = try JSONFiles.read(ProjectManifest.self, url)
        guard manifest.schemaVersion == 1 else { throw LibraryError("This project manifest requires a newer app.") }
        return manifest
    }
    public func health(_ root: URL) throws -> [String] {
        let manifest = try readManifest(root)
        if manifest.skills.isEmpty { return ["No installed skills recorded."] }
        return manifest.skills.map { installed in
            do {
                let folder = try SafeFiles.target(root, ".agents/skills/\(installed.name)")
                let actual = try SafeFiles.hash(SafeFiles.tree(folder))
                let local = actual == installed.hash ? "Unchanged" : "Local edits or extra files"
                let latest = library.catalog.skills.first(where: { $0.id == installed.skillID })?.currentRevision
                return "\(installed.name): \(local)" + (latest != nil && latest != installed.revisionID ? " · Library update available" : "")
            } catch { return "\(installed.name): Missing or unreadable — \(error.localizedDescription)" }
        }
    }
}
