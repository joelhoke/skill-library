import Foundation
import SkillCore

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count >= 2 else { throw LibraryError("Usage: skilltool <scan|import|recover|list|prepare|health> <library-folder> [paths...]") }
    let lib = try Library(root: URL(fileURLWithPath: args[1]))
    switch args[0] {
    case "scan":
        print("Imported \(try lib.scan(args.dropFirst(2).map { URL(fileURLWithPath: $0) })) skill folders")
    case "import":
        for path in args.dropFirst(2) { print(try lib.importFolder(URL(fileURLWithPath: path))) }
    case "recover":
        guard args.count == 3 else { throw LibraryError("Provide a recovery package folder.") }
        try lib.importRecovery(URL(fileURLWithPath: args[2])); print("Recovery package imported")
    case "list":
        for skill in lib.catalog.skills { print("\(skill.status.rawValue)\t\(skill.name)\t\(skill.sources.count) sources\t\(skill.id)") }
    case "prepare":
        guard args.count >= 4 else { throw LibraryError("Provide destination and exact skill names.") }
        let pins = try args.dropFirst(3).map { name -> SkillPin in
            let matches = lib.catalog.skills.filter { $0.name == name }
            guard matches.count == 1, let skill = matches.first else { throw LibraryError("Missing or ambiguous skill: \(name)") }
            return SkillPin(skillID: skill.id, revisionID: skill.currentRevision)
        }
        let preparer = ProjectPreparer(lib)
        let preview = try preparer.preview(pins: pins, root: URL(fileURLWithPath: args[2]))
        guard !preview.changes.contains(where: { $0.kind == .replace }) else { throw LibraryError("Resolve conflicts in the app.") }
        let result = try preparer.apply(preview, choices: [:]); print("Prepared: \(result.root)")
    case "health":
        guard args.count == 3 else { throw LibraryError("Provide the project folder.") }
        print(try ProjectPreparer(lib).health(URL(fileURLWithPath: args[2])).joined(separator: "\n"))
    default: throw LibraryError("Unknown command.")
    }
} catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
