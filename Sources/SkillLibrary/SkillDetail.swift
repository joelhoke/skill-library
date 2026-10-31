import SwiftUI
import SkillCore
import AppKit

struct SkillDetail: View {
    @EnvironmentObject var model: AppModel
    let skill: Skill
    @State private var editPath: String?
    @State private var history = false
    @State private var metadata = false
    @State private var filePaths: [String] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("SKILL DETAILS").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(.secondary); Spacer(); StatusPill(status: skill.status) }
                Text(skill.name).font(.title2.bold()).textSelection(.enabled)
                Text(skill.summary).foregroundStyle(.secondary).textSelection(.enabled)
                HStack { Button("Edit instructions") { editPath = "SKILL.md" }; Button { history = true } label: { Image(systemName: "clock.arrow.circlepath") }.help("Revision history and comparison") }
                if skill.status != .ready && skill.issues.isEmpty {
                    Button("Mark reviewed & ready", systemImage: "checkmark.circle") {
                        guard let lib = model.library else { return }
                        model.perform({ try lib.update(skill.id, category: skill.category, origin: skill.origin, status: .ready, hidden: skill.hidden, dependencies: skill.dependencies) }, message: "\(skill.name) is ready to use in projects.")
                    }.buttonStyle(.borderedProminent)
                    Text("Ready means the structure is valid and you’ve reviewed the instructions. Scripts are never run by this app.").font(.caption).foregroundStyle(.secondary)
                }
                if !skill.issues.isEmpty {
                    VStack(alignment: .leading, spacing: 8) { Text("Needs attention").font(.headline).foregroundStyle(.red); ForEach(skill.issues, id: \.self) { Text($0).font(.caption) } }.padding(12).background(Color.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
                Divider()
                HStack { Text("Organization").font(.headline); Spacer(); Button("Edit") { metadata = true } }
                Text(skill.category + " · " + skill.origin.rawValue).font(.callout)
                Text("Dependencies").font(.headline)
                Text(skill.dependencies.isEmpty ? "No dependencies declared. Review the instructions for runtime requirements." : skill.dependencies.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("Files · \(filePaths.count)").font(.headline)
                ForEach(filePaths, id: \.self) { path in
                    Button { editPath = path } label: { Label(path, systemImage: "doc").font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                }
                Divider()
                Text("Sources").font(.headline)
                ForEach(skill.sources) { source in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(source.location).font(.caption).textSelection(.enabled)
                        if let task = source.taskID { Text("Task: \(task)").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
                        if !source.notes.isEmpty { Text(source.notes).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.bottom, 6)
                }
                Text("\(skill.revisions.count) saved revision\(skill.revisions.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                Button("Export complete skill…") {
                    if let destination = model.newFolder(title: "Export a portable skill package"), let lib = model.library {
                        model.perform({ try lib.export([SkillPin(skillID: skill.id, revisionID: skill.currentRevision)], to: destination) }, message: "Exported complete skill package.")
                    }
                }
            }.padding(24)
        }.background(.background)
        .onAppear { if let lib = model.library { model.perform { filePaths = try lib.files(SkillPin(skillID: skill.id, revisionID: skill.currentRevision)).keys.sorted() } } }
        .sheet(isPresented: Binding(get: { editPath != nil }, set: { if !$0 { editPath = nil } })) { if let path = editPath { FileEditor(skill: skill, path: path).environmentObject(model) } }
        .sheet(isPresented: $history) { HistoryView(skill: skill).environmentObject(model) }
        .sheet(isPresented: $metadata) { MetadataEditor(skill: skill).environmentObject(model) }
    }
}

struct FileEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let skill: Skill; let path: String
    @State private var text = ""
    @State private var initial = ""
    @State private var editable = true
    @State private var localError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { VStack(alignment: .leading) { Text(path).font(.title2.bold()); Text("Saves a new library revision. Original project files stay unchanged.").foregroundStyle(.secondary) }; Spacer() }
            if editable { TextEditor(text: $text).font(.system(size: 13, design: .monospaced)).border(Color.secondary.opacity(0.2)) }
            else { emptyState("Preview in Finder", "This file is binary or too large for the text editor. Export the complete skill to work with its assets.", icon: "doc.richtext") }
            if let localError { Text(localError).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Show saved file") { if let lib = model.library, let folder = try? lib.snapshotURL(skill.id, skill.currentRevision) { NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent(path)]) } }
                Spacer(); Button(text == initial ? "Close" : "Discard changes") { dismiss() }
                if editable { Button("Save revision") {
                    do { try model.library?.edit(skill.id, path: path, text: text); model.refresh(); dismiss() } catch { localError = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(text == initial) }
            }
        }.padding(24).frame(width: 840, height: 630).interactiveDismissDisabled(text != initial)
        .onAppear {
            do {
                if let blob = try model.library?.files(SkillPin(skillID: skill.id, revisionID: skill.currentRevision))[path], blob.data.count < 1_000_000, let content = String(data: blob.data, encoding: .utf8) { text = content; initial = content }
                else { editable = false }
            } catch { localError = error.localizedDescription; editable = false }
        }
    }
}

