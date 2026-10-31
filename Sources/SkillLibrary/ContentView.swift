import SwiftUI
import SkillCore
import AppKit

// Primary accent: #3B9EC8
let accent = Color(red: 59.0 / 255.0, green: 158.0 / 255.0, blue: 200.0 / 255.0)
enum Section: String, CaseIterable, Identifiable {
    case library = "Library", drafts = "Recovered drafts", kits = "Starter kits", projects = "Projects"
    var id: String { rawValue }
    var icon: String { switch self { case .library: "square.grid.2x2"; case .drafts: "tray.and.arrow.down"; case .kits: "shippingbox"; case .projects: "folder" } }
}
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var section: Section = .library
    @State private var query = ""
    @State private var category = "All categories"
    @State private var selected: String?
    @State private var showHidden = false
    @State private var prepare = false
    @State private var kitEditor = false
    @State private var editingKit: StarterKit?
    @State private var coverage = false
    var filtered: [Skill] {
        model.catalog.skills.filter {
            (showHidden || !$0.hidden) && (section != .drafts || $0.isRecovered && $0.status != .ready)
            && (category == "All categories" || $0.category == category)
            && (query.isEmpty || ([$0.name, $0.summary, $0.category, $0.origin.rawValue, $0.status.rawValue] + $0.sources.map(\.location) + $0.dependencies).joined(separator: " ").localizedCaseInsensitiveContains(query))
        }.sorted { $0.name < $1.name }
    }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image(systemName: "books.vertical.fill").font(.system(size: 27)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 3) { Text("Skill Library").font(.title3.bold()); Text("YOUR REUSABLE WORK").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(.secondary) }
                }.padding(.horizontal, 18).padding(.top, 24)
                List(Section.allCases, selection: $section) { item in
                    Label(item.rawValue, systemImage: item.icon).padding(.vertical, 7).tag(item)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 12) {
                    Text("ON THIS MAC").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Label("Private, local library", systemImage: "internaldrive").font(.caption)
                    Button("Show library folder") { if let url = model.library?.root { NSWorkspace.shared.open(url) } }.buttonStyle(.link)
                    Button("View scan & recovery coverage") { coverage = true }.buttonStyle(.link)
                }.padding(18)
            }.navigationSplitViewColumnWidth(min: 215, ideal: 235, max: 260)
        } detail: {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.rawValue).font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text(subtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if section == .drafts {
                        Button { model.copyRecoveryPrompt() } label: { Label("Recover with Codex", systemImage: "sparkles") }
                    }
                    Button { prepare = true } label: { Label("Prepare project", systemImage: "folder.badge.plus") }.buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
                }.padding(26)
                if let notice = model.notice {
                    HStack { Image(systemName: "checkmark.circle").foregroundStyle(accent); Text(notice).font(.callout); Spacer(); Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }.padding(12).background(accent.opacity(0.08)).padding(.horizontal, 26).padding(.bottom, 12)
                }
                if section == .library || section == .drafts {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search skills, sources, or dependencies", text: $query).textFieldStyle(.plain)
                        Picker("Category", selection: $category) { Text("All categories").tag("All categories"); ForEach(Array(Set(model.catalog.skills.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 170)
                        Toggle("Hidden", isOn: $showHidden).toggleStyle(.checkbox)
                        Menu { Button("Scan default folders") { model.scan() }; Button("Scan another folder…") { if let folder = model.chooseFolder(title: "Scan for skills") { model.scan(folder) } }; Button("Import skill or recovery package…") { model.importFolder() } } label: { Label("Add skills", systemImage: "plus") }
                    }.padding(14).background(.background).clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 26)
                    HSplitView {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack { metric("SKILLS", "\(filtered.count)"); metric("READY", "\(filtered.filter { $0.status == .ready }.count)"); metric("TO REVIEW", "\(filtered.filter { $0.status != .ready }.count)") }.padding(.vertical, 10)
                                if filtered.isEmpty { emptyState("No skills here yet", "Import a skill folder, scan your projects, or recover workflows with Codex.", icon: "books.vertical") }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                                    ForEach(filtered) { skill in
                                        Button { selected = skill.id } label: { SkillCard(skill: skill, selected: selected == skill.id) }.buttonStyle(.plain)
                                    }
                                }
                            }.padding(24)
                        }.frame(minWidth: 350)
                        if let id = selected, let skill = model.catalog.skills.first(where: { $0.id == id }) {
                            SkillDetail(skill: skill).id(skill.id + skill.currentRevision + skill.status.rawValue).frame(minWidth: 310, idealWidth: 350, maxWidth: 420)
                        }
                    }.padding(.top, 10)
                } else if section == .kits { kitsView } else { projectsView }
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(accent)
        .disabled(model.busy || model.library == nil)
        .overlay { if model.busy { VStack(spacing: 14) { ProgressView(); Text("Finding and importing skills…").font(.headline); Text("Your original folders stay in place.").foregroundStyle(.secondary) }.padding(36).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
        .alert("Couldn’t complete that action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .sheet(isPresented: $prepare) { PrepareView().environmentObject(model) }
        .sheet(isPresented: $kitEditor, onDismiss: { editingKit = nil }) { KitEditor(kit: editingKit).environmentObject(model) }
        .sheet(isPresented: $coverage) { CoverageView().environmentObject(model) }
    }
    var subtitle: String {
        switch section {
        case .library: "Find what you’ve built. Bring it to what’s next."
        case .drafts: "Workflows recovered from your projects, ready for your review."
        case .kits: "The right skills and starter files, together in one kit."
        case .projects: "See what’s installed, check for changes, and undo preparation."
        }
    }
    func metric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) { Text(value).font(.title2.weight(.medium)); Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    var kitsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Pin a skill revision so your next project starts consistently.").foregroundStyle(.secondary); Spacer(); Button("New starter kit", systemImage: "plus") { editingKit = nil; kitEditor = true } }
                if model.catalog.kits.isEmpty { emptyState("Your next project starts here", "Build a kit from reviewed skills. Add optional starter files for documents, code, or other work.", icon: "shippingbox") }
                ForEach(model.catalog.kits) { kit in
                    HStack(alignment: .top, spacing: 18) {
                        Image(systemName: "shippingbox.fill").font(.title).foregroundStyle(accent).frame(width: 46, height: 46).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(kit.name).font(.title3.bold())
                            Text("\(kit.skills.count) pinned skills" + (kit.templateFolder != nil ? " · Includes starter files" : "")).foregroundStyle(.secondary)
                            Text(kit.skills.compactMap { pin in model.catalog.skills.first(where: { $0.id == pin.skillID })?.name }.joined(separator: " · ")).font(.caption)
                        }
                        Spacer(); Button("Edit") { editingKit = kit; kitEditor = true }
                    }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(26)
        }
    }
    var projectsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.transactions.isEmpty { emptyState("No prepared projects yet", "Choose skills or a starter kit, then preview every file before applying.", icon: "folder.badge.plus") }
                ForEach(model.transactions) { transaction in ProjectCard(transaction: transaction).environmentObject(model) }
            }.padding(26)
        }
    }
}

