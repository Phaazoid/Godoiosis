# Iosis release notes

One entry per build that went out, newest first. A build is a version `tools/archive-build.ps1` tagged; the version numbers between two entries were merges that never became builds. Builds handed out before v0.188.4 carried no tag and are not recorded here.

The game reads this file (#1075). The lines directly under a release heading are shown to players on the title screen's "What's new" card, so they are written for a player: one plain `- ` bullet per line, no formatting, no issue numbers. Everything from `### Internal` down to the next release is for us and never shown. `tests/core/test_release_notes.gd` lints both rules on every PR that touches this file.

Cutting a release:

1. Open a PR that adds the new entry at the top, headed `## v<version>`, where the version is main's with the last digit plus one. Leave it unlabelled: a `type/feature` label bumps the middle digit instead, and the heading would name a build that never exists.
2. Rewrite the player lines in review, merge it last, then run `tools/archive-build.ps1`. It refuses to build a version this file has no heading for.
3. If something else merged first, the version has moved on and the build refuses. Fix the heading directly on main, since another PR would bump the version again, and run it again.

## v0.192.0 (2026-09-20)

- F3 opens the bug report card from anywhere in the game. It used to do nothing outside development builds.
- There is a report button on screen during battles, so you don't need to know the key or find the pause menu.
- Enemy threat marks start at the enemy's body instead of over its head, curve slightly, and end in a narrow cone instead of an arrowhead.

### Internal

- F3 promoted from a dev key to a player binding (#1050) and the on-screen report mark (#1051), both in PR #1065.
- The threat mark reshaped after the dev's play of #1042's first pass (#1059, PR #1061).

## v0.191.0 (2026-09-20)

- The first-launch card offers to put a name on your bug reports and playtest runs. It is optional, you can change it in Settings, and it doesn't have to be your real name.

### Internal

- Opt-in player name as a PlayerSettings text row, stamped on reports and runs (#1049, PR #1053). The launch notice became versioned, so installs that saw the old card are shown the new one.

## v0.190.2 (2026-09-20)

- Enemy threat marks were redrawn. They pulse from the enemy toward its target, point in a direction, and no longer look like your own aiming lines.
- The title screen tells you when a newer build is out, with a link to download it.

### Internal

- Threat mark direction, motion and vocabulary (#1042, PR #1048). A first-time player on stream read a threat line as another way of aiming a fireball.
- A placed blast spreads outward from where it lands and is stopped by walls and height (#805, PR #1047). No demo content authors a multi-cell placed blast yet, so nothing on these boards changes.
- Builds upload to itch with butler from archive-build.ps1, which then announces the version to the intake Worker's release row that the in-game update check reads (#1060, PRs #1063 and #1064).

## v0.188.8 (2026-09-19)

- Bug reports no longer include your Windows account name.

### Internal

- BugReporter printed its own save path into the engine log, and the next report pasted that log tail back in, so every report after a player's first carried their account name (#1036, PR #1046).

## v0.188.7 (2026-09-18)

- The prologue's enemies are named Thug, and Isaac's rune is named Fire Rune.

### Internal

- Placeholder names Soldier2 and BFire replaced in Prolog.tres.
- Reverted a Project Settings flip ("Use Hidden Project Data Directory") that had committed 953 engine cache files and repointed 385 asset imports (0f5d4e2).

## v0.188.6 (2026-09-18)

- The download is a single file. The game is packed inside Iosis.exe, so it runs with nothing beside it.

### Internal

- binary_format/embed_pck turned on (#1029, PR #1030). v0.188.4 went up on itch as a bare exe without its .pck and could not start.
- The archive step survives a file held by a virus scan or a running copy of the game (#1031, PR #1032). Its first failure is why there is no v0.188.5.

## v0.188.4 (2026-09-18)

- The first demo build, with five missions: Prolog, The Dry Field, The Ford, The Causeway and Terraces.

### Internal

- The first build tagged by archive-build.ps1 (#1027). The Quarry is authored and deliberately held out of the demo.
- Known broken on itch: the upload was the bare exe with no data pack beside it, so it failed at launch with "Couldn't load project data". Fixed in v0.188.6.
