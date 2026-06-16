# 4 — GitHub migration

**Lane A (Claude-owned) · run anytime, hands-off, parallel-safe** — but plan before executing (creating issues is outward-facing). git is available (C:\Program Files\Git); a GitHub remote may not be configured — check first.

```
Project: Iosis (tactical RPG, Godot 4.6). Work in C:\Iosis\Godoiosis (a git repo). Read CLAUDE.md (the collaboration contract grants you GitHub issue text) and docs/BACKLOG.md IN FULL — it's the source to migrate, and every open item is already written to be "actionable cold."

Goal: Stand up the repo's Issues / labels / milestones from BACKLOG.md (the dev wants this expedited), keeping docs/design/ as the canonical specs.

Claude-owned scaffolding — BUT creating Issues is outward-facing and hard to undo, so PLAN first, get the user's OK, THEN execute.

Steps:
1. Verify the toolchain and remote: gh auth status; git remote -v. git is installed but gh may not be, and there may be no GitHub remote yet. If gh is missing or there's no remote, STOP and ask how the user wants it set up — don't create a remote or install tooling unilaterally.
2. Propose, and show the user before creating anything:
   - Labels mirroring the backlog scheme: priority (P0-blocking / P1-soon / P2-someday, mapping the 🔴/🟡/🟢 tiers) + type (bug, debt, feature, design, scaffolding).
   - Milestones: P (done), A (artist-attractor demo), B (vertical slice).
   - The issue list mapped from open Bugs/Debt + Features + Design-session + Scaffolding items. Each issue body = the backlog item's text verbatim (already cold-actionable) + its file/line anchors. Link docs/design/*.md as canonical; do NOT duplicate spec content into issues.
3. On confirmation, create labels -> milestones -> issues via gh.
4. Replace the migrated sections of BACKLOG.md with a thin pointer to Issues (keep "Recently completed" as local history unless the user wants it moved). Don't delete BACKLOG.md without explicit OK.

Done when: labels, milestones, and issues mirror the backlog, docs/design/ stays canonical, and BACKLOG.md points to Issues. Note in each design-session issue that the spec lives in docs/design/.
```
