import Foundation
import CryptoKit

public enum SafeFiles {
    public static let fm = FileManager.default
    public static func safeRelative(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") && !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
    }
    public static func target(_ root: URL, _ path: String) throws -> URL {
        guard safeRelative(path) else { throw LibraryError("Unsafe relative path: \(path)") }
        let base = root.standardizedFileURL
        var cursor = base
        // Reject symlinks in every existing ancestor, including the selected root.
        var ancestor = base
        while ancestor.path != "/" {
            if !["/var", "/tmp", "/etc"].contains(ancestor.path), (try? fm.attributesOfItem(atPath: ancestor.path)[.type] as? FileAttributeType) == .typeSymbolicLink { throw LibraryError("Choose a real folder instead of a symbolic link: \(ancestor.path)") }
            ancestor.deleteLastPathComponent()
        }
        for part in path.split(separator: "/") {
            cursor.appendPathComponent(String(part))
            if cursor.path != base.appendingPathComponent(path).path, let attr = try? fm.attributesOfItem(atPath: cursor.path), attr[.type] as? FileAttributeType != .typeDirectory { throw LibraryError("A file or link blocks a required folder: \(cursor.path)") }
            if (try? fm.attributesOfItem(atPath: cursor.path)[.type] as? FileAttributeType) == .typeSymbolicLink { throw LibraryError("Symbolic link blocks this operation: \(cursor.path)") }
        }
        return cursor
    }
    public static func blob(_ url: URL) throws -> FileBlob? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        let attrs = try fm.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular else { throw LibraryError("Expected a regular file: \(url.path)") }
        return FileBlob(data: try Data(contentsOf: url), executable: ((attrs[.posixPermissions] as? Int ?? 0) & 0o111) != 0, permissions: (attrs[.posixPermissions] as? Int ?? 0o644) & 0o777)
    }
    public static func write(_ blob: FileBlob, _ url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try blob.data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: blob.permissions], ofItemAtPath: url.path)
    }
    public static func tree(_ root: URL) throws -> [String: FileBlob] {
        var result: [String: FileBlob] = [:]
        var total = 0
        func visit(_ folder: URL, _ prefix: String, _ visited: Set<String>) throws {
            let actual = folder.resolvingSymlinksInPath().standardizedFileURL
            let base = root.resolvingSymlinksInPath().standardizedFileURL.path
            guard actual.path == base || actual.path.hasPrefix(base + "/") else { throw LibraryError("Supporting files link outside the skill: \(folder.path)") }
            guard !visited.contains(actual.path) else { throw LibraryError("Circular symbolic link: \(folder.path)") }
            var seen = visited; seen.insert(actual.path)
            for item in try fm.contentsOfDirectory(at: actual, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
                if [".git", ".DS_Store"].contains(item.lastPathComponent) { continue }
                let name = prefix + item.lastPathComponent
                let resolved = item.resolvingSymlinksInPath().standardizedFileURL
                guard resolved.path.hasPrefix(base + "/") else { throw LibraryError("Supporting file escapes the skill: \(name)") }
                let attr = try fm.attributesOfItem(atPath: resolved.path)
                if attr[.type] as? FileAttributeType == .typeDirectory {
                    try visit(resolved, name + "/", seen)
                } else if attr[.type] as? FileAttributeType == .typeRegular {
                    let size = attr[.size] as? Int ?? 0
                    total += size
                    guard total < 512 * 1024 * 1024, result.count < 20_000 else { throw LibraryError("This folder exceeds the 512 MB / 20,000 file import limit.") }
                    result[name] = try blob(resolved)
                } else { throw LibraryError("Unsupported supporting file: \(name)") }
            }
        }
        try visit(root, "", [])
        return result
    }
    public static func hash(_ blob: FileBlob) -> String {
        var data = Data("\(blob.permissions)\0".utf8); data.append(blob.data)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public static func hash(_ files: [String: FileBlob]) -> String {
        var digest = SHA256()
        for path in files.keys.sorted() {
            digest.update(data: Data((path + "\0" + hash(files[path]!) + "\n").utf8))
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func saveTree(_ files: [String: FileBlob], _ root: URL) throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for path in files.keys.sorted() { try write(files[path]!, target(root, path)) }
    }
}

public struct SkillMetadata {
    public var name: String
    public var description: String
    public var issues: [String]
    public var dependencies: [String]
}
public enum SkillValidation {
    public static func inspect(_ files: [String: FileBlob], fallback: String) -> SkillMetadata {
        guard let data = files["SKILL.md"]?.data, let text = String(data: data, encoding: .utf8) else {
            return SkillMetadata(name: fallback, description: "Missing or unreadable SKILL.md", issues: ["SKILL.md must be a UTF-8 text file."], dependencies: [])
        }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var issues: [String] = []; var fields: [String: String] = [:]
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            var i = 1
            while i < end {
                let line = lines[i]
                if !line.hasPrefix(" "), !line.hasPrefix("#"), !line.isEmpty {
                    if let colon = line.firstIndex(of: ":") {
                        let key = String(line[..<colon]); var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        if ["name", "description"].contains(key) {
                            if fields[key] != nil { issues.append("Duplicate \(key) in frontmatter.") }
                            if value.hasPrefix(">") || value.hasPrefix("|") {
                                var block: [String] = []; i += 1
                                while i < end, lines[i].hasPrefix(" ") || lines[i].isEmpty { block.append(lines[i].trimmingCharacters(in: .whitespaces)); i += 1 }
                                value = block.joined(separator: value.hasPrefix("|") ? "\n" : " "); i -= 1
                            } else if value.hasPrefix("\"") || value.hasPrefix("'") {
                                if value.count < 2 || value.last != value.first { issues.append("Unclosed quote in \(key).") }
                                else { value = String(value.dropFirst().dropLast()) }
                            } else {
                                value = value.components(separatedBy: " #").first ?? value
                                if value.contains(": ") || value.hasPrefix("[") || value.hasPrefix("{") { issues.append("Use a quoted string or block text for \(key).") }
                            }
                            fields[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } else { issues.append("Malformed frontmatter line: \(line.prefix(80))") }
                }
                i += 1
            }
        } else { issues.append("Add YAML frontmatter enclosed by --- with name and description.") }
        let name = fields["name"] ?? fallback
        if fields["name"] == nil || name.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) == nil || name.count > 64 { issues.append("Name must be 1–64 lowercase letters, digits, and hyphens.") }
        if (fields["description"] ?? "").isEmpty { issues.append("A description is required.") }
        if let regex = try? NSRegularExpression(pattern: #"\]\(([^\s\)]+)(?:\s+[^\)]*)?\)"#) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                var path = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                if path.contains(":") || path.hasPrefix("#") { continue }
                path = path.components(separatedBy: "#")[0].removingPercentEncoding ?? path
                if path.hasPrefix("./") { path = String(path.dropFirst(2)) }
                if !path.isEmpty && files[path] == nil && !files.keys.contains(where: { $0.hasPrefix(path + "/") }) { issues.append("Missing local reference: \(path)") }
            }
        }
        var dependencies: [String] = []
        if let yaml = files["agents/openai.yaml"], let content = String(data: yaml.data, encoding: .utf8) {
            for line in content.components(separatedBy: "\n") {
                let value = line.trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("value:") { dependencies.append(String(value.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))) }
            }
        }
        return SkillMetadata(name: name, description: fields["description"] ?? "Add a description to make this skill discoverable.", issues: Array(Set(issues)).sorted(), dependencies: dependencies)
    }
}