struct SkillCard: View {
    let skill: Skill; let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Image(systemName: skill.isRecovered ? "sparkles" : "doc.text").foregroundStyle(accent); Spacer(); StatusPill(status: skill.status) }
            Text(skill.name).font(.system(size: 16, weight: .semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Text(skill.summary).font(.callout).foregroundStyle(.secondary).lineLimit(3).frame(height: 52, alignment: .topLeading)
            Divider()
            HStack { Text(skill.category).font(.caption.weight(.medium)); Spacer(); Text("\(skill.sources.count) source\(skill.sources.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary) }
            Text(skill.origin.rawValue + (skill.hidden ? " · Hidden" : "")).font(.caption2).foregroundStyle(.secondary)
        }.padding(17).background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? accent : Color.primary.opacity(0.07), lineWidth: selected ? 2 : 1))
    }
}
struct StatusPill: View {
    let status: SkillStatus
    var color: Color { status == .ready ? accent : (status == .draft ? .orange : .red) }
    var body: some View { Text(status.rawValue).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(color).background(color.opacity(0.1), in: Capsule()) }
}
func emptyState(_ title: String, _ subtitle: String, icon: String) -> some View {
    VStack(spacing: 16) { Image(systemName: icon).font(.system(size: 42, weight: .light)).foregroundStyle(accent); Text(title).font(.title2.weight(.medium)); Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430) }.frame(maxWidth: .infinity).padding(50)
}

struct ProjectCard: View {
    @EnvironmentObject var model: AppModel
    let transaction: SkillCore.Transaction
    @State private var health: [String] = []
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: "folder.fill").foregroundStyle(accent); Text(URL(fileURLWithPath: transaction.root).lastPathComponent).font(.title3.bold()); Spacer(); Text(transaction.state).font(.caption).foregroundStyle(.secondary) }
            Text(transaction.root).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("\(transaction.date.formatted()) · \(transaction.entries.filter { $0.path != ".skill-library.json" }.count) changed files").font(.caption)
            ForEach(health, id: \.self) { Text($0).font(.callout) }
            HStack {
                Button("Show folder") { NSWorkspace.shared.open(URL(fileURLWithPath: transaction.root)) }
                Button("Check installed skills") { if let library = model.library { model.perform { health = try ProjectPreparer(library).health(URL(fileURLWithPath: transaction.root)) } } }
                Spacer()
                if transaction.state != "Rolled back" { Button("Roll back…") { confirm = true } }
            }
        }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 14))
        .confirmationDialog("Undo this preparation? Files edited since preparation will be preserved.", isPresented: $confirm) {
            Button("Roll back preparation") {
                if let library = model.library { model.perform {
                    let preserved = try ProjectPreparer(library).rollback(transaction.id)
                    model.notice = preserved.isEmpty ? "Preparation rolled back." : "Rollback preserved later edits: " + preserved.joined(separator: ", ")
                    health = []
                } }
            }
        }
    }
}

struct CoverageView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Scan & recovery coverage").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Text("This is an inventory of what was checked, not a claim that every past task has been recovered.").foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(model.catalog.coverage.reversed()) { item in
                        VStack(alignment: .leading, spacing: 5) { HStack { Text(item.source).font(.headline); Spacer(); Text(item.status).font(.caption).foregroundStyle(accent) }; Text(item.detail).font(.callout).textSelection(.enabled); Text(item.date.formatted()).font(.caption2).foregroundStyle(.secondary) }; Divider()
                    }
                }
            }
        }.padding(26).frame(width: 760, height: 570)
    }
}
