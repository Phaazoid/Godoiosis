# Zoom animation sheets

Battle-scene spritesheets from **Fire Emblem: The Blazing Blade** (Fire Emblem 7, GBA), used as
**placeholder art** the way `../MapSprites/` already is. Each file here is named after the unit it
pairs with over there, so `ZoomAnimations/Sage.png` is the combat art for `MapSprites/Sage.png`.

Three of the sheets print **"Please give credit if used"**, which is why this file exists rather
than the credit living in a filename:

| File | Ripped by | Source |
|---|---|---|
| `Sage.png` | peebay, for The Spriters Resource | *"credit not necessary, but appreciated"* |
| `Basic_Soldier.png` | Grim — http://unp.cjb.net | Enemy Units - Soldier |
| `Brigand.png` | Bonzai — http://unp.cjb.net | Enemy Units - Brigand |
| `Sniper.png` | Grim — http://unp.cjb.net | Generic Units - Sniper (Female) |

## Three kinds of file live here

- **`Game Boy Advance - ...` are the DOWNLOADS, kept as archive.** Exactly as they arrived, original
  filenames and all. Nothing reads them; they are here so the pipeline can always be re-derived from
  an untouched rip rather than from something already processed.
- **`<Unit>.png` is what the pipeline READS** — named to pair with `../MapSprites/<Unit>.png`, so the
  combat art for a unit is found under the same name as its map art. Verified **pixel-identical** to
  the download it came from (`Sage.png` is byte-identical; the other three are the same pixels in a
  container Godot can actually open — see below).
- **`<Unit>_Frames.png` is GENERATED** by `tools/zoomanim/gen_zoom_animations.gd`. Do not hand-edit
  it; edit the manifest in that tool and re-run. It is one palette block of the source with every
  background keyed to transparent, so a frame's rect is a coordinate you can find on the source
  sheet by eye.

So each unit has a download and a working copy of the same pixels. That duplication is deliberate —
the download is the archive, the short name is the one anything reads.

**A sheet may carry the class more than once.** The Sage sheet has it three times: a **male** block at
the top (its palette strips are named Erk / Pent / Aion) and two **female** blocks below (Sonia /
Limstella, then Nino). `MapSprites/Sage.png` is the female, so the generator's `region` picks a
female block. Which one a unit needs is a **content call** — it is not derivable from the sheet — and
it is made in the manifest, one line.

## The three GIFs needed PNG copies, and that was not cosmetic

**Godot cannot load GIF at all** — `Image.load()` returns error 15, `File unrecognized` — so the
three `.gif` downloads cannot be imported, previewed or read by any tool in the project. That is why
they have PNG working copies rather than just shorter names. Both formats are lossless and the
conversion was verified **zero differing pixels**, with no alpha anywhere in the sources.

The `.gif` files themselves are inert: nothing imports them, and no catalog scans this folder
(`SpawnTool`'s sprite scan is `Art/Units/MapSprites/` only).

## Two kinds of sheet, and only the Sage is READ

The Sage is a **card-format** sheet: every frame sits in a fixed 66x42 rectangle with its duration
printed above it, the animation's name to the left of the row it starts, and a return pointer under
the last row. All of that is extracted automatically.

The other three are older rips with **none** of it, and no tool recovers what is not there:

- **No timing.** The durations simply are not on the sheet.
- **No registration.** A card is a fixed viewport, so where the sprite sits inside it *is* the
  per-frame offset — the animation's own footwork. Those three have no cards, so the best any
  splitter can do is a tight bounding box, which throws that away; played back it jitters instead of
  stepping. Registration buys a second thing besides the footwork: because the idle card holds the
  pose at a known place, the character's **stand point** can be measured off it once and stored with
  the set (#634). A sheet with no cards has nowhere to measure that from either.
- **They also merge.** Connected regions of the Soldier's first attack row come back as one 257px
  blob, its crit row as 377 + 285, because the spear and shield sweeps cross into the neighbouring
  frame.

Dev ruling (2026-08-28): *"All of these are very old uploads, there doesn't exist others as clean as
the sage's."* So no better sources are coming. What the other three
get instead is RECONSTRUCTION rather than reading -- the next section, and the Brigand has it.

## The other three are RECONSTRUCTED, and the Brigand is the first (#603 / #635, 2026-09-05)

`LooseSheet` reads a sheet that has none of the above. It cuts frames out of a band as connected
regions of not-page ink, drops anything too small to be a frame (that is the printed animation name,
which sits inside the band), and **re-cards** what is left: every frame gets one shared card size,
its ink bottom flush with the card's ground line and its ink centred across it. What comes out is
the same uniform artifact a card sheet produces, so everything downstream is unchanged.

**It gives back registration it cannot actually know, and the difference matters when you look at
one.** Vertical is right by construction — the lowest ink *is* the ground, which is why the
Brigand's leap keeps its height off the shadow drawn under it. Horizontal is a guess that drifts:
an axe swung out to one side widens the bounding box that way and walks the body the other. On the
shipped Brigand the worst frame-to-frame shift is about 10 texels, a third of a cell, at the two
frames where the swing arc appears. Two other anchors were measured — the ink centre of the bottom
rows, and of the lower half — and both were worse. Hand-authored per-frame offsets are the only real
cure; that is [#635](https://github.com/Phaazoid/Godoiosis/issues/635)'s own fork 2 and is unpicked.

**Timing is typed into the manifest**, since the sheet prints none: the Brigand's axe attack is 12
frames over 74 GBA frames (~1.23 s), authored to be tuned by eye rather than measured off anything.

`Brigand_Frames.png` is generated like `Sage_Frames.png` and edited the same way — through the
manifest, never by hand — with one difference worth knowing: **a rect in it is NOT a rect on the
source.** Every frame has been moved to sit on its card's ground, so unlike the Sage atlas you
cannot find a frame's coordinates on the original sheet by eye.
