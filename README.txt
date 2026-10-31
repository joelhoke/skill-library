Skill Library — source

Native SwiftUI macOS app (macOS 14+, Apple silicon build).

Build: ./build-app.sh [absolute output app path]
Tests: CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" swift test --disable-sandbox
The sandbox flag affects SwiftPM's build sandbox, not the application or Codex permissions.

Sources/SkillCore: local catalog, immutable folder revisions, validation, scan,
recovery import/export, pinned starter kits, project preview and transaction rollback.
Sources/SkillLibrary: SwiftUI interface. All library mutations are serialized;
scans run on a background queue while the UI and menu mutations are disabled.
Sources/SkillTool: command-line adapter for deterministic import and test fixtures.
Tests/SkillCoreTests: filesystem behavior, validation, conflicts, revisions and rollback.
RecoverySkill: portable Codex workflow and package validator.
Guide.html: user documentation.

Optional SeedLibrary folder is copied into the .app during build; without it,
the app starts empty. The repository excludes personal seed data and recovered personal workflows.
SKILL_LIBRARY_HOME overrides the data folder for isolated UI and integration tests.
Default runtime storage: ~/Library/Application Support/Skill Library.

Catalog schema version 1. Skill IDs and revision IDs are UUID strings. Skill
revisions are immutable snapshots checked against a deterministic SHA-256 of
relative paths, contents, and permissions. Metadata and source notes live in the
catalog. Atomic JSON saves and an exclusive file lock prevent writer collisions.
Transactions persist before changes begin; rollback compares actual file bytes
and permissions against before/after records, including an unmarked write after
an abrupt exit. Project manifests retain the selected revision even when a
conflicting local file is kept, so health reports that deviation.

The native metadata validator supports scalar and folded/literal name/description
frontmatter plus relative Markdown references. It is not a general YAML linter
for arbitrary custom metadata. Dependencies shown in the app are declared
metadata and recovery notes; installing a skill does not install its tools.

Recovery packages use RecoverySkill/references/package-format.md. The importer
never executes scripts, applies embedded instructions, or invokes network tools.
Source instructions are data, not app execution authority.

App builds are ad-hoc signed for local use. Notarization and public distribution
are intentionally outside version 1.
