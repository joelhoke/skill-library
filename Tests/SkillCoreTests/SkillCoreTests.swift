import XCTest
@testable import SkillCore

final class SkillCoreTests: XCTestCase {
    var root: URL!
    var lib: Library!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SkillLibraryTest-" + UUID().uuidString)
        lib = try Library(root: root.appendingPathComponent("library"))
    }
    override func tearDownWithError() throws { lib = nil; try FileManager.default.removeItem(at: root) }
    func tree(_ name: String = "sample", body: String = "Use this workflow.") -> [String: FileBlob] {
        ["SKILL.md": FileBlob(data: Data("---\nname: \(name)\ndescription: A useful reusable workflow\n---\n\(body)\n".utf8)), "scripts/helper.sh": FileBlob(data: Data("#!/bin/sh\necho hello\n".utf8), executable: true), "assets/template.txt": FileBlob(data: Data("starter".utf8))]
    }
    func add(_ files: [String: FileBlob]? = nil, recovered: Bool = false) throws -> SkillPin {
        let id = try lib.importFiles(files ?? tree(), fallback: "sample", sources: [Source(location: "test")], recovered: recovered)
        return SkillPin(skillID: id, revisionID: lib.catalog.skills.first { $0.id == id }!.currentRevision)
    }
    func project(_ name: String = "project") -> URL { root.appendingPathComponent(name) }
    func testCompleteFolderAndPermissionsRoundTrip() throws {
        let pin = try add()
        XCTAssertEqual(try lib.files(pin), tree())
        let exporter = root.appendingPathComponent("export")
        try lib.export([pin], to: exporter)
        try lib.importRecovery(exporter)
        XCTAssertEqual(lib.catalog.skills.count, 1)
        XCTAssertTrue(try lib.files(pin)["scripts/helper.sh"]!.executable)
    }
    func testDuplicateSourcesAndVariants() throws {
        let id = try lib.importFiles(tree(), fallback: "sample", sources: [Source(location: "a")])
        let duplicate = try lib.importFiles(tree(), fallback: "sample", sources: [Source(location: "b")])
        XCTAssertEqual(id, duplicate); XCTAssertEqual(lib.catalog.skills[0].sources.count, 2)
        _ = try lib.importFiles(tree(body: "Different workflow"), fallback: "sample", sources: [Source(location: "c")])
        XCTAssertEqual(lib.catalog.skills.count, 2)
    }
    func testSourceUpdateKeepsHistoryAndNeedsReview() throws {
        _ = try add(); _ = try add(tree(body: "Updated source"))
        XCTAssertEqual(lib.catalog.skills.count, 1); XCTAssertEqual(lib.catalog.skills[0].revisions.count, 2)
        XCTAssertEqual(lib.catalog.skills[0].status, .draft)
    }
    func testValidationMissingMalformedAndReferences() throws {
        XCTAssertFalse(SkillValidation.inspect([:], fallback: "bad").issues.isEmpty)
        let malformed = ["SKILL.md": FileBlob(data: Data("name: example\ndescription: no frontmatter".utf8))]
        _ = try add(malformed); XCTAssertEqual(lib.catalog.skills[0].status, .repair)
        let missing = SkillValidation.inspect(tree(body: "Read [guide](references/missing.md)."), fallback: "sample")
        XCTAssertTrue(missing.issues.contains { $0.contains("Missing local reference") })
        var block = tree(); block["SKILL.md"] = FileBlob(data: Data("---\nname: block-test\ndescription: >-\n  First line\n  second line\n---\nBody".utf8))
        XCTAssertEqual(SkillValidation.inspect(block, fallback: "sample").description, "First line second line")
    }
    func testEditRestoreDoesNotChangeOriginalRevision() throws {
        let pin = try add()
        let original = try lib.files(pin)
        try lib.edit(pin.skillID, path: "assets/template.txt", text: "changed")
        XCTAssertEqual(try lib.files(pin), original)
        try lib.restore(pin.skillID, revision: pin.revisionID)
        XCTAssertEqual(lib.catalog.skills[0].revisions.count, 3)
        XCTAssertEqual(try lib.files(SkillPin(skillID: pin.skillID, revisionID: lib.catalog.skills[0].currentRevision)), original)
    }
    func testRecoveryReviewKitPrepareEndToEnd() throws {
        let pin = try add(recovered: true)
        XCTAssertEqual(lib.catalog.skills[0].status, .draft)
        let preparer = ProjectPreparer(lib)
        XCTAssertThrowsError(try preparer.preview(pins: [pin], root: project()))
        try lib.edit(pin.skillID, text: "---\nname: sample\ndescription: Reviewed recovery\n---\nUse evidence.")
        try lib.update(pin.skillID, category: "Writing", origin: .personal, status: .ready, hidden: false, dependencies: [])
        let current = SkillPin(skillID: pin.skillID, revisionID: lib.catalog.skills[0].currentRevision)
        let kitID = try lib.saveKit(name: "Writing", pins: [current])
        let kit = lib.catalog.kits.first { $0.id == kitID }!
        let preview = try preparer.preview(pins: kit.skills, root: project())
        let tx = try preparer.apply(preview, choices: [:])
        XCTAssertEqual(tx.state, "Applied")
        XCTAssertTrue(FileManager.default.fileExists(atPath: project().appendingPathComponent(".agents/skills/sample/SKILL.md").path))
        XCTAssertEqual(try preparer.health(project()), ["sample: Unchanged"])
    }
    func testRepeatedPreparationSkipsUnchanged() throws {
        let pin = try add(), p = ProjectPreparer(lib)
        _ = try p.apply(p.preview(pins: [pin], root: project()), choices: [:])
        let preview = try p.preview(pins: [pin], root: project())
        XCTAssertTrue(preview.changes.allSatisfy { $0.kind == .unchanged })
        let tx = try p.apply(preview, choices: [:]); XCTAssertTrue(tx.entries.isEmpty)
    }
    func testConflictRequiresChoiceAndKeepPreserves() throws {
        let pin = try add(), p = ProjectPreparer(lib)
        _ = try p.apply(p.preview(pins: [pin], root: project()), choices: [:])
        let path = ".agents/skills/sample/SKILL.md"
        try SafeFiles.write(FileBlob(data: Data("my local edit".utf8)), project().appendingPathComponent(path))
        let preview = try p.preview(pins: [pin], root: project())
        XCTAssertThrowsError(try p.apply(preview, choices: [:]))
        _ = try p.apply(preview, choices: [path: .keep])
        XCTAssertEqual(try String(contentsOf: project().appendingPathComponent(path), encoding: .utf8), "my local edit")
        XCTAssertTrue(try p.health(project())[0].contains("Local edits"))
    }
    func testRollbackPreservesSubsequentEditsAndCanResume() throws {
        let pin = try add(), p = ProjectPreparer(lib)
        let tx = try p.apply(p.preview(pins: [pin], root: project()), choices: [:])
        let path = ".agents/skills/sample/assets/template.txt"
        try SafeFiles.write(FileBlob(data: Data("edited after prep".utf8)), project().appendingPathComponent(path))
        let preserved = try p.rollback(tx.id)
        XCTAssertTrue(preserved.contains(path))
        XCTAssertEqual(try String(contentsOf: project().appendingPathComponent(path), encoding: .utf8), "edited after prep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: project().appendingPathComponent(".agents/skills/sample/SKILL.md").path))
        XCTAssertTrue(try p.journals()[0].state.hasPrefix("Partially"))
    }
    func testReplacementRollbackRestoresOriginalAndAgentsUnchanged() throws {
        let pin = try add(), p = ProjectPreparer(lib)
        let path = ".agents/skills/sample/assets/template.txt"
        let original = FileBlob(data: Data("original".utf8))
        try SafeFiles.write(original, project().appendingPathComponent(path))
        try SafeFiles.write(FileBlob(data: Data("Existing instructions".utf8)), project().appendingPathComponent("AGENTS.md"))
        let tx = try p.apply(p.preview(pins: [pin], root: project()), choices: [path: .replace])
        XCTAssertTrue(try p.rollback(tx.id).isEmpty)
        XCTAssertEqual(try SafeFiles.blob(project().appendingPathComponent(path)), original)
        XCTAssertEqual(try String(contentsOf: project().appendingPathComponent("AGENTS.md"), encoding: .utf8), "Existing instructions")
    }
    func testStalePreviewDoesNotWrite() throws {
        let pin = try add(), p = ProjectPreparer(lib)
        let preview = try p.preview(pins: [pin], root: project())
        try SafeFiles.write(FileBlob(data: Data("new edit".utf8)), project().appendingPathComponent(".agents/skills/sample/SKILL.md"))
        XCTAssertThrowsError(try p.apply(preview, choices: [:]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: project().appendingPathComponent(".agents/skills/sample/assets/template.txt").path))
    }
    func testInterruptedWriteAutomaticallyReverts() throws {
        let pin = try add(), p = ProjectPreparer(lib)
        XCTAssertThrowsError(try p.apply(p.preview(pins: [pin], root: project()), choices: [:], failAfter: 1))
        XCTAssertEqual(try p.journals()[0].state, "Rolled back")
        XCTAssertFalse(FileManager.default.fileExists(atPath: project().appendingPathComponent(".agents/skills/sample/SKILL.md").path))
    }
    func testTraversalAndSymlinkRejection() throws {
        XCTAssertThrowsError(try SafeFiles.target(project(), "../escape"))
        try FileManager.default.createDirectory(at: project(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: project().appendingPathComponent(".agents"), withDestinationURL: root)
        let pin = try add()
        XCTAssertThrowsError(try ProjectPreparer(lib).preview(pins: [pin], root: project()))
        let source = root.appendingPathComponent("source")
        try SafeFiles.saveTree(tree(), source)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("escape"), withDestinationURL: root)
        XCTAssertThrowsError(try SafeFiles.tree(source))
    }
    func testSameNameSkillsAndCaseCollisionsBlocked() throws {
        let a = try add()
        let bID = try lib.importFiles(tree(body: "Variant"), fallback: "sample", sources: [Source(location: "second")])
        let b = SkillPin(skillID: bID, revisionID: lib.catalog.skills.first { $0.id == bID }!.currentRevision)
        XCTAssertThrowsError(try ProjectPreparer(lib).preview(pins: [a, b], root: project()))
        var mixed = tree("mixed"); mixed["assets/Template.txt"] = FileBlob(data: Data("case collision".utf8))
        let pin = try add(mixed)
        XCTAssertThrowsError(try ProjectPreparer(lib).preview(pins: [pin], root: project()))
    }
    func testTemplatesPinnedAndConflictsExplicit() throws {
        let pin = try add(), template = root.appendingPathComponent("template")
        try SafeFiles.saveTree(["README.txt": FileBlob(data: Data("starter project".utf8))], template)
        let id = try lib.saveKit(name: "Starter", pins: [pin], template: template)
        let kit = lib.catalog.kits.first { $0.id == id }!
        try SafeFiles.write(FileBlob(data: Data("original project".utf8)), project().appendingPathComponent("README.txt"))
        let preview = try ProjectPreparer(lib).preview(pins: kit.skills, root: project(), templateFolder: kit.templateFolder)
        XCTAssertEqual(preview.changes.first { $0.path == "README.txt" }?.kind, .replace)
        XCTAssertEqual(kit.skills, [pin])
    }
    func testImportPackageAtomicAndIdempotent() throws {
        let folder = root.appendingPathComponent("package")
        try SafeFiles.saveTree(tree(), folder.appendingPathComponent("skills/sample"))
        let item = RecoveryItem(folder: "skills/sample", category: "Test", origin: .unknown, dependencies: [], sources: [Source(location: "Task evidence", taskID: "task")])
        let package = RecoveryPackage(schemaVersion: 1, packageID: "test", skills: [item], coverage: [RecoveryCoverage(source: "Test task", status: "Partial", detail: "Reviewed source instructions")])
        try JSONFiles.write(package, folder.appendingPathComponent("package.json"))
        try lib.importRecovery(folder); try lib.importRecovery(folder)
        XCTAssertEqual(lib.catalog.skills.count, 1); XCTAssertEqual(lib.catalog.coverage.count, 1)
        XCTAssertEqual(lib.catalog.skills[0].status, .draft)
        var bad = package; bad.skills.append(RecoveryItem(folder: "../escape", category: "Test", origin: .unknown, dependencies: [], sources: [Source(location: "bad")]))
        try JSONFiles.write(bad, folder.appendingPathComponent("package.json"))
        XCTAssertThrowsError(try lib.importRecovery(folder)); XCTAssertEqual(lib.catalog.skills.count, 1)
    }
    func testScannerExclusionsAndMissingRootCoverage() throws {
        let scan = root.appendingPathComponent("scan")
        try SafeFiles.saveTree(tree(), scan.appendingPathComponent("project/.agents/skills/sample"))
        try SafeFiles.saveTree(tree(), scan.appendingPathComponent("node_modules/unwanted"))
        let result = SkillScanner.scan([scan, root.appendingPathComponent("missing")])
        XCTAssertEqual(result.folders.count, 1); XCTAssertEqual(result.coverage.last?.status, "Partial")
    }
    func testExclusiveLibraryLock() throws { XCTAssertThrowsError(try Library(root: lib.root)) }
    func testRollbackPreservesPrivateFilePermissions() throws {
        let pin = try add(), p = ProjectPreparer(lib)
        let path = ".agents/skills/sample/assets/template.txt"
        let original = FileBlob(data: Data("private original".utf8), permissions: 0o600)
        try SafeFiles.write(original, project().appendingPathComponent(path))
        let tx = try p.apply(p.preview(pins: [pin], root: project()), choices: [path: .replace])
        XCTAssertTrue(try p.rollback(tx.id).isEmpty)
        XCTAssertEqual(try SafeFiles.blob(project().appendingPathComponent(path)), original)
    }
    func testAbruptExitBetweenWriteAndJournalMarkCanRecover() throws {
        let pin = try add(), p = ProjectPreparer(lib)
        var tx = try p.apply(p.preview(pins: [pin], root: project()), choices: [:])
        tx.state = "Applying"
        for i in tx.entries.indices { tx.entries[i].applied = false }
        try JSONFiles.write(tx, lib.root.appendingPathComponent("transactions/\(tx.id).json"))
        XCTAssertTrue(try p.rollback(tx.id).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: project().appendingPathComponent(".agents/skills/sample/SKILL.md").path))
    }
    func testSourceNotesRefreshDoesNotDuplicateIdentity() throws {
        _ = try add()
        _ = try lib.importFiles(tree(), fallback: "sample", sources: [Source(location: "test", notes: "New evidence")])
        XCTAssertEqual(lib.catalog.skills[0].sources.count, 1)
        XCTAssertEqual(lib.catalog.skills[0].sources[0].notes, "New evidence")
    }
    func testFileBlockingRequiredDirectoryFailsAtPreview() throws {
        let pin = try add()
        try SafeFiles.write(FileBlob(data: Data("keep me".utf8)), project().appendingPathComponent(".agents"))
        XCTAssertThrowsError(try ProjectPreparer(lib).preview(pins: [pin], root: project()))
        XCTAssertEqual(try String(contentsOf: project().appendingPathComponent(".agents"), encoding: .utf8), "keep me")
    }
}
