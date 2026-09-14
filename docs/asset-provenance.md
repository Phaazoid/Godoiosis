# Asset provenance record

**Where every shipped asset came from, and under what terms we ship it.** This is [#139](https://github.com/Phaazoid/Godoiosis/issues/139)'s deliverable, and it is deliberately NOT the credits screen: `Classes/core/Credits.gd` answers *whose name must the build print* (short, player-facing, only what ships); this file answers *where did this file come from and may we ship it* (complete, internal, and it keeps the rows that get no credit because they cannot be licensed at all). `docs/` is in the export's `exclude_filter`, so nothing here reaches a player.

**Record current as of 2026-09-14.** Licence texts that exist nowhere in the repo are transcribed under [`docs/licences/`](licences/). A row's *evidence* column names the thing that would still answer the question a year from now.

**The rule for adding an asset:** nothing enters `Art/` or `Audio/` without a row here. Terms are quoted or a file is dropped in `docs/licences/`; a grant given *on condition* of attribution becomes a `required: true` row in `Credits.gd`, which `tests/law/test_credits_required.gd` then holds to the page.

## Ships -- art

| what ships | origin | terms | credit | evidence |
|---|---|---|---|---|
| `Art/Units/MapSprites/` -- 126 stills | **Zerie**, *Tiny RPG Character Asset Pack 01 V2.0*, zerie.itch.io; purchased by the dev 2026-09-13. Re-canvassed to 64x64 by `tools/sprites/extract_stills.gd` ([#937](https://github.com/Phaazoid/Godoiosis/issues/937), PR #950) | Personal and commercial use; modification allowed; **no redistribution, resale or re-upload**; no AI training or NFT use. *"Credit is appreciated but not required."* | courtesy row | [`docs/licences/Zerie - Tiny RPG Character Asset Pack - terms.md`](licences/Zerie%20-%20Tiny%20RPG%20Character%20Asset%20Pack%20-%20terms.md) (the pack ships no licence file; the page is the terms). The source sheets stay out of the repo because of the redistribution clause -- only the derived stills are committed. |
| `Art/Board/Solaria Demo Tiles.png` -- the 2D board tileset | **Jamie Brownhill**, *World of Solaria* demo pack | Unlimited use in commercial and non-commercial media products (§2a.2); modification allowed (§2b.2); no resale/redistribution/sublicensing, no web3/NFT, no AI/ML (§2b.3-5). **§2b.6 makes credit a condition:** *"grant proper credit to the Licensor where due"*. | **required** row | [`docs/licences/World of Solaria - Asset Licence 2024-02-01.txt`](licences/World%20of%20Solaria%20-%20Asset%20Licence%202024-02-01.txt); current terms at solarialicence.carrd.co |
| `Art/Icons/ElementIcons/` (6), `Art/Icons/WeaponIcons/` (7), `Art/UI/Logo.png` -- 14 files, byte-identical to the 2014-18 GameMaker project's sprites | **Sara Shen** (@stargarnishstudio), drawn for the college-project version of the game; nothing was signed then | Verbal grant relayed by the dev, 2026-09-10: *"fine with us using whatever, and just to include her name and insta link somewhere."* Scope: all art originating in the old project, so it also covers her staged 32x32 unit/board art if that is ever used. **Credit is the condition.** | **required** row (name + @stargarnishstudio) | #139 comments of 2026-09-10 and 2026-09-11; the per-file mapping to `spr_*` names is in the first. `Art/Source/Logo.png` is the same file in a `.gdignore`d folder and does not export. |
| `Art/Icons/BoardIcons/GuardWardIcon.png` | Cut from `ProjectUtumno_full.png` row 38 ([#450](https://github.com/Phaazoid/Godoiosis/issues/450)/[#591](https://github.com/Phaazoid/Godoiosis/issues/591); recorded in `docs/design/standing-reactions.md`). The sheet is part of *Dungeon Crawl 32x32 tiles supplemental* on OpenGameArt (submitter MedicineStorm) | **CC0.** *"No attribution is required. As a courtesy, include a link to the OGA page."* | courtesy row carrying the OGA link | opengameart.org/content/dungeon-crawl-32x32-tiles-supplemental, read 2026-09-14. The source sheet itself left the repo with `Art/Potential Tilesheets/` (PR #916). |
| `Art/Units/Portraits/` (8), `Art/Icons/ActionIcons/` (7), `Art/Icons/ArrowIcons/` (16), `Art/Icons/BoardIcons/` (12 -- all but the ward), `Art/Icons/StateIcons/` (7), `Art/Icons/TerrainIcons/` (11), `Art/LookDev/` (14), `Art/Board/Basic_Hover_Tile.png`, `Basic_Tile_Overlay.png`, `IosisTiles.png`, `select.png` | **Daniel Manzella**, own work in Aseprite (the portrait source is `Art/Source/hair_mcgee.aseprite`); placeholder art, to be replaced by commissioned work | Own work | **none, by his choice** (2026-09-14): *"Don't credit me for individual art."* The Development row already carries the name. | `git log --diff-filter=A` on each folder (all added by him, May-Aug 2026); confirmed in chat 2026-09-14 |

## Ships -- audio

| what ships | origin | terms | credit | evidence |
|---|---|---|---|---|
| `Audio/Music/splendor_of_adventure.mp3`, `battlefield.mp3`, `enemy_approaching.mp3` | **Simeon Anfinrud**, original score written for this game (album "Iosis", 2014-15; ID3-tagged on every file). Two more tracks (*Journey*, *Boss Battle 1*) are staged and unused. | Co-developer's own work for this project; permission confirmed via the dev, 2026-09-14 | Music row, by track title | #139 audio comment 2026-09-10; `C:\Iosis\old-game-sounds\MANIFEST.md`; the ID3 tags themselves |

## Ships -- engine and addons

| what ships | origin | terms | credit | evidence |
|---|---|---|---|---|
| Godot Engine 4.7.1 | godotengine.org | MIT; the engine's own and third-party notices are embedded in the binary (`Engine.get_license_info()`) | Built-with row | the binary |
| `addons/dialogic/` (2.0-Alpha-20), vendored at [#182](https://github.com/Phaazoid/Godoiosis/issues/182) | dialogic-godot/dialogic | **MIT** -- and the vendored copy carried **no `LICENSE` file** until this record restored `addons/dialogic/LICENSE` from upstream (MIT asks that the notice travel with copies). | Built-with row | `addons/dialogic/LICENSE` |
| `addons/dialogic/Example Assets/` that reach the pack: `backgrounds/`, `next-indicator/`, `bbcode_transitions/`, the two `.gd` | Dialogic's own | MIT, as above | -- | `exclude_filter` in `export_presets.cfg` (the `Fonts/` folder is excluded since PR #916; `portraits/` is skipped by Dialogic's export plugin) |
| `addons/dialogic/Example Assets/sound-effects/typing1-5.wav` | **Tim Krief** | **CC BY-SA 4.0** (`LICENSE.txt` beside them). They are held as `ext_resource` by the default VN-choices layer, which loads with every dialogue -- so they **ship** even though no Iosis timeline has a choice event and they never **play**. Excluding them from the pack was ruled out: a dangling `ext_resource` is a hard parse error in every conversation of the exported build. ShareAlike does not reach a game that includes an unmodified clip; attribution is the whole obligation. | **required** row | the layer's `.tscn`; `tests/export/test_export_smoke.gd` would catch the exclusion route breaking |
| Fonts | none ship -- `Resources/UiTheme.tres` sets no font, so the game runs on the engine's built-in face | covered by the engine's bundled notices | -- | PR #916 |
| `addons/gdUnit4/`, `addons/AsepriteWizard/` | vendored tooling | each carries its LICENSE in-tree | -- | both in `exclude_filter`; **not in the build** |

## Held, not shipped

Staged outside the repo, kept because the record's job is to answer "where did this come from" later:

| what | where | why it is out |
|---|---|---|
| Sara Shen's 32x32 unit and board sprites | `C:\Iosis\old-game-sprites\` | reference material for the art pass; never imported. Covered by her grant if used. |
| The old game's unused audio: *Journey*, *Boss Battle 1*; `snd_attack_block`, `_earth`, `_miss` | `C:\Iosis\old-game-sounds\` (+ `MANIFEST.md`) | never imported |
| **The seven attack clips that shipped until 2026-09-14** -- `air`, `chainsword`, `drill`, `fire`, `impact`, `springspear`, `water` | `C:\Iosis\old-game-sounds\sfx\` (originals, bytes untouched) | Ruled out of the demo build by the dev, on feel (*"bad sound reads as more broken than no sound"*) and on provenance. `fire` is *Large Fireball*, Mike Koenig, SoundBible, CC BY 3.0 -- a credit condition, moot while it does not ship; `impact` and `chainsword` are SoundBible-tagged but unidentifiable; the other four are untraceable down to the GMS1.4 definitions at `c3potheds/iosis@43429d5e`. `AudioDirector.IMPACT` is unassigned on purpose and the rule around it stays; a licensed clip needs a row here before it goes in. |
| Candidate tilesheets -- Solaria, ProjectUtumno, Textures-16, *Big 32x32 Tileset* (PxlDev / Team Melon, own licence: free for personal and commercial use, credit if commercial) | `C:\Iosis\potential-tilesheets\` | 1764 files that nothing referenced and that were shipping anyway; moved out in PR #916 |
| Zerie's source sheets (the 100x100 animation strips) | the dev's purchase folder | the pack's no-redistribution clause; only derived stills are committed |

## Deleted -- unlicensable

| what | why | when |
|---|---|---|
| `Art/Units/MapSprites/` before #937 -- Fire Emblem GBA map sprites | ripped; cannot be licensed at any price | deleted PR #950, 2026-09-13; replaced by Zerie's pack |
| `Art/Units/ZoomAnimations/` -- four *Fire Emblem: The Blazing Blade* battle sheets and three raw downloads | same | deleted PR #951, 2026-09-14; no replacement -- the battle zoom has no art until [#603](https://github.com/Phaazoid/Godoiosis/issues/603) resumes with [#635](https://github.com/Phaazoid/Godoiosis/issues/635)'s tool |

These are kept off the credits page on purpose (see `Credits.gd`'s header): crediting an asset that cannot be licensed does not license it.
