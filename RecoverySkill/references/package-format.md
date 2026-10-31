# Skill Library recovery package, version 1

An ordinary folder contains `package.json` and one or more complete skill directories. Import the folder using the app. No ZIP extraction or remote fetch is performed by the app.

```json
{
  "schemaVersion": 1,
  "packageID": "recovery-2026-10-31-local",
  "skills": [
    {
      "folder": "skills/example-workflow",
      "category": "Writing",
      "origin": "Personal",
      "dependencies": ["A current approved source document"],
      "sources": [
        {
          "location": "Exact task title or original file path",
          "taskID": "actual-task-id-when-known",
          "notes": "Specific instructions inspected; what remains unverified."
        }
      ]
    }
  ],
  "coverage": [
    {
      "source": "Local task history",
      "status": "Partial",
      "detail": "Reviewed the named task and its supplied brief; other turns remain unreviewed."
    }
  ]
}
```

All fields above are required except `taskID`, which may be omitted. `origin` is exactly one of `Personal`, `Project-specific`, `Third-party`, `Unknown`. Personal means the workflow is intended for this user's use; it does not prove authorship. Categories and coverage statuses are plain strings. Folder paths are relative to the package, contain no `..`, and cannot escape through symlinks. Each folder must contain UTF-8 `SKILL.md` with frontmatter `name` and `description`. Include actual supporting resources and use relative links to them. The importer always marks recovered skills as Draft, or Needs repair when validation fails. It will not accept a package instruction to mark them Ready.

Include a source entry for every recovered skill. An evidence note should distinguish actual user requirements from inferred generalization, completed behavior from plans, and inspected materials from unavailable context. Preserve notes about conflicts. Do not embed full conversation dumps unless specifically needed and requested.

Package IDs identify collection runs. Folder-content hashes deduplicate skill versions; matching coverage entries do not multiply on reimport. A changed folder creates a distinct recovered variant for comparison. Exported skills also use this format and require review when imported into a new library.

The scanner excludes dependencies, build outputs, app bundles, plugin caches, and folders containing `.skill-library-ignore`. To inspect an intentionally excluded skill, import its exact folder directly.