public struct ScanResult { public var folders: [URL] = []; public var coverage: [Coverage] = [] }
public enum SkillScanner {
    public static let excluded: Set<String> = [".git", "node_modules", ".build", "build", "dist", "target", ".next", ".cache", "DerivedData", "vendor", ".venv", "venv", "Pods", "arduino-data", "Library", ".Trash"]
    public static func scan(_ roots: [URL], excluding: [URL] = []) -> ScanResult {
        var result = ScanResult(); var seen: Set<String> = []
        let exclusions = excluding.map { $0.standardizedFileURL.path }
        func visit(_ root: URL, _ failures: inout [String], depth: Int) {
            let path = root.standardizedFileURL.path
            if depth > 40 || exclusions.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) || path.contains("/plugins/cache/") { return }
            guard seen.insert(path).inserted else { return }
            if root.pathExtension == "app" || SafeFiles.fm.fileExists(atPath: root.appendingPathComponent(".skill-library-ignore").path) { return }
            let marker = root.appendingPathComponent("SKILL.md")
            if SafeFiles.fm.fileExists(atPath: marker.path) { result.folders.append(root); return }
            do {
                for item in try SafeFiles.fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) {
                    if excluded.contains(item.lastPathComponent) || item.lastPathComponent == ".system" { continue }
                    let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if values.isSymbolicLink == true {
                        if SafeFiles.fm.fileExists(atPath: item.appendingPathComponent("SKILL.md").path) { result.folders.append(item) }
                    } else if values.isDirectory == true { visit(item, &failures, depth: depth + 1) }
                }
            } catch { failures.append(path + ": " + error.localizedDescription) }
        }
        for root in roots {
            var failures: [String] = []; let before = result.folders.count
            visit(root, &failures, depth: 0)
            result.coverage.append(Coverage(source: root.path, status: failures.isEmpty ? "Scanned" : "Partial", detail: "Found \(result.folders.count - before) skill folders. " + failures.prefix(20).joined(separator: "\n")))
        }
        return result
    }
}
