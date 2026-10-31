import SwiftUI
import SkillCore

struct SkillSelection: View {
    @EnvironmentObject var model: AppModel
    @Binding var selected: Set<String>
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(model.catalog.skills.filter { !$0.hidden }.sorted { $0.name < $1.name }) { skill in
                    HStack {
                        Toggle(isOn: Binding(get: { selected.contains(skill.id) }, set: { if $0 { selected.insert(skill.id) } else { selected.remove(skill.id) } })) {
                            VStack(alignment: .leading, spacing: 3) { Text(skill.name).font(.headline); Text(skill.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }.toggleStyle(.checkbox).disabled(skill.status != .ready)
                        Spacer(); StatusPill(status: skill.status)
                    }.padding(10).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

struct KitEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let kit: StarterKit?
    @State private var name = ""
    @State private var selected: Set<String> = []
    @State private var template: URL?
    @State private var keepTemplate = true
    @State private var latest = false
    @State private var error: String?
    @State private var deleteConfirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kit == nil ? "New starter kit" : "Edit starter kit").font(.title2.bold())
            TextField("Kit name", text: $name).textFieldStyle(.roundedBorder)
            Text("Choose reviewed skills. Each kit saves a specific revision.").foregroundStyle(.secondary)
            SkillSelection(selected: $selected)
            if kit != nil { Toggle("Update selected skills to their latest library revisions", isOn: $latest) }
            HStack {
                Button("Choose starter files folder…") { template = model.chooseFolder(title: "Choose files to include in the project root") }
                Text(template?.lastPathComponent ?? (kit?.templateFolder != nil && keepTemplate ? "Existing starter files included" : "No starter files")).font(.caption).foregroundStyle(.secondary)
                if template != nil || kit?.templateFolder != nil && keepTemplate { Button("Remove") { template = nil; keepTemplate = false } }
            }
            Text("Starter files are copied to the project root. Include only files you intend to reuse.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                if kit != nil { Button("Delete kit…", role: .destructive) { deleteConfirmation = true } }
                Spacer(); Button("Cancel") { dismiss() }; Button("Save kit") { save() }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 720, height: 650)
        .onAppear { name = kit?.name ?? ""; selected = Set(kit?.skills.map(\.skillID) ?? []) }
        .confirmationDialog("Delete this starter kit? Library skills remain available.", isPresented: $deleteConfirmation) {
            Button("Delete kit", role: .destructive) { if let id = kit?.id { model.perform { try model.library?.deleteKit(id) }; dismiss() } }
        }
    }
    func save() {
        guard let lib = model.library else { return }
        do {
            let pins = model.catalog.skills.filter { selected.contains($0.id) }.map { skill in
                if !latest, let pinned = kit?.skills.first(where: { $0.skillID == skill.id }) { return pinned }
                return SkillPin(skillID: skill.id, revisionID: skill.currentRevision)
            }
            _ = try lib.saveKit(id: kit?.id, name: name, pins: pins, template: template, keepTemplate: keepTemplate)
            model.refresh(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct PrepareView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var selected: Set<String> = []
    @State private var kitID = "custom"
    @State private var destination: URL?
    @State private var preview: Preparation?
    @State private var choices: [String: ConflictChoice] = [:]
    @State private var error: String?
    @State private var complete: SkillCore.Transaction?
    var kit: StarterKit? { model.catalog.kits.first { $0.id == kitID } }
    var unresolved: Int { preview?.changes.filter { $0.kind == .replace && choices[$0.path] == nil }.count ?? 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { VStack(alignment: .leading, spacing: 6) { Text(complete == nil ? "Prepare a project" : "Your project is ready").font(.title2.bold()); Text(complete == nil ? (preview == nil ? "Choose skills and a destination, then review the changes." : "Review files and resolve conflicts before applying.") : "Skills are saved alongside the project for Codex to discover.").foregroundStyle(.secondary) }; Spacer() }
            if let complete {
                Spacer()
                Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(accent).frame(maxWidth: .infinity)
                Text(complete.root).textSelection(.enabled).frame(maxWidth: .infinity)
                Text("\(complete.entries.filter { $0.path != ".skill-library.json" }.count) files changed. Open a new Codex task in this folder to use its skills.").multilineTextAlignment(.center).frame(maxWidth: .infinity)
                Text("You can check for local edits or roll back this preparation in Projects.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
                HStack { Button("Show project") { NSWorkspace.shared.open(URL(fileURLWithPath: complete.root)) }; Spacer(); Button("Done") { dismiss() }.buttonStyle(.borderedProminent) }
            } else if let preview {
                Text(preview.root.path).font(.caption).textSelection(.enabled)
                HStack(spacing: 24) {
                    Text("\(preview.changes.filter { $0.kind == .add }.count) new")
                    Text("\(preview.changes.filter { $0.kind == .replace }.count) conflicts").foregroundStyle(.orange)
                    Text("\(preview.changes.filter { $0.kind == .unchanged }.count) unchanged").foregroundStyle(.secondary)
                }.font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(preview.changes) { change in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(change.path).font(.system(size: 12, design: .monospaced)); Spacer(); Text(change.kind.rawValue).font(.caption).foregroundStyle(change.kind == .replace ? .orange : .secondary) }
                                if change.kind == .replace {
                                    Picker("Resolve", selection: Binding(get: { choices[change.path]?.rawValue ?? "Choose…" }, set: { choices[change.path] = ConflictChoice(rawValue: $0) })) {
                                        Text("Choose…").tag("Choose…"); ForEach(ConflictChoice.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                                    }.pickerStyle(.segmented)
                                    DisclosureGroup("Compare content") {
                                        HStack(alignment: .top) { comparison(change.before?.data, title: "Existing"); comparison(change.after.data, title: "Selected") }
                                    }.font(.caption)
                                }
                            }.padding(12).background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                Text("The app also records installed revisions in .skill-library.json. Extra files already in the project remain in place.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Back") { self.preview = nil; choices = [:]; error = nil }; Spacer()
                    Button(unresolved > 0 ? "Resolve \(unresolved) conflicts" : "Apply changes") { apply(preview) }.buttonStyle(.borderedProminent).disabled(unresolved > 0)
                    Button("Cancel") { dismiss() }
                }
            } else {
                Picker("Start with", selection: $kitID) { Text("Individual skills").tag("custom"); ForEach(model.catalog.kits) { Text($0.name).tag($0.id) } }
                if let kit {
                    Text("\(kit.skills.count) pinned skills" + (kit.templateFolder != nil ? " and starter files" : "")).font(.headline)
                    ScrollView { VStack(alignment: .leading, spacing: 12) { ForEach(kit.skills) { pin in if let skill = model.catalog.skills.first(where: { $0.id == pin.skillID }) { HStack { Text(skill.name); Spacer(); StatusPill(status: skill.status); Text(String(pin.revisionID.prefix(8))).font(.caption.monospaced()).foregroundStyle(.secondary) } } } } }
                } else { SkillSelection(selected: $selected) }
                HStack { Button("Choose existing folder…") { destination = model.chooseFolder(title: "Choose project folder", create: true) }; Button("New project folder…") { destination = model.newFolder(title: "Create a project folder") } }
                Text(destination?.path ?? "No folder selected").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                HStack { Text("Drafts must be reviewed before use.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Cancel") { dismiss() }; Button("Preview changes") { makePreview() }.buttonStyle(.borderedProminent).disabled(destination == nil || kit == nil && selected.isEmpty) }
            }
        }.padding(26).frame(width: 850, height: 690).interactiveDismissDisabled(preview != nil)
    }
    func comparison(_ data: Data?, title: String) -> some View {
        VStack(alignment: .leading) { Text(title).bold(); Text(data.flatMap { String(data: $0, encoding: .utf8) }.map { String($0.prefix(8000)) } ?? "Binary file").font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
    func makePreview() {
        guard let lib = model.library, let destination else { return }
        do {
            let pins = kit?.skills ?? model.catalog.skills.filter { selected.contains($0.id) }.map { SkillPin(skillID: $0.id, revisionID: $0.currentRevision) }
            preview = try ProjectPreparer(lib).preview(pins: pins, root: destination, templateFolder: kit?.templateFolder); choices = [:]; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func apply(_ preview: Preparation) {
        guard let lib = model.library else { return }
        do { complete = try ProjectPreparer(lib).apply(preview, choices: choices); model.refresh(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
