# Skill Library

A native macOS app for finding, organizing, editing, and reusing Codex skills. Assemble starter kits, preview project changes, and install selected skill revisions into project-local `.agents/skills` folders.

Built with SwiftUI and Apple frameworks. The primary accent is **#3B9EC8**. All library data stays on your Mac; the app requires no AI API account or server.

## Requirements

- macOS 14 or later
- Xcode with Swift 6 or later selected as the active developer toolchain

## Build and run

```sh
./build-app.sh
open "Skill Library.app"
```

The script builds the app and command-line helper, generates the icon, and signs the app for local use. You can also open `Package.swift` in Xcode. Public distribution and notarization are outside this version.

## Use

1. Scan personal skills and project folders, or import a complete skill folder.
2. Review instructions, supporting files, provenance, dependencies, and validation results.
3. Edit a skill to create a library revision without modifying the source project.
4. Create a starter kit with pinned skill revisions and optional starter files.
5. Preview changes for a new or existing project, resolve conflicts, and apply.
6. Check installed revisions or roll back a preparation while preserving subsequent user edits.

The **Recovered drafts** section provides a companion Codex recovery skill. Codex can inspect accessible task history or supplied exports and produce reviewable import packages. See [the recovery skill](RecoverySkill/SKILL.md) and [package format](RecoverySkill/references/package-format.md).

Open [Guide.html](Guide.html) in a browser for the complete usage guide.

## Local data

Library data lives in `~/Library/Application Support/Skill Library`. Set `SKILL_LIBRARY_HOME` to use a separate library for testing. Refresh is manual; imported scripts are never automatically run and project dependencies are never automatically installed.

This repository contains source, tests, and generic recovery tooling. Personal skill collections, recovered task content, generated apps, and local library data are excluded. A source build starts with an empty library.

## Tests

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
swift test --disable-sandbox
```

The flag disables SwiftPM's build sandbox only. Tests cover full-folder imports, validation, duplicates, revision handling, preparation conflicts, interrupted writes, and rollback.

## Source map

| Path | Purpose |
| --- | --- |
| `Sources/SkillCore` | Catalog, scan/import, immutable revisions, validation, project preparation and rollback |
| `Sources/SkillLibrary` | Native SwiftUI interface |
| `Sources/SkillTool` | Command-line adapter for imports and integration checks |
| `Tests/SkillCoreTests` | Filesystem and workflow tests |
| `RecoverySkill` | Portable Codex recovery instructions and package validator |

See [README.txt](README.txt) for storage and validation implementation notes.
