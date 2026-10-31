import SwiftUI
import AppKit
@preconcurrency import SkillCore

@MainActor final class AppModel: ObservableObject {
    @Published var catalog = Catalog()
    @Published var error: String?
    @Published var notice: String?
    @Published var busy = false
    @Published var library: Library?
    @Published var transactions: [SkillCore.Transaction] = []
    init() {
        do {
            let path = ProcessInfo.processInfo.environment["SKILL_LIBRARY_HOME"]
            let root = path.map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Skill Library")
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent("catalog.json").path),
               let seed = Bundle.main.resourceURL?.appendingPathComponent("SeedLibrary"), FileManager.default.fileExists(atPath: seed.path) {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                for item in try FileManager.default.contentsOfDirectory(at: seed, includingPropertiesForKeys: nil) where item.lastPathComponent != ".lock" && item.lastPathComponent != "catalog.json" {
                    let destination = root.appendingPathComponent(item.lastPathComponent)
                    if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                    try FileManager.default.copyItem(at: item, to: destination)
                }
                try Data(contentsOf: seed.appendingPathComponent("catalog.json")).write(to: root.appendingPathComponent("catalog.json"), options: .atomic)
            }
            library = try Library(root: root); refresh()
        } catch { self.error = error.localizedDescription }
    }
    func refresh() { if let library { catalog = library.catalog; transactions = (try? ProjectPreparer(library).journals()) ?? [] } }
    func perform(_ action: () throws -> Void, message: String? = nil) {
        guard !busy else { return }
        do { try action(); refresh(); if let message { notice = message } } catch { self.error = error.localizedDescription; refresh() }
    }
    func scan(_ additional: URL? = nil) {
        guard let library, !busy else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaults = [home.appendingPathComponent(".codex/skills"), home.appendingPathComponent(".agents/skills"), home.appendingPathComponent("Desktop"), home.appendingPathComponent("Documents")].filter { FileManager.default.fileExists(atPath: $0.path) }
        let roots = additional.map { [$0] } ?? Array(Set(defaults + catalog.scanRoots.map { URL(fileURLWithPath: $0) }))
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try library.scan(roots, excluding: [Bundle.main.bundleURL, Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Skill Library Source")]) }
            DispatchQueue.main.async {
                self.busy = false; self.refresh()
                switch result { case .success(let count): self.notice = "Scanned \(count) skill folders. See recovery coverage for skipped or inaccessible locations."
                case .failure(let error): self.error = error.localizedDescription }
            }
        }
    }
    func chooseFolder(title: String, create: Bool = false) -> URL? {
        let panel = NSOpenPanel(); panel.title = title; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.canCreateDirectories = create; panel.prompt = "Choose folder"
        return panel.runModal() == .OK ? panel.url : nil
    }
    func newFolder(title: String) -> URL? {
        let panel = NSSavePanel(); panel.title = title; panel.nameFieldStringValue = "New project"; panel.canCreateDirectories = true; panel.prompt = "Choose location"
        return panel.runModal() == .OK ? panel.url : nil
    }
    func importFolder() {
        guard let folder = chooseFolder(title: "Import a skill or recovery package"), let library else { return }
        perform({
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent("package.json").path) { try library.importRecovery(folder) }
            else { try library.importFolder(folder) }
        }, message: "Imported into your library. Original files are unchanged.")
    }
    func copyRecoveryPrompt() {
        let skillPath = Bundle.main.resourceURL?.appendingPathComponent("RecoverySkill/SKILL.md").path ?? "the app Resources/RecoverySkill/SKILL.md"
        let prompt = "Read and follow the skill-library-recovery skill at \(skillPath) to review my accessible Codex task history and local project instructions. Produce a version-1 recovery package with complete skill folders, evidence notes, and honest coverage, including unavailable devices. Keep recovered workflows as drafts. Save the package to an outputs folder so I can import it into Skill Library. Do not modify existing projects or my library catalog."
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prompt, forType: .string)
        notice = "Recovery prompt copied. Paste it into Codex, then import the resulting package."
        if let skill = Bundle.main.resourceURL?.appendingPathComponent("RecoverySkill") { NSWorkspace.shared.activateFileViewerSelecting([skill]) }
    }
}

@main struct SkillLibraryApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Skill Library", id: "main") {
            ContentView().environmentObject(model).tint(accent).frame(minWidth: 1080, minHeight: 720)
        }.defaultSize(width: 1320, height: 850)
            .commands {
                CommandGroup(replacing: .newItem) { Button("Import skill or recovery package…") { model.importFolder() }.keyboardShortcut("i", modifiers: [.command, .shift]).disabled(model.busy) }
                CommandGroup(replacing: .help) { Button("Skill Library Guide") { if let url = Bundle.main.resourceURL?.appendingPathComponent("Guide.html") { NSWorkspace.shared.open(url) } } }
            }
    }
}
