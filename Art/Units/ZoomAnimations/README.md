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

## Sources vs generated

- **`<Unit>.png` is a SOURCE sheet** — the rip, untouched, and the authority.
- **`<Unit>_Frames.png` is GENERATED** by `tools/zoomanim/gen_zoom_animations.gd`. Do not hand-edit
  it; edit the manifest in that tool and re-run. It is one palette block of the source with every
  background keyed to transparent, so a frame's rect is a coordinate you can find on the source
  sheet by eye.

## The three GIFs became PNGs, and that was not cosmetic

**Godot cannot load GIF at all** — `Image.load()` returns error 15, `File unrecognized` — so the
originals could not be imported, previewed or read by any tool in the project. They were converted
to PNG (both formats are lossless; verified **zero differing pixels** and no alpha in any source),
and the `.gif` originals dropped rather than committed, since a file the engine cannot open has no
business in `Art/`.

## Only the Sage is machine-readable, and this is why

The Sage is a **card-format** sheet: every frame sits in a fixed 66x42 rectangle with its duration
printed above it, the animation's name to the left of the row it starts, and a return pointer under
the last row. All of that is extracted automatically.

The other three are older rips with **none** of it, and no tool recovers what is not there:

- **No timing.** The durations simply are not on the sheet.
- **No registration.** A card is a fixed viewport, so where the sprite sits inside it *is* the
  per-frame offset — the animation's own footwork. Those three have no cards, so the best any
  splitter can do is a tight bounding box, which throws that away; played back it jitters instead of
  stepping.
- **They also merge.** Connected regions of the Soldier's first attack row come back as one 257px
  blob, its crit row as 377 + 285, because the spear and shield sweeps cross into the neighbouring
  frame.

Dev ruling (2026-08-28): *"All of these are very old uploads, there doesn't exist others as clean as
the sage's."* So the three are kept for reference and for whatever hand-assisted path #629's
follow-up settles on; the automatic pipeline is the Sage's alone for now.
