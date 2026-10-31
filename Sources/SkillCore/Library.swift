import Foundation
import Darwin

public final class Library {
    public let root: URL
    public private(set) var catalog: Catalog
    private var lockFD: Int32 = -1
    public init(root: URL) throws {
        self.root = root.standardizedFileURL
        try SafeFiles.fm.createDirectory(at: root, withIntermediateDirectories: true)
        lockFD = open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { if lockFD >= 0 { close(lockFD) }; lockFD = -1; throw LibraryError("This library is already open. Close its other window or tool and try again.") }
        let url = root.appendingPathComponent("catalog.json")
        catalog = SafeFiles.fm.fileExists(atPath: url.path) ? try JSONFiles.read(Catalog.self, url) : Catalog()
        guard catalog.schemaVersion == 1 else { throw LibraryError("This catalog needs a newer version of Skill Library.") }
        try validateCatalogPaths()
    }
    deinit { if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD) } }
    private func validateCatalogPaths() throws {
        for skill in catalog.skills {
            guard UUID(uuidString: skill.id) != nil, skill.revisions.allSatisfy({ UUID(uuidString: $0.id) != nil }) else { throw LibraryError("Invalid catalog identifier.") }
        }
        for kit in catalog.kits { guard UUID(uuidString: kit.id) != nil else { throw LibraryError("Invalid kit identifier.") } }
    }
    public func save() throws { try JSONFiles.write(catalog, root.appendingPathComponent("catalog.json")) }
    public func snapshotURL(_ skillID: String, _ revisionID: String) throws -> URL {
        guard UUID(uuidString: skillID) != nil, UUID(uuidString: revisionID) != nil else { throw LibraryError("Invalid revision identifier.") }
        return try SafeFiles.target(root, "skills/\(skillID)/\(revisionID)")
    }
    public func files(_ pin: SkillPin) throws -> [String: FileBlob] {
        guard let skill = catalog.skills.first(where: { $0.id == pin.skillID }), let revision = skill.revisions.first(where: { $0.id == pin.revisionID }) else { throw LibraryError("The selected skill revision is no longer available.") }
        let tree = try SafeFiles.tree(snapshotURL(pin.skillID, pin.revisionID))
        guard SafeFiles.hash(tree) == revision.hash else { throw LibraryError("A saved revision was modified outside the app. Import that folder as a new revision before using it.") }
        return tree
    }
    @discardableResult public func importFolder(_ folder: URL, origin: Origin = .unknown, category: String = "General", sources: [Source]? = nil, recovered: Bool = false, dependencies: [String] = []) throws -> String {
        let files = try SafeFiles.tree(folder)
        return try importFiles(files, fallback: folder.lastPathComponent, origin: origin, category: category, sources: sources ?? [Source(location: folder.path)], recovered: recovered, dependencies: dependencies)
    }
    @discardableResult public func importFiles(_ files: [String: FileBlob], fallback: String, origin: Origin = .unknown, category: String = "General", sources: [Source] = [], recovered: Bool = false, dependencies: [String] = []) throws -> String {
        guard files["SKILL.md"] != nil else { throw LibraryError("Choose a skill folder containing SKILL.md.") }
        let hash = SafeFiles.hash(files), meta = SkillValidation.inspect(files, fallback: fallback)
        let old = catalog
        // Exact folder matches are one library entry even if found in many projects.
        if let index = catalog.skills.firstIndex(where: { $0.revisions.contains(where: { $0.hash == hash }) }) {
            for source in sources {
                if let existing = catalog.skills[index].sources.firstIndex(where: { $0.id == source.id }) { catalog.skills[index].sources[existing] = source }
                else { catalog.skills[index].sources.append(source) }
            }
            do { try save() } catch { catalog = old; throw error }
            return catalog.skills[index].id
        }
        let sameSource = catalog.skills.firstIndex { $0.name == meta.name && !$0.isRecovered && !recovered && $0.sources.contains(where: { prior in sources.contains(where: { $0.location == prior.location }) }) }
        let id = sameSource.map { catalog.skills[$0].id } ?? UUID().uuidString
        let revision = Revision(id: UUID().uuidString, hash: hash, date: Date(), note: recovered ? "Recovered draft" : "Imported complete skill folder")
        try SafeFiles.saveTree(files, snapshotURL(id, revision.id))
        if let index = sameSource {
            catalog.skills[index].revisions.append(revision)
            catalog.skills[index].currentRevision = revision.id
            catalog.skills[index].name = meta.name; catalog.skills[index].summary = meta.description
            catalog.skills[index].issues = meta.issues
            catalog.skills[index].dependencies = Array(Set(meta.dependencies + dependencies)).sorted()
            catalog.skills[index].status = meta.issues.isEmpty ? .draft : .repair
        } else {
            catalog.skills.append(Skill(id: id, name: meta.name, summary: meta.description, category: category, origin: origin, status: meta.issues.isEmpty ? (recovered ? .draft : .ready) : .repair, dependencies: Array(Set(meta.dependencies + dependencies)).sorted(), sources: sources, issues: meta.issues, revisions: [revision], currentRevision: revision.id, isRecovered: recovered))
        }
        do { try save() } catch { catalog = old; throw error }
        return id
    }
    public func edit(_ id: String, path: String = "SKILL.md", text: String, note: String = "Edited in Skill Library") throws {
        guard let index = catalog.skills.firstIndex(where: { $0.id == id }), SafeFiles.safeRelative(path) else { throw LibraryError("Skill or file not found.") }
        let skill = catalog.skills[index]
        var tree = try files(SkillPin(skillID: id, revisionID: skill.currentRevision))
        tree[path] = FileBlob(data: Data(text.utf8), executable: tree[path]?.executable ?? false, permissions: tree[path]?.permissions)
        try commitRevision(index, tree, note: note)
    }
    private func commitRevision(_ index: Int, _ tree: [String: FileBlob], note: String) throws {
        let old = catalog; let meta = SkillValidation.inspect(tree, fallback: catalog.skills[index].name)
        let hash = SafeFiles.hash(tree)
        if catalog.skills[index].revisions.first(where: { $0.id == catalog.skills[index].currentRevision })?.hash == hash { return }
        let revision = Revision(id: UUID().uuidString, hash: hash, date: Date(), note: note)
        try SafeFiles.saveTree(tree, snapshotURL(catalog.skills[index].id, revision.id))
        catalog.skills[index].revisions.append(revision); catalog.skills[index].currentRevision = revision.id
        catalog.skills[index].name = meta.name; catalog.skills[index].summary = meta.description; catalog.skills[index].issues = meta.issues
        catalog.skills[index].status = meta.issues.isEmpty ? .draft : .repair
        catalog.skills[index].dependencies = Array(Set(catalog.skills[index].dependencies + meta.dependencies)).sorted()
        do { try save() } catch { catalog = old; throw error }
    }
    public func restore(_ id: String, revision: String) throws {
        guard let index = catalog.skills.firstIndex(where: { $0.id == id }) else { throw LibraryError("Skill not found.") }
        try commitRevision(index, files(SkillPin(skillID: id, revisionID: revision)), note: "Restored revision \(revision.prefix(8))")
    }
    public func update(_ id: String, category: String, origin: Origin, status: SkillStatus, hidden: Bool, dependencies: [String]) throws {
        guard let index = catalog.skills.firstIndex(where: { $0.id == id }) else { return }
        if status == .ready && !catalog.skills[index].issues.isEmpty { throw LibraryError("Fix the validation issues before marking this skill ready.") }
        let old = catalog
        catalog.skills[index].category = category.isEmpty ? "General" : category; catalog.skills[index].origin = origin
        catalog.skills[index].status = status; catalog.skills[index].hidden = hidden; catalog.skills[index].dependencies = dependencies
        do { try save() } catch { catalog = old; throw error }
    }
    public func addCoverage(_ items: [Coverage]) throws { catalog.coverage.append(contentsOf: items); try save() }
    public func scan(_ roots: [URL], excluding: [URL] = []) throws -> Int {
        let result = SkillScanner.scan(roots, excluding: excluding + [root])
        var issues: [Coverage] = []; var count = 0
        for folder in result.folders {
            let path = folder.path
            let origin: Origin = path.contains("/.codex/skills/") || path.contains("/.agents/skills/") && path.hasPrefix(SafeFiles.fm.homeDirectoryForCurrentUser.appendingPathComponent(".agents").path) ? .personal : (path.contains("/.agents/skills/") ? .project : .unknown)
            do { try importFolder(folder, origin: origin); count += 1 }
            catch { issues.append(Coverage(source: path, status: "Import failed", detail: error.localizedDescription)) }
        }
        for url in roots where !catalog.scanRoots.contains(url.path) { catalog.scanRoots.append(url.path) }
        try addCoverage(result.coverage + issues)
        return count
    }
    public func importRecovery(_ folder: URL) throws {
        let package = try JSONFiles.read(RecoveryPackage.self, SafeFiles.target(folder, "package.json"))
        guard package.schemaVersion == 1 else { throw LibraryError("Unsupported recovery package version.") }
        // Validate every folder before changing the catalog; no partial package imports.
        let trees = try package.skills.map { item -> [String: FileBlob] in
            let tree = try SafeFiles.tree(SafeFiles.target(folder, item.folder))
            guard tree["SKILL.md"] != nil else { throw LibraryError("\(item.folder) has no SKILL.md.") }
            guard !item.sources.isEmpty else { throw LibraryError("Recovery drafts need evidence sources.") }
            return tree
        }
        let old = catalog
        do {
            for (item, tree) in zip(package.skills, trees) {
                try importFiles(tree, fallback: URL(fileURLWithPath: item.folder).lastPathComponent, origin: item.origin, category: item.category, sources: item.sources, recovered: true, dependencies: item.dependencies)
            }
            for entry in package.coverage {
                let source = package.packageID + " · " + entry.source
                if !catalog.coverage.contains(where: { $0.source == source && $0.detail == entry.detail && $0.status == entry.status }) {
                    catalog.coverage.append(Coverage(source: source, status: entry.status, detail: entry.detail))
                }
            }
            try save()
        } catch { catalog = old; try? save(); throw error }
    }
    @discardableResult public func saveKit(id: String? = nil, name: String, pins: [SkillPin], template: URL? = nil, keepTemplate: Bool = true) throws -> String {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, !pins.isEmpty || template != nil else { throw LibraryError("Give the kit a name and select a skill or starter folder.") }
        for pin in pins { _ = try files(pin) }
        let old = catalog, kitID = id ?? UUID().uuidString
        let existing = catalog.kits.first(where: { $0.id == kitID })
        var folder = keepTemplate ? existing?.templateFolder : nil
        if let template {
            let tree = try SafeFiles.tree(template)
            guard !tree.keys.contains(where: { $0.hasPrefix(".agents/") || $0 == ".skill-library.json" }) else { throw LibraryError("Starter files cannot replace skill folders or the installation manifest.") }
            folder = "templates/\(kitID)/\(UUID().uuidString)"
            try SafeFiles.saveTree(tree, SafeFiles.target(root, folder!))
        }
        catalog.kits.removeAll(where: { $0.id == kitID })
        catalog.kits.append(StarterKit(id: kitID, name: name, skills: pins, templateFolder: folder))
        do { try save() } catch { catalog = old; throw error }
        return kitID
    }
    public func deleteKit(_ id: String) throws { catalog.kits.removeAll(where: { $0.id == id }); try save() }
    public func recordProject(path: String, transaction: String) throws {
        catalog.projects.removeAll(where: { $0.path == path })
        catalog.projects.append(ProjectRecord(id: UUID().uuidString, path: path, date: Date(), transactionID: transaction))
        try save()
    }
    public func export(_ pins: [SkillPin], to destination: URL) throws {
        guard !SafeFiles.fm.fileExists(atPath: destination.path) else { throw LibraryError("Choose a new folder for the export.") }
        var items: [RecoveryItem] = []
        for pin in pins {
            guard let skill = catalog.skills.first(where: { $0.id == pin.skillID }) else { continue }
            let folder = "skills/\(skill.name)-\(skill.id.prefix(8))"
            try SafeFiles.saveTree(files(pin), SafeFiles.target(destination, folder))
            items.append(RecoveryItem(folder: folder, category: skill.category, origin: skill.origin, dependencies: skill.dependencies, sources: skill.sources.isEmpty ? [Source(location: "Skill Library export")] : skill.sources))
        }
        let package = RecoveryPackage(schemaVersion: 1, packageID: UUID().uuidString, skills: items, coverage: [RecoveryCoverage(source: "Library export", status: "Exported", detail: "Selected revisions. Imported copies require review.")])
        try JSONFiles.write(package, destination.appendingPathComponent("package.json"))
    }
}