struct MetadataEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let skill: Skill
    @State private var category = ""
    @State private var origin = Origin.unknown
    @State private var status = SkillStatus.draft
    @State private var hidden = false
    @State private var dependencies = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Organize \(skill.name)").font(.title2.bold())
            Form {
                TextField("Category", text: $category)
                Picker("Origin", selection: $origin) { ForEach(Origin.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Status", selection: $status) { ForEach(SkillStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField("Dependencies (comma separated)", text: $dependencies)
                Toggle("Hide from the default library view", isOn: $hidden)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") {
                do { try model.library?.update(skill.id, category: category, origin: origin, status: status, hidden: hidden, dependencies: dependencies.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }); model.refresh(); dismiss() } catch { self.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent) }
        }.padding(26).frame(width: 570)
        .onAppear { category = skill.category; origin = skill.origin; status = skill.status; hidden = skill.hidden; dependencies = skill.dependencies.joined(separator: ", ") }
    }
}

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let skill: Skill
    @State private var revision = ""
    @State private var comparisonSkillID = ""
    var comparisonSkill: Skill { model.catalog.skills.first { $0.id == comparisonSkillID } ?? skill }
    @State private var oldText = ""
    @State private var currentText = ""
    @State private var changes: [String] = []
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Revision history").font(.title2.bold())
            Picker("Variant", selection: $comparisonSkillID) { ForEach(model.catalog.skills.filter { $0.name == skill.name }) { candidate in Text(candidate.name + " · " + (candidate.sources.first?.location ?? candidate.id)).tag(candidate.id) } }.onChange(of: comparisonSkillID) { _, _ in revision = comparisonSkill.revisions.first?.id ?? ""; load() }
            Picker("Compare with current", selection: $revision) { ForEach(comparisonSkill.revisions.reversed()) { item in Text(item.date.formatted() + " · " + item.note + " · " + item.id.prefix(8)).tag(item.id) } }.onChange(of: revision) { _, _ in load() }
            Text(changes.isEmpty ? "The complete folders match." : changes.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary).lineLimit(5)
            HSplitView { VStack { Text("Selected revision").font(.headline); TextEditor(text: .constant(oldText)).font(.system(size: 12, design: .monospaced)) }; VStack { Text("Current revision").font(.headline); TextEditor(text: .constant(currentText)).font(.system(size: 12, design: .monospaced)) } }
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Text("Restoring keeps all later revisions in history.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Close") { dismiss() }; Button("Restore as new revision") {
                do { try model.library?.restore(skill.id, revision: revision); model.refresh(); dismiss() } catch { self.error = error.localizedDescription }
            }.disabled(revision == skill.currentRevision || comparisonSkillID != skill.id).buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 980, height: 650).onAppear { comparisonSkillID = skill.id; revision = skill.revisions.first?.id ?? skill.currentRevision; load() }
    }
    func load() {
        guard let lib = model.library else { return }
        do {
            let old = try lib.files(SkillPin(skillID: comparisonSkill.id, revisionID: revision)), current = try lib.files(SkillPin(skillID: skill.id, revisionID: skill.currentRevision))
            oldText = String(data: old["SKILL.md"]?.data ?? Data(), encoding: .utf8) ?? ""; currentText = String(data: current["SKILL.md"]?.data ?? Data(), encoding: .utf8) ?? ""
            changes = Set(old.keys).union(current.keys).sorted().filter { old[$0] != current[$0] }.map { path in (old[path] == nil ? "Added: " : current[path] == nil ? "Removed: " : "Changed: ") + path }
        } catch { self.error = error.localizedDescription }
    }
}
