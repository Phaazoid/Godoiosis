# Presentation & effects — the HD-2D idea wall

**Status: an idea wall plus two locked decisions.** Solicited by the dev on 2026-08-12, the day Stage 0 (#203) passed its GO gate: *"a full thought experiment, all ideas on the wall."* Nothing below the Decisions section is a commitment — it is the candidate pool for #176's stage 5 and beyond, kept so it can't evaporate from chat. The look-dev scene (`Scenes/LookDev/LookDev.tscn`) is the standing playground where any of it gets prototyped before it's real — and since #212 (2026-08-15) the **Moods tab** in the dev-tools window tunes the *shipping* view live, so a value on this wall can be judged on a real board rather than in the diorama. **It is a playground, not a scratch scene ([#393](https://github.com/Phaazoid/Godoiosis/issues/393), 2026-08-19)** — five presentation suites fixture on it, `Battle3D.tscn` loads its MeshLibrary, and `BoardMirror`/`BoardOverlays` read textures out of `Art/LookDev/`, so it is edited with the same care as shipping code. Its four moods stopped being a second copy at the same time: `look_dev.gd` held them as a hardcoded `PRESETS` table, seeded from the same values four of the twelve `LookPreset` files now carry, and it resolves them by NAME through `LookKnobs` instead.

**Canon checked through #579 (2026-08-27).**

---

## Where a presentation value is authored (#272, #373; one-tab-per-row since #380, 2026-08-19)

A tuned value has **three** possible homes, and picking the wrong one is how a value ends up with
nowhere to live. The question to ask is *who is allowed to disagree about this?*

| home | who may differ | surface | stored in |
|---|---|---|---|
| **mission mood** | one board vs another | Moods tab | a `LookPreset` a `ScenarioData` names (#253), or the DEFAULT every board with no named mood wears (#386) |
| **game constant** | nobody, ever | Game tab → *Save to source* | the declaration that authors it — an `@export` default, a `static var`, or one entry of `BoardOverlays.LAYERS` |
| **per object type** | one tile type vs another | Objects tab → *Save object fields* | a TileSet custom-data column |

The middle row is the one that was missing until #272, and its absence is what both tickets were
actually about: prop geometry and the whole fire block are world construction rather than mood, so a
preset was never the right store for them — they are the same in every mission forever. #373 found
the same hole one shelf along and closed it the same way, for everything that had been excluded from
presets by name: board markup and its colours, the unit readout, camera *handling*, the brush ghost.
Each population left `LookKnobs.KNOBS` entirely rather than being filtered out of presets, which is
what makes "a mission cannot restyle the game" structural instead of a list someone maintains — and
with the last of it gone, `PRESET_EXCLUDED` had nothing left to name and was deleted. The look table
is now scene mood entire, so a knob added to it joins presets automatically and correctly.

The middle row briefly read "Game tab *or* Objects tab" while the Objects tab still held the
world-construction globals; #380 moved those (and the fire block, and the four lamp defaults —
which had NO surface anywhere) into the Game tab, so each row is one tab again. The Objects tab is
purely per-type now: which object glows, how tall THIS one stands. The lamp defaults also gained
the setter-plus-sweep the geometry globals already had, so tuning one re-lights every standing lamp
instead of waiting for a repaint (#264's born-dead slider, closed for lights).

**Every save that can overwrite asks first (#380's convention, dev: "anything that can overwrite
settings should").** Every tool's Update — load-gated *and* confirmed — plus the Game tab's source
save, the Objects tab's tileset save, and the Moods tab's *Update default* (#386, confirmed but not
load-gated: there is one default and it is always the target, so what the ask guards is "not yet"
rather than "the wrong file"); `DevWidgets.confirm_overwrite` is the shared wording. Save
As is the one save that never confirms, because `refuse_existing_file` makes it structurally unable to
overwrite anything.

**And every save says whether there is anything to do** (#389): a panel holding unsaved changes
wears `Save *`, via `DevWidgets.mark_unsaved`. It never disables — Save As is legitimate on a clean
panel, and a greyed Save would bury the precise "nothing has moved" its handler already reports.
The three knob panels answer `has_unsaved_changes()` differently (Moods and Game diff a baseline,
Objects has none since its edits land in the live TileSet), which is why they shipped as one
ticket rather than three improvisations.

**And a knob page must not dictate the window's WIDTH** ([#403](https://github.com/Phaazoid/Godoiosis/issues/403),
2026-08-21). `DevWidgets.add_knob_scroll` is the one answer to how a knob page scrolls — the
ScrollContainer plus the row VBox inside it, which Moods, Game and Objects each built identically.
Its horizontal axis is `SCROLL_MODE_AUTO`, and that is the fix rather than the tidy-up: **a
ScrollContainer with an axis DISABLED declares its content's full width as its own MINIMUM**, so a
panel pushed its widest row all the way up to the window. An `add_color` row is 841px — label 190,
swatch, and four 0-255 slider/SpinBox pairs whose SpinBoxes measure **87 each however small a
minimum they are asked for** — against the 678 a 900-wide window left a page, so the six colour
sub-tabs ran off the right edge while every other page fitted. Scrolling costs nothing at the
default size (the rows still EXPAND to fill a window with room) and degrades to a scrollbar rather
than to silent clipping when the window is dragged narrower. Measurement moved the fix: an
`HSplitContainer` does **not** squeeze its first child, so the tool tree was never displaced and
the split-offset clamp the report proposed would have fixed nothing.

**A global is the DEFAULT, an object may override it** (dev, 2026-08-16). `BoardMirror` is the only
place that resolves the two, so nothing downstream knows a global exists.

### GLOW IS TWO QUESTIONS, and only one of them can be per-source ([#420](https://github.com/Phaazoid/Godoiosis/issues/420), 2026-08-21)

The dev's ask was *"the glow settings belong on the Fire tab"*, and the ticket was filed as a
composed-VIEW question — one page showing rows from two knob tables, each still saving to its own
home. **That framing was wrong, and re-deriving from the code is what showed it.** The rows it
proposed to compose are the wrong rows.

| | what it is | scope it can have | where it lives |
|---|---|---|---|
| the bloom **pass** | `WorldEnvironment.environment:glow_*` — one screen-space post-process | scene-wide. **Cannot** be per-source: there is one Environment per board | Moods → Post, **mission mood, and staying there** |
| what a source **throws into** it | `emission` + `emission_energy_multiplier` on the source's own material | genuinely per-source | the source's own table |

The second row **had no knob anywhere**. Fire's was four hardcoded values — `Color(1, 0.55, 0.15)`
and `2.5` in the flame material, plus `Color(1, 0.62, 0.3)` for the light it casts, while props
have had a tunable `prop_light_color` since #380. So the only glow-shaped dial in the whole panel
was the scene-wide one, which is exactly why it got reached for: the dev went looking for *make the
fire glow harder* and found *make the whole image bloom harder*.

**The fix was therefore to ADD the missing knobs, not to move any.** `flame_glow_color`,
`flame_glow_energy` and `flame_light_color` are Fire-group rows beside `flame_light_energy`, its
natural neighbours — and once they exist, the thing being tuned next to the flame IS a Fire-table
row. **No cross-table view is needed, and none was built.** *Do not build one on spec.*

The coupling to know: `glow_hdr_threshold` is a silent gate — emission below it does not bloom at
all, so raising a source's glow under a high threshold makes it brighter without haloing. Both
ends carry a tooltip pointing at the other; it is not an argument for moving a row.

**The underlying complaint stands and is unresolved**: the tabs are organised by *where a value is
stored*, the dev tunes by *what he is looking at*. #420 answered it the cheap way — group the rows
better (see the Elemental tab below) rather than invent cross-table views. Expect it again.

**CASTING LIGHT AND GLOWING ARE DIFFERENT QUESTIONS, and only the second constrains the form.**
A light is its own node — parent an `OmniLight3D` beside anything and it lights the scene, whatever
the thing beside it is drawn as. Making the ART itself glow is emission, and emission is a
**material** property, so it is only available to something that has a material.

**A `Sprite3D` does not.** Measured 2026-08-21: `SpriteBase3D`'s entire surface is `modulate`,
`shaded`, `alpha_cut`, `alpha_scissor_threshold`, `alpha_antialiasing_*`, `billboard`, `cast_shadow`,
`gi_*`. Very likely why #324 built the flame as a `MeshInstance3D` + `QuadMesh` +
`StandardMaterial3D` in the first place. So **a thing that should GLOW needs a form that can emit**,
and authoring `prop_lit` on a `BILLBOARD` tile gets the `OmniLight3D` and silently **no glow from the
art** — a half-working state with no warning, worth a `BoardLint` check once more than one tile can
get it wrong.

**Three tickets sit on this split, and it is what separates their costs:**

| | casts light | its art glows |
|---|---|---|
| **fire** (#324, #420) | yes, always did | **yes** — it is a `MeshInstance3D` already, which is why #420's emission knobs were cheap |
| **the lamp** ([#454](https://github.com/Phaazoid/Godoiosis/issues/454)) | yes, since #255 | **no** — a `BILLBOARD` prop is a `Sprite3D`; this is the whole reason that ticket pairs the glow with the model |
| **carried gear** ([#320](https://github.com/Phaazoid/Godoiosis/issues/320)) | **buildable today** — the light is a sibling node, so `UnitSprite3D` being a `Sprite3D` does not block it | **no, and doubly so** — the sprite has no material, *and* a unit is ONE sprite, so there is no staff-head to emit separately even if it did |

That last row is the useful one: **#320's cast-light half is unblocked and its glow half is a
different feature**, needing the carried item to be its own drawn thing rather than pixels inside the
unit's sprite. Do not let the second silently ride in on the first.

Their shared question is **where a light source's values live**, and there are already three homes
(a `BoardMirror` global default, a per-type TileSet column, and the `LookPreset` a mission wears).
Carried gear must land in one of those shapes rather than inventing a fourth — Law #4, flagged on
#320 at filing and now concrete, since #454 pins the prop side.

**Which is why lamp emission is [#454](https://github.com/Phaazoid/Godoiosis/issues/454) rather than
part of #420**: closing that gap on the billboard path means changing the node kind, and the dev's
own plan retires that form (*"I don't like lanterns as a billboard… the current setup is wholly
temporary"*). The census is what makes the consequence exact — **two** `BILLBOARD` tiles exist
(Lantern, Tree) and **exactly one tile is `prop_lit`: the Lantern**, so moving it to a solid form
leaves **zero lit billboards** and nothing waiting on that path. On the block path emission is a
`set_surface_override_material` over a duplicate of the generator-baked material, per surface —
no node-kind change, no test rewrites, no UV question, roughly a third of the cost, and it survives.

*(The estimate this replaces said converting the billboard path "touches every tree, banner and
fence". Wrong — fences are `PLANE` and already go through the meshlib block path. #263's precedent:
an assumption reversing under measurement, in the direction that made the work smaller, which is
the direction nobody checks.)*

### The Elemental tab (#420)

`Fire` and `Cover` both map to an **Elemental** sub-tab of the Game tab. Cover moved off *World*
because #326 already ruled it the same kind of thing — a terrain STATE whose art draws objects —
and the two now sit together. **Frost has nothing to move yet**: `FROZEN` draws as a flat icon on
`Layer.TERRAIN` with no 3D effect, so it gets a section when someone builds one.

It stays a SUB-TAB rather than its own tree leaf, and that is the storage rule again: elemental VFX
are game constants, so they want `GameTool`'s existing Save-to-source. A separate leaf would need
its own panel and its own save — a duplicate seam for nothing. A new element is one `GROUP_TABS`
line.

**A tab named for a category with two members is a promise, not a category** — what keeps it is
[#455](https://github.com/Phaazoid/Godoiosis/issues/455), the board channel of *elemental state made
visible*. Its strongest single item is that **BLAZE and BURNING are still visually identical**
(#174's one-texture ruling; #324 recorded not fixing it as deliberate), i.e. two mechanically
different states the board refuses to distinguish. **Its sibling is
[#358](https://github.com/Phaazoid/Godoiosis/issues/358), the UNIT channel** — wet drip, frost
sheen, Crisis — and the two are named together because they can disagree: a CHILLED unit wearing a
frost sheen while standing on a FROZEN tile drawn as a flat blue quad is two answers to one idea.
Whatever #358 settles for layering and intensity is the doctrine here too. Restraint governs both
(dev, #346): *effects in the correct places rather than everywhere* — "the tab looks empty" is not a
reason for a state to earn one.

**A knob written once at build needs a SWEEP or it is not a knob**, and this ticket paid it twice.
`_rebuild_fires()` was already the answer for the five geometry knobs (#324); emission and the
light's colour join them. It also caught an existing one: **`flame_light_range` had shipped with no
setter**, so dragging it moved nothing on a board already alight — `_animate_flames` refreshes
`light_energy` alone and the props sweep walks `_props` by design. `flame_light_energy` keeps no
setter on purpose: the animation loop re-reads it every frame, and a second path to one property is
a second authority.

**INHERIT is zero, and that is forced rather than chosen.** `TileData.has_custom_data` answers
whether the *layer* exists, never whether *this tile* wrote to it, so an unauthored field arrives as
its type's own default and the sentinel has to BE that default. A `Color` layer's default is opaque
black, not transparent — so blackness means inherit there, since a black light is the same non-value
a zero energy is. The cost is that a literal zero is not authorable, which for these fields is no
cost: `prop_lit = false` already says "no light", and better.

**Which props glow is CONTENT** — it lives in the tile's own `prop_lit` column. It used to be a
hardcoded name list in `BoardMirror`, which is exactly the shape Law #4 warns about: a fact the
content layer should hold, sitting in a script because that was where the first reader stood.

---

## Decisions

### Two presentations, parallel stacks (dev, 2026-08-12)

The HD-2D presentation (#176) is built as its own parallel stack. **The flat-2D game stays alive, playable, and untouched** — the experimental sandbox, the test harness's home, and the dev tools' host. No feature-parity obligation in either direction.

- ~~A launch-time chooser (which battle scene Mission Select boots) arrives around stage 4~~ — **SETTLED 2026-08-14, and the answer is no chooser: the game always boots into 3D.** `Battle3D.tscn` is the `main_scene`; it hosts `Main.tscn` and the existing **F4** toggle is the whole 2D escape hatch. The dev declined a title-screen 2D button for now: *"the 2D mode is an afterthought at this point — the development will be focused on the 3D version, and if there's extra time somehow, the 2D version can catch up."* The parallel-stacks doctrine above is unchanged; what changed is which stack is the default, not whether the other still runs.
  - `Battle3D.auto_play` defaults **false** so the hosted game opens **Mission Select** for itself. True is a dev shortcut that jumps straight to `mission_path`, and shipping with it on would skip the title screen, the mission list and Load Game.
  - The cost, paid immediately: **`Main` is no longer at `/root`**, so `game.gd`'s absolute `/root/Main/DevOverlay` lookup returned null and F1 went dead in the 3D build. Now relative. Any other absolute `/root/...` path inside the game subtree is the same bug waiting.
- **No formal BoardView interface up front.** The interface direction is right, the up-front project is not: an interface designed before its second implementation exists gets shaped wrong. Stages 1–4 build presentation-neutral seams (cell↔world, picker, facing, overlays), each stage leaving the sim/view boundaries it touches cleaner — by stage 4 the interface exists *de facto* and formalizing it is a rename, not a refactor. (The `HoverPresenter`/`MainActionMenu`/`OrderExecutor` extractions are the precedent: extract when the tangle earns it.)
- **The trailer beat** — opening on the flat 2D game, then dramatically becoming HD-2D — stays achievable: a capture cut works today; the live version (both stacks reading one sim, crossfade) becomes a small job once stages 1–4 exist.
- **Elevation in the 2D style (dev ruling, 2026-08-12):** *"a Z level is just a variable"* — 2D spritework can emulate elevation (the FFT/Tactics Ogre lineage proves it: sprite offsets, stacked tile sides, drop shadows), so rules-level elevation (#116) does **not** retire the 2D side. The honest difference is cost, not possibility: the 3D board renders height structurally for free; the 2D board pays an authored-cleverness tax per effect — and with no parity obligation, that tax is optional per feature. *"With a little bit of cleverness, any effect can work in both styles."*

### The 3D view is solo-playable, and the 2D game is its UI (#222, stage 4c, 2026-08-13)

Stage 4b made the 3D view playable by keeping the whole 2D render as a corner picture-in-picture — a declared crutch. 4c retires it. **The hidden 2D game is now the UI surface**: its container covers the window at native scale over a transparent viewport with its board visuals hidden, so every Control draws over the 3D world and takes physical clicks natively (real tooltips, menus placed at the real cursor, the `ModalLock` click path untouched). Consequences worth knowing:

- **Board markup mirrors, it is not reimplemented.** `OverlayMirror` polls `OverlayManager`'s retained state each frame and diffs it into `BoardOverlays`/`UnitMirror` — no trigger-site hooks, and the 2D stays the one authority for every cell set, texture, tint and animation (the aim pulse is its layer modulate, polled). The parallel-stacks doctrine holds: two representations, one declared authority.
- **A diff key must cover everything the render reads, and markup is drawn through TWO stores ([#308](https://github.com/Phaazoid/Godoiosis/issues/308), 2026-08-16).** The 2D is the authority for *which* cells are marked; `BoardHeights` decides how each one is *drawn* — the tilt a fill lies at (#281) and the surface a flame stands on. Neither is in a cell list, so a **rise painted onto a cell whose elevation does not change** left `_fill`'s `Array[Vector3i]` byte-identical and the quad kept its old tilt. The rule: a poll that draws through a second store **gates on that store having changed**, never on a copy of what it reads — a copied key is a second spelling that goes stale again the moment the render grows an input. `DirtyCells.version` is that gate, a monotonic count beside the cell list, non-consuming so it does not touch `battle3d`'s ONE-CONSUMER claim on the list itself. Coarse on purpose (any height edit re-pushes every fill layer) because height edits are authoring events, and the alternative pays per cell per layer per frame forever.
- **Overlays render UNSHADED** (dev ruling): gameplay markup must never read as terrain, which is why fills are unshaded quads rather than Decals — a Decal's albedo modulates the lit surface by construction.
- **Markup LIES ON the surface it marks; anything that STANDS on one stays upright ([#281](https://github.com/Phaazoid/Godoiosis/issues/281), 2026-08-15).** Dev: *"they should be flat against the ground, even on slopes."* `BoardSpace.surface_transform` is the one answer to how a flat thing lies on a cell — position *and* orientation, with `surface_point` as its origin so the two halves cannot drift. The tilt derives from `Terrain.gradient_of_corners`, the same call the ramp wedge's own yaw comes from, so ground and markup can never disagree about which way a slope climbs. **A CORNER CELL HAS NO SUCH TILT, and the fold moved to the MESH ([#427](https://github.com/Phaazoid/Godoiosis/issues/427) slice 4 follow-up, found in play).** Four non-coplanar surface points, and an affine transform maps a plane to a plane — so the best-fit plane crossed the ground by a quarter of the climb at every corner, six times `fill_lift`, which is what z-fighting on a corner tile's flat half and arrows cutting through it both were. `surface_transform` now returns an identity basis there rather than a tilt it cannot honour, and `BoardOverlays._surface_mesh` gives the marker four vertices at their true heights, split on the diagonal `Terrain.height_at_uv` splits on. Planar cells — flat ground and every cardinal ramp — keep the one shared `PlaneMesh`, so this costs a predicate and nothing else on the boards that exist. A SPRITE's shape travels in its marker entry **alongside** the basis, because the knockback drop pointer carries an orientation of its own and lies on nothing: an absent shape means airborne. Units, flames and props keep reading `surface_point`, and billboards and the hover bracket (a cell *volume*) are declared non-tilting. **The tilt carries a stretch**: a ramp face is 1.414 cells long, so markup that only rotated would leave it bare at both edges — stretching is also what makes an arrow foreshorten exactly as the ground under it does. Both values are derived geometry, not taste, so neither is a Look knob. **The tilt is the surface's; the LIFT is not ([#432](https://github.com/Phaazoid/Godoiosis/issues/432), 2026-08-21).** Every ground marker clears the ground it lies on by `fill_lift + sort * lift_step`, and that clearance goes **straight up**, never along the marker's own normal. What the lift buys is a shared *plane* — every marker on a layer the same distance off the ground, which is what lets one ribbon run through several of them — and since `BoardSpace.surface_height_at` already meets exactly at a shared edge, only a **constant** vertical offset leaves the markup meeting there too. Riding the normal instead decomposed on a slope into half up and half *downhill*, sliding every ramp marker `lift·sin(45°)` out of the cell it marks — a gap at the uphill join, an overlap tucked under the downhill one, and layers misregistered against each other in proportion to their own sort, which is the opposite of what #281 chose the normal for. It also made `lift_step`, whose documented job is vertical spacing, silently control horizontal placement on slopes. The price is that a 45° slope's *perpendicular* clearance is `cos(45°)` of the flat ground's — `fill_lift` is the knob if a ramp ever speckles, and the flat ground it was tuned on is unchanged.
- **Board clicks skip events entirely.** The picker calls `game._on_left_click` / `_on_right_click` (the dispatchers game.gd's own `_unhandled_input` only feeds), and `game.board_input_delegated` stands the 2D derivation down so one physical click cannot act twice. That bool is the whole arc's only game.gd input edit; unset, the flat 2D game is bit-for-bit unchanged — **all hosting mutations are runtime**, never authored into `Main.tscn`.
- The corner PiP survives as a **dev debug view** (F4), not a player-facing mode. The launch-time chooser named above is still stage 4d.
- **A mirror that copies a FLAG inherits every writer of that flag — mirror the QUESTION instead ([#232](https://github.com/Phaazoid/Godoiosis/issues/232), found in play, 2026-08-14).** 4c copied `$MapSprite.visible` to get planning-ghost parity, and `Unit._show_downed_sprite` writes that same flag for an unrelated reason (swapping in the separate downed art) — so going down made a unit vanish from the diorama one line after the mirror had correctly given it the downed pose. The fix is Law #4 at the source: `UnitVisuals.projected` is now declared, so the two questions stop sharing storage. The twin, same commit: the faction tint is set on the **Unit node** and 2D multiplies it down the tree for free, so copying only the child's `modulate` left every enemy un-reddened in 3D — the mirror takes the product. **The general rule for anything polling the 2D: copy what the 2D *renders*, not the field it happens to be stored in.**
- Both of the above were **green under the suite**: `test_downed_and_death_reconcile` asserts the texture swap and passes against a unit nobody can see. Parity tests have to assert what reaches the screen.
- **Draw ORDER is part of the mirror's contract, and the 2D's z-order is the authority for it** (found in play 2026-08-14: freeze icons drew over path arrows and planning ghosts). `BoardOverlays.LAYERS`' `sort` had terrain state at the top of its range while the 2D puts it at `TERRAIN_Z_INDEX` — *above the board, below unit sprites* — with arrows above that. The two orders are now tied together by a test that reads both sides, so retuning a sort is free but **contradicting the 2D reds**. Beneath that sits a structural rule the 3D had simply been missing: **`BoardOverlays.UNIT_RENDER_PRIORITY` puts every unit sprite above every overlay layer by construction** — the twin of the 2D's "tile overlays sit below `Unit.BASE_SPRITE_INDEX`". Planning ghosts are `UnitSprite3D`s, so they inherit it; before it they were priority 0 and *arrows* drew over them too, which nobody had reported yet.
- **Anything that starts writing depth must first be checked for COPLANARITY — the two failure modes are opposite, and fixing one hands you the other** (fire, 2026-08-14, twice in one day). A flame that did *not* write depth lost to whatever did, which is how a body lying in fire swallowed it. Switching it to `TRANSPARENCY_ALPHA_DEPTH_PRE_PASS` fixed that and immediately produced the worst z-fighting on the board, because a centred 0.7-tall quad lifted 0.35 has its **bottom edge at exactly y = 0** — coplanar with the tile it stands on, seen at the grazing angle a pitched camera looks from. Harmless for as long as it stayed out of the depth buffer. The clearance is now a **clamp** (`BoardMirror.flame_base_lift`), not a default, so no authored knob can put the quad back in the ground; that is the flame's twin of `BoardOverlays.fill_lift`, and **every new depth-writing surface owes the same check**. **So does every surface drawn on top of another one — the corner CAP ([#427](https://github.com/Phaazoid/Godoiosis/issues/427), found in play 2026-08-25).** A cap sits on a column whose top block reaches exactly the cell's surface, and an OUTER corner's own surface has a whole triangle at that same height — three corners at the low side — so the cap and the block drew the same grass into the same plane. Fixed by *not drawing it twice*: **a cap draws nothing in its own floor plane**, which is the rule its side walls already followed. The tell that it was a mesh bug and not a markup one: it appeared on corner tiles and never on a wedge, whose low side is an EDGE with no area. **Two faces had to go, not one, and removing the first is what proved it** — the top triangle and the bottom QUAD both lived in that plane, and taking only the triangle handed the whole area to the quad. A back-facing polygon rasterises to no pixels, so the shimmer became **holes straight through the board**: when a coplanar pair resolves in favour of something that is then culled, the artefact is not a fight you can see, it is an absence. **Which way a duplicated face points decides only what the bug LOOKS like — so a coplanarity check has to count UP and DOWN faces alike, and skip degenerate zero-area triangles or it reds on correct geometry.** The residual — a flame and a unit sprite are both camera-facing planes through the same point, so they are coplanar by construction wherever a unit stands in fire — outlived both attempts, and **it is not a trade between two artefacts, which is what this bullet claimed until 2026-08-15 ([#298](https://github.com/Phaazoid/Godoiosis/issues/298))**. Both are `BILLBOARD_FIXED_Y` quads whose origins share the cell's X/Z, and a Y-billboard yaws about its own origin — so they are not two planes sitting close together, they are the **same plane**, and the flame fights the sprite whichever way `flame_writes_depth` is set. Swallowed ([#243](https://github.com/Phaazoid/Godoiosis/issues/243), closed — it stopped reproducing) versus speckled (#298, live) is which way per-fragment precision fell, not a mode anyone picks. `flame_lift` reaches neither, because **Y is the one axis that cannot separate two vertical coplanar planes** — so the fix has to be geometry that separates them: an offset toward the camera, non-billboarded fire, or the particle version already on the Tier 1 wall below. **#324 took the first of those, and the reason it is a fix rather than a number is that it is recomputed every frame from the LIVE camera** — a baked offset is a guess about where the viewer is, and free orbit is exactly the thing that invalidates a guess. See *Fire is an effect, not a sprite* below.
- **A BURIED face is still a DRAWN face, and at an axis-aligned yaw a whole row of them lands on one scanline ([#559](https://github.com/Phaazoid/Godoiosis/issues/559), 2026-08-26).** The bullet above is about two surfaces meeting in a PLANE; this is its sibling one dimension down — two surfaces meeting along an EDGE. Every ground block emitted all six faces with no knowledge of its neighbours, so a side quad's top edge sat exactly in the top face's plane, where the neighbouring cell's top face also ends. Four surfaces, one line, and a pixel centre landing on it could be won by the dirt. **What made it a BUG rather than noise is the camera:** off-axis those wins scatter across scanlines and read as texture, while at yaw 0/90/180/270 an entire row of cell borders projects to a single screen row and the scatter becomes a clean brown hairline across the board — and `CameraRig3D.align_to_detent` snaps to exactly those yaws on the enemy phase, so the game drives itself into the triggering pose. Diagnosis rule worth keeping: **a CONSTANT artefact colour, unchanged by whatever is behind it, rules out every shading cause at once** (cascade banding, AO, depth haze all MODULATE the pixel underneath) and proves something is being drawn; and tracing a terrain edge THROUGH the artefact separates an overlay from a seam between two renders. The fix is geometry again, never a number: the sides now stop `BoardSpace.SIDE_RIM` short of the surface and a RIM wearing the TOP material closes the gap, so the surface still meeting the neighbour at a border is ground-coloured and a residual tie is invisible. Dropping the sides without the rim would have opened a band at every cliff crest — and since the same ticket put `cull_mode` back to `CULL_BACK`, that band would read as a hole through the board rather than as an inside face. **Culling had been silently insuring every open shell in the meshlib**; `_form_mesh`'s deliberate one is now pinned rather than merely argued.

### The camera contract, amended: free orbit rests, Q/E realign (#176 stage 4d, 2026-08-14)

The original contract locked **"yaw snapping in 90° steps"**. The dev asked the sharper question — *do we need to snap to anything at all?* — and the answer from the code was no:

- **Sprite facing never depended on it.** `UnitSprite3D.facing_flip_for` judges each step against the **live** camera basis, so it is correct at any continuous yaw today; the future `frame_for(unit_facing, camera_yaw)` seam quantizes the *relative* angle internally.
- **"Units can't hide behind terrain" is helped, not threatened** — free rotation reaches every angle rather than four.
- The genuine cost is **texel shimmer at off-axis rest**, which is aesthetic and about the *resting* pose, not about what happens mid-drag.

**So: yaw orbits freely and rests wherever the player leaves it; Q/E step to the next 90° detent, realigning in one press.** The crisp axis-aligned pose is now an affordance rather than a cage. A corollary the amendment forced: facing was only re-judged when a unit *moved*, so any rotation left standing sprites facing the old angle — snapping never protected against that either; the mirror now re-judges on camera turn.

Bindings are knobs, not canon: `orbit_button` was built to default to middle-drag so right-click could keep its press-to-cancel meaning, with the click/drag threshold built so flipping it was an inspector change. **The dev flipped it to right-drag after playing it (2026-08-14)** — *"you don't need to drag the mouse when canceling orders, so the overlap is a non issue"* — which is the knob working as intended; cancel now fires on release-under-slop, and moving the binding back moves it back to press.

Also settled here: **the camera follows the action by mirroring the 2D camera** (which `AIController` already pans to each acting squad) rather than growing a second follow seam — so `Pacing.AI_SQUAD_PAN` keeps one number and one reader, and the 3D inherits the 2D's easing exactly. The gate is `ai_locked`, deliberately *not* the broader board lock, which also covers menus. **Entering an AI turn also squares the camera up** to the nearest detent (dev call, 2026-08-14): free orbit is the player's, but an enemy phase reads on an axis-aligned board. It fires on the *edge* into the turn rather than every frame, so the day orbit is allowed to stay live under an AI turn it squares up once instead of fighting the drag.

### The camera comes BACK when an order is committed ([#471](https://github.com/Phaazoid/Godoiosis/issues/471), 2026-08-22)

The mirror above answers *the AI is acting somewhere else*. #467's ring raised the other half: the ring
does **not** lock the board, so the player can pan the diorama anywhere while choosing — and then
commit an order that plays out around a unit no longer on screen. **A terminal pick brings the view
back to the acting unit; backing out with no order leaves it exactly where the player put it.** The
dev's line drawn once: *action versus no action*, not board-verbs versus UI-verbs. Inspect and Wait
yank the camera too, and that is a knob to turn in play rather than a rule to guess at.

- **The gate above is untouched, and reaching for it would have been the wrong fix.** `pan_to` moves
  the hidden 2D camera, which under `HD_2D` nobody is looking at, so widening `ai_locked` was the
  obvious answer and would have produced a change that runs and does nothing visible ([#103](https://github.com/Phaazoid/Godoiosis/issues/103)'s shape).
  `battle3d` already had a **player-initiated** rig recentre that never touches the mirror — SPACE —
  so this is a second caller of `_center_rig_on(cell)`, and the two guard cases in
  `test_camera_follow.gd` keep saying exactly what they said before.
- **SNAP, not glide** (dev call). Two reasons beyond the feel: the rig smooths yaw and distance but
  **not position** — every writer, WASD included, assigns it outright — so a glide is a mechanism to
  invent, not a duration to pick; and the 2D twin's `center_on_position` sets `lock_manual_input`,
  refusing the player's own camera on the way in, which is the wrong answer for someone who just
  gave an order.
- **`game.focus_view_on(unit)` derives the cell ONCE and emits it.** The **projected** destination,
  which is already what every gate and pick layer means by "where this unit acts from" ([#126](https://github.com/Phaazoid/Godoiosis/issues/126)),
  so a queued move is followed rather than second-guessed. The 2D camera is written there and the 3D
  rig on the signal — one question, two cameras, no second answer about which cell.
- **The 2D write stands down under a 3D host, and that is load-bearing.** `battle3d._update_pointer`
  snaps that hidden camera on every motion purely to park the hover card, so writing it from here
  would mis-anchor the card and change nothing else. Same flag, same reason, as the WASD poll's.
- **2D/3D** ([#292](https://github.com/Phaazoid/Godoiosis/issues/292)): both views answer it. `CORNER` deliberately does not — it is a debug PiP whose
  2D camera is already being dragged by the pointer.

**Riding along: the pointer poll re-derives on CAMERA movement, not only on mouse movement.** The
pick depends on both, and the early-out only compared the mouse — so panning the world under a still
cursor left the hover bracket on the cell the pointer had *left*, until you jiggled the mouse. True
of WASD and of SPACE long before this ticket; the return-to-unit is what made it frequent enough to
be worth fixing. It compares the camera's whole transform rather than the rig's position, because
yaw and zoom move the pick too and both lerp for frames after the input that started them.

**The invariant that keeps two authorities apart, worth stating because nothing in the code says
it:** `_update_pointer` WRITES the hidden 2D camera and `_mirror_camera` READS it, so the two chase
each other to the pan limit if they ever run in the same frame. `ai_locked` opens the second gate and
the board lock shuts the first, so what keeps them apart is that a locked board is implied by
`ai_locked` — which is why, since [#484](https://github.com/Phaazoid/Godoiosis/issues/484),
`_board_locked_for_player()` **reads that flag** rather than only `game_state == AI_TURN`.

**This paragraph used to claim the pair was unreachable, and that claim is what shipped the bug.** It
argued the two are written in one block by `start_faction_turn`, so `ai_locked` without a locked board
could not happen. But `game_state` is TRANSIENT — `set_dev_mode` and `clear_board` both rest it on
`_base_state()` from anywhere — so toggling dev mode mid-enemy-phase (either direction; *off* lands on
`IDLE`) reached it, and the mouse became welded to the camera. **The lesson is the shape, not the
path:** an invariant that holds because of *who writes what, in what order* is a coincidence with good
manners, and the fix is to make the pair unrepresentable rather than to enumerate the ways in. Two
other things that same window opened, both worse than the camera: board clicks stopped refusing during
an enemy phase, and `can_control` returns `true` for *any* unit in `DEV_MODE`, so enemy units became
commandable.

Note the containment is one-way and deliberate. `_mirror_camera` still gates on `ai_locked` alone,
**narrower** than the board lock, because that predicate also covers `MENU` and Mission Select opts out
of the modal lock — mirroring there would yank the rig to a stale 2D position the moment a menu opened.
Widening *it* was the obvious-looking fix and is the wrong one; the two `test_camera_follow.gd` guard
cases still say so.

### The rig aims at the SURFACE, never at the board's ceiling (dev report, 2026-08-23)

Found by playing the section above, and **pre-existing since 4d rather than caused by it** — which
is what made it worth a rule instead of a patch. Recentring on a unit in Level_1 put the view above
them, and *so did the enemy phase*.

`CameraRig3D._aim_at` lifts the opening shot to **the top of the whole board volume** — its own
comment says why: so the pitch looks down at the surface rather than through it. That is right for
FRAMING a board and wrong for LOOKING AT something standing on one, and **nothing ever re-derived
it**: `_center_rig_on` and `_mirror_camera` both kept `_rig.position.y`, so the opening shot's
height was the aim height for the rest of the battle. Level_1 has columns to level 4 and an
authored `camera_start` that froze `aim.y = 5` against a ground surface of `y = 1`, so the look-at
point floated four cells in the air; at close zoom the unit rode off the top of the frame. Prolog
is flat, which is why it never showed there and why the report named two boards and an AI turn.

**The rule: whatever the rig is aiming AT, it aims at the surface under it.** Both readers now do:

- `_center_rig_on(cell)` takes `BoardSpace.surface_point`'s WHOLE answer — the same seam
  `UnitMirror` places the sprite with (#273), so the camera looks where the unit visibly is, ramps'
  half-level rise included.
- `_mirror_camera` takes the continuous twin, `surface_height_at` (#259). The 2D camera answers
  WHERE and the board answers HOW HIGH; continuous rather than per cell because an AI pan is a
  GLIDE, and a height that stepped at cell boundaries would jolt the diorama mid-beat.

One authority, two entry points `BoardSpace` already ships — not two answers.

**What is deliberately NOT fixed, and is the reason this is a rule rather than a finished feature:**
WASD panning still leaves `position.y` where the last recentre put it, so panning from a valley
onto a hill re-opens a smaller version of the same gap. Making the aim height track the terrain
*continuously* would mean teaching `CameraRig3D` about the board, which it deliberately does not
know (the look-dev scene shares it and has no board at all). Filed as its own question rather than
smuggled in here.

**The general shape, worth carrying:** a value that is correct at INITIALISATION and never
re-derived is invisible for exactly as long as its initial answer stays close enough — and a flat
board keeps it close enough forever. Two of this suite's own cases had pinned the inherited height
as CORRECT (`is_equal(Vector3(point.x, before.y, point.z))`), which is how a bug outlives the tests
written over it.

**The opening shot is the player's squad, not the board (dev feel-check, 2026-08-14: fitting all 64×40 of Prolog opened too far out to play from).** These are two different questions and the rig now takes both — `frame(shot, bounds)`: the *shot* is what is on screen at load, the *bounds* are the box the view may never leave, and only the bounds set the zoom ceiling and the pan limit. Solving the ceiling off a close shot would have clamped the player out of ever seeing the rest of the map, which is the same class of bug as the cells-passed-as-a-distance one this stage fixed. Falsification note worth keeping: the obvious test — *are the player's units on screen at load?* — **passes against a window aimed at the board's centre** on both authored missions, because both squads start near the middle. The aim itself has to be asserted, or "opens on your squad" is pinned by nothing.

### A mission may AUTHOR where it opens ([#234](https://github.com/Phaazoid/Godoiosis/issues/234), 2026-08-15)

**Two answers to "where does the camera open", declared per Law #4: an authored pose is AUTHORITATIVE, and the squad derivation above is the fallback for a board that authors none.** Same shape as the `objectives`-vs-painted-`zones` guard in [`missions.md`](missions.md). A derivation is the right default and the wrong authored answer — a handcrafted level opens on the gate you have to breach, which is not necessarily where your squad is standing.

`ScenarioData.camera_start` holds it, as a `CameraPose` (aim + yaw + distance). Four things are declared rather than obvious:

- **A pose, not a volume, which is why `frame()` could not be the insertion point.** `frame()` *derives* position and distance from a box and deliberately never touches yaw. Free orbit (above) makes yaw part of what a shot IS, so the shot half needed its own door — `pose(aim, yaw, distance, bounds)`. The **bounds half is the same `rebound()` call**, so an authored start replaces the shot and nothing else moves: ceiling and pan limit stay derived from the board.
- **Yaw is set BEFORE the bounds are solved, and that is load-bearing.** `rebound()` solves the fit through the camera's own basis, so a ceiling computed at the previous yaw is a fit for an orientation the shot will never be seen at. Caught by the equivalence assertion in `test_camera_rig.gd`, not by reasoning. `pose()` also adopts yaw as **home** — R means "back to the opening shot", and an authored one includes its angle — which is the one place it deliberately differs from `frame()`.
- **A REFERENCE on `ScenarioData`, unlike `look_preset`'s name-only rule (#253).** The difference is whether the resource has a life of its own: a `LookPreset` is a file, so a ref can dangle or silently embed (#177's `unit_data` trap). A `CameraPose` has no file and no existence outside its board — embedding it as a sub-resource on save is exactly the wanted behaviour.
- **A board already authored how WIDE it opens.** `opening_view_cells` is a Look knob, i.e. scene mood, so every `LookPreset` carries it and a board names a preset. `camera_start` is therefore a second influence over a *different* axis (where / which way / how far), not a duplicate — it simply retires the width knob for the boards that use it.

**Nothing validates a start (dev call, 2026-08-15).** A stale aim — the board was edited after the shot was captured — is **clamped, silently**, by the `pan_limit` clamp `_process` already runs and by `set_zoom`'s existing bounds. There is deliberately no validity predicate, i.e. no second answer to "where may the camera be"; re-capture is the fix. Known consequence, accepted: an aim at a *deleted* cell that is still inside the board is not clamped at all, and simply looks at empty space.

**Save/resume: the authored start, every load** (dev call). The camera stays out of the #87 mid-battle snapshot, so a resumed save opens where the mission says rather than where the player left the view — which is #144's *"a menu arrival trusts the file"* read straight, since the file's only camera fact IS the authored start.

**3D only, declared** ([#292](https://github.com/Phaazoid/Godoiosis/issues/292)'s rule: a declared asymmetry is a design, an undeclared one is drift). The flat view has no opening shot to diverge *from* — nothing centres the 2D camera on a board load, and under `HD_2D` it is dragged around by the 3D pointer purely so the hover card parks against a live view. Serving 2D here would mean inventing a 2D opening shot, derived half included, which is that umbrella's work and not this one's.

Authored through the dev-tools **Scenario tab**: fly the camera, press Capture, save the board. Deliberately not typed in as numbers — and deliberately a field on the capture the tab already owns rather than a new tool. Out of scope but not precluded: the dev's slow orbit-and-descend that *lands* on the start, which is why the pose is one resource instead of three loose floats — a keyframe sequence extends it rather than re-homing three fields that had grown callers.

### The mirror is LIVE, and the turn-boundary approximation is retired (#231, 2026-08-14)

Stage 4a shipped two declared cadences: the board mirrored on `board_loaded`, and tile states re-read at `turn_started`. Both were honest v1 approximations, and both became wrong the moment authoring moved into the 3D view — you painted and nothing happened until F2, which is the round trip the whole dev-tools-in-3D arc exists to kill. They are gone.

**Fire is now reconciled per cell and polled**, so a mid-pass ignition appears when it happens. That also removes the artefact the old cadence produced: a flame that rendered wrong appeared to "come back at the end of the turn" because the *marker* was rebuilt, not the state. Poll rather than signal, and for a reason worth remembering: a `states_changed` signal fires *inside* the resolver's per-effect loop, so it would create and free markers many times within one pass, where a poll coalesces a whole frame into one reconcile.

**Terrain syncs per cell too, but only while `DEV_MODE` is active** — the sim never paints terrain, so the diff stays entirely out of the shipping game. (An engine signal was the first choice and does not exist: `TileMapLayer.changed` does **not** fire on `set_cell`/`erase_cell` in 4.7. Measured, with a property write as the control.)

**That diff used to be a whole-board walk, and the property it bought is now a law instead ([#319](https://github.com/Phaazoid/Godoiosis/issues/319), 2026-08-16).** Re-reading everything every frame caught every writer with *no trigger site to remember*, which was the point — and it cost O(board) per frame, i.e. a whole 60fps budget on Prolog before anyone painted anything. The trade: writes now announce which cells moved (`BoardGrid.paint`/`erase`/`reset`, `BoardHeights.set_cell`), the poll reconciles only those, and the cost goes flat in board size. **The "no trigger site" guarantee did not survive that and was not meant to** — `tests/law/test_board_writes_announce.gd` carries it now, and since [#391](https://github.com/Phaazoid/Godoiosis/issues/391) it has no exceptions: the bulk `tile_map_data` write was one — a property assignment a door cannot cover, made safe by `board_loaded` → `rebuild()` — until the authoring undo needed the same wholesale write and it got `BoardGrid.restore`, which `mark_all`s. Numbers and the two traps — a lowered floor still full-syncs; the board rect grows in place but shrinks by re-deriving — are in [`docs/performance.md`](../performance.md).

Two rules this settled, both general:

- **A repaint can add or erase a COLUMN**, which is what the picker table and the camera bounds derive from — refresh them with it, or the cell you just painted is unclickable. Bounds only, never a re-frame: painting a tile must not yank the camera, matching what `CameraController.refresh_bounds` has always done in 2D.
- **Authoring scaffolding mirrors only while the 2D shows it.** `ZONE_PATROL` (the brush's default kind) and the picked-zone highlight had no 3D twin at all; giving them one means mirroring *cells and visibility*, because the 2D reveals those layers solely while the Tile Brush tab is up. Mirror the question — "should this be on screen" — never the field the cells happen to live in.

### What mirrors for free, and what needs a channel ([#321](https://github.com/Phaazoid/Godoiosis/issues/321), 2026-08-16)

The attack lunge never reached the diorama, and the reason generalizes past this one effect. `UnitMirror` keys on **`unit.position`** — the Unit node — while `UnitVisuals` plays the lunge on **`$MapSprite.position`**, a local offset inside that node. The mirror was faithful and blind at once: it reproduced where the unit *is*, and the lunge deliberately never moves where the unit is. The walk is the counter-example that always worked, because `MovementComponent` moves the Unit node.

**The rule: anything a 2D effect expresses on the Unit node mirrors for free; anything it expresses as a child-sprite offset arrives through `UnitVisuals.animation_offset()`, and that is the whole of the offset channel.** Measured rather than assumed — the rest of the class's vocabulary is `modulate` (already mirrored as the product of both nodes, #222), `visible`/`projected`, `z_index` and `scale`, none of which needs a second answer. The only other writer of that offset is the invalid-order shake, which now crosses too.

Three things were decided here rather than discovered later:

- **Mirroring the offset, not giving the 3D its own playback.** The lunge direction is a **board cardinal** (`GridUtils.cardinal_direction_between`), not a screen axis — in the flat view those are the same thing — so the offset reproduces exactly under any camera yaw, and the 2D stays the one animation authority (#222's ruling). A second playback off the same `AttackAction` beat is what an eventual *real* attack animation wants; it is not what a half-cell lunge needs.
- **The lunge distance stays a 2D value** (`GridUtils.TILE_SIZE / 2`). There is deliberately **no 3D-side multiplier**: a view-local scale would mean the two views disagree about how far a lunge goes, which is the same second-authority problem one layer down. If it reads weakly at the pitched view, move the 2D constant and both views move — the same shape as `OverlayManager`'s attack-reach colour, which the 3D mirrors rather than duplicating.
- **The offset is added LAST, after the step, facing and cell derivations.** Those all read the sprite's position, so folding the lunge in earlier makes an out-and-back swing register as two steps — the unit ends facing backwards — and puts a mid-swing unit on the cell it is leaning into. `UnitSprite3D.art_offset` exists so the board point stays recoverable: position is always *board point + art offset*, one writer.

A 2D y is board **DEPTH**, never height, here as everywhere else on this stack (#263's fence, #280's flowerbed).

### A terrain STATE whose art draws objects takes FIRE's route ([#326](https://github.com/Phaazoid/Godoiosis/issues/326), 2026-08-16)

Burrow's COVER pops up as three mud bumps — the dev's ask, twice: *"cover should POP UP as three individual mud bumps cropping up, NOT the whole sprite rotating vertical"*, then *"burrow terrain should pop like the flowers do."*

**A state is not a tile, so `prop_shape` cannot answer for it** — cover is deposited at runtime through `TerrainStateManager` and has no meshlib entry to bake a form into. The question that *is* already answered is the one fire asked: what does a terrain state look like in a diorama? `BoardMirror` owns the standing form (the flame + light IS fire) and `OverlayMirror` skips that state's flat icon on the LIVE channel while keeping it on the PREVIEW channel, where the ghost is the only warning a queued order gets. Cover is now the second member of that rule; **FROZEN is genuinely flat and stays a ground quad**. So `Layer.TERRAIN` grew no "this state stands up" fork — the state left the layer instead. `OverlayMirror.STANDING_STATES` is the declared list, and it earned being a list at exactly two members.

**The bumps themselves are #280's decomposition, unchanged**: split the drawn pixels into 8-connected clusters and stand each one up at its own place — x from its centre column, z from its **bottom** row, because a top-down drawing's y is depth. One difference is worth stating, because it is where the two arts differ: a **tile** is opaque ground with things drawn on it, so its background colour has to be measured and keyed out; an **icon** already carries its own alpha and is clustered as drawn.

**The art had to answer "three" before the code could.** Measured before building, and it reversed the issue's own premise: `Cover.png`'s three mounds *touched* — one cluster 8-connected, two 4-connected — so the mechanism as shipped would have stood the whole icon up, which is the exact outcome the dev vetoed. Three pixels of seam were erased (dev's call). The general rule: **a decomposition can only find the objects the art separates**, so before reusing one, count the clusters in the art you are pointing it at.

Two smaller rulings ride along. The icon is the **2D's own**, not a 3D copy, so a re-drawn Cover reaches both views — which is also why its `detect_3d/compress_to` had to be cleared in the same diff (#250's trap: first 3D use silently re-imports a shared texture to VRAM + mipmaps, degrading the 2D that draws it too). And `cover_scale` is a **second** knob beside `tuft_scale` rather than a shared one, on the lantern-vs-flame rule: two different objects at two different drawn sizes, and one number would force whoever tunes the second to un-tune the first. (Both were Look knobs until [#272](https://github.com/Phaazoid/Godoiosis/issues/272) moved them to the Objects tab, and both left again — `tuft_scale` and `cover_scale` are Game-tab globals since #380, and `cover_scale` sits on the Elemental sub-tab since #420. See *Where a presentation value is authored* below.)

### Fire is an EFFECT, not a sprite standing on a tile ([#324](https://github.com/Phaazoid/Godoiosis/issues/324), 2026-08-16)

Fire came back in three separate feel-checks — #215's close (*"the fire looks not great"*), the #236/#243 depth fight, then the v0.39.0 playtest (*"the fire effect needs fixing too"*) — and each time it was tuned rather than designed. What shipped until now was **one static `QuadMesh` wearing the look-dev TORCH texture**, 0.5 × 0.7 in a 1×1 cell: no frames, no motion of any kind, and a lamp's art doing duty as terrain fire. The knobs were never the problem; the effect had never been designed, only positioned.

Four rulings, and each is reusable past fire:

- **A cell on fire is not one flame.** `flame_count` quads stand on a ring of radius `flame_spread`, seeded so the scatter is DERIVED from the cell — one tile always burns the same way, no two burn in step, and nothing needs a per-cell store to remember it. The same shape as #280's tufts one level up: *several small things placed across the square* is what reads as the square being the thing, and it is why a single sprite in the middle always read as an object standing on a tile.
- **Motion belongs in the ART, and the art is a sheet.** Eight looping frames generated by `tools/lookdev/gen_lookdev_assets.gd` (analytic, not per-frame noise — every term is periodic in `frame / count`, so the loop closes with no seam), stepped by sliding `uv1_offset` along `uv1_scale`. A shader could have faked fire without any texture, and was rejected for the reason the whole generated-greybox pipeline exists: **when an artist arrives the textures swap and the meshes stay**, and a sprite sheet is what an artist delivers. The sheet imports **lossless with no mipmaps and `detect_3d/compress_to` cleared** — block compression bleeds colour across frame boundaries and mipmaps blend neighbouring frames into each other, which is a hazard a single-image texture does not have.
- **Every strobing effect ships THROUGH #217's switch, never beside it.** `BoardMirror.flame_animated` is that switch's first tenant and its only reader here: off holds the frames still and the light at steady energy — *a still flame, never a missing one*, which is what [#217](https://github.com/Phaazoid/Godoiosis/issues/217) requires of every toggle-off state. It is excluded from `LookPreset` capture, and that exclusion is the sharper half of the ruling: **an accessibility choice is the player's, so authored content must not be able to reach it.** The player-facing half **SHIPPED as #217**: a `PlayerSettings` entry (`PHOTOSENSITIVITY`) the settings screen projects, ANDed with this flag in `BoardMirror._flame_animating()` — one composed reader, declared in the store, never beside the effect.
- **A tuning knob that only applies to the NEXT one built is not a knob.** Fire is reconciled per cell and left standing, so the poll never re-runs on a static board — every geometry value (count, spread, size, lift, the depth switch) re-stands what is already burning through its setter. The animation values need no such thing because the loop re-reads them every frame; that split is worth noticing before adding a knob anywhere that reconciles rather than redraws.

**#298 is addressed here rather than separately, and the redesign alone did not do it.** Scattering the flames off the cell centre helps and does not solve it: a Y-billboard yaws about its own origin, so a flame offset *sideways in screen space* is still in the unit sprite's plane, and which flames those are changes as the camera orbits. The separation has to be along the view — `flame_camera_offset` pushes every flame toward the live camera each frame, which is why it holds under free orbit where a baked number could not. It also delivers what that issue argues is correct anyway: **a body lying in fire now reads as on fire**, because the flame draws in front of it. Verdict is the dev's eye on a burning board; the geometry is what the tests can pin.

**Deliberately not done.** BLAZE and BURNING still look identical — #174's *one Fire texture covers both* stands, and making the permanent state read fiercer is a design call, not a free win (the expressive version, embers + smoke + haze, is already on Tier 1/3 below). Every flame is a quad and a draw, so `flame_count` is the one knob here with a real cost on a heavily-burning board; the answer if that ever bites is [#311](https://github.com/Phaazoid/Godoiosis/issues/311)'s one-mesh-per-cell, not a smaller number.

### Conventions the art commission must carry (pending look-dev experiments)

Two Tier-1/2 ideas below change *what art gets ordered*, so they are experiments to run in the look-dev scene **before** any commission, then locked into #176's conventions list:

1. **Emission channel** — windows, runes, crystals authored with an emission mask so bloom picks them selectively. Cheap to demand up front, impossible to retrofit across a finished sprite library.
2. **Normal-mapped pixel art** — generated from sprites (e.g. Laigter-class tools) so flat-lit art still takes directional light convincingly. This *amends* the flat-lit convention rather than breaking it (albedo stays flat; the normal map carries the depth). Decide by eye in the look-dev scene.

### A prop's FORM is authored art data, not a rendering choice (#255, 2026-08-15 — MEASURED, not predicted)

Stage 5b stood every object-shaped tile up as a billboard and the dev judged the result: *"most of it looks awful… things that are supposed to be blocky, like the chest and the crates, look so odd like this, they really want to be textures on a 3D model. The fences don't work at all. The lamps, surprisingly, are fine. I think **anything that's thin already works in this style**."*

That sentence is the convention, and it is the same split Octopath uses (billboarded foliage and lampposts; real geometry for crates, walls and buildings). **A prop therefore has four possible forms, and which one it is belongs to the ART, decided when it is drawn:**

| Form | What it is | Renders as | Art it needs |
|---|---|---|---|
| **Billboard** | thin, roughly symmetric about its vertical axis — lamps, trees, banners | camera-facing sprite, pivot at the base | one front-on sprite (what a tilesheet already gives) |
| **Oriented plane** | thin but DIRECTIONAL — fences, railings, low walls | thin slab, run authored per piece | one front-on sprite **plus a facing** |
| **Block** | volumetric — crates, chests, rocks, barrels | real geometry standing on the ground block | a **top** texture and a **side** texture, minimum |
| **Tuft** | ground WITH things growing on it — flowers, weeds | one small camera-facing sprite **per plant the art draws**, over a generated speckle in the tile's own colours | the ground tile itself, nothing more |

**The form is ONE authored column, `prop_shape` on the tileset** (`GridUtils.PropShape`, read by `BoardMirror` and by `gen_lookdev_assets.gd`). It began as #255's `stands_up` bool and was widened by #264 rather than joined by a second column: a tile's shape and whether it stands up are one question, and two answers to it can disagree. `FLAT` is the ground itself; `BILLBOARD` is the thin form; `CUBE` / `FACETED` / `ROUND` are the block form, with the member naming the solid so a crate and a boulder differ without a second seam; `PLANE` is #263's oriented plane; `TUFT` is #280's.

**All four forms are shipped: billboards (#255), blocks (#264), oriented planes (#263), tufts (#280).**

#### A TUFT splits "does it stand up" from "does its art leave the ground" (#280, 2026-08-15)

The dev's ask was *"I want grass to pop up a bit as well, have a tiny bit of 3D presence, similar to unit sprites… flowers and clover… on their respective tiles."*

**A cell's top face has THREE possible answers, and a tuft is what forced the third.** The meshlib generator bakes a FLAT tile's own art, and a standing prop's face as the bare kind base — the ground it stands on, so a tree is drawn once rather than also lying flat under itself. A tuft is a prop by that rule, but the kind base is the wrong ground for it: those bases are the Stage-0 generated set (grass is a muted olive) while the sheet's grass is a bright green, so a tuft cell would read as a *patch* among its neighbours. So a tuft's face is **generated from the tile itself** — its own field colour, sparsely speckled in its own other colours. Same technique as a prop's generated faces (#274), same rule that only measured colours are worn, and it needs no *"which tile is this one's base?"* relationship.

*(A first pass instead kept a tuft's whole art baked, on the theory that a tuft is still ground — the dev's feel-check killed it in one line: drawing the flowers flat AND standing them up "looks very silly", which is #255's double-render in miniature. The predicate that split had introduced was deleted with it.)*

#### A tuft is ONE SPRITE PER PLANT, because a top-down tile's y is DEPTH

The first build stood the whole tile up as one quad, and the dev's feel-check found two things wrong with it at once — one obvious and one structural.

The obvious one: **the green behind the flowers stood up with them**, so the board grew squares with pictures of flowers on them. The fix is to key the background out, and the reason it does not need the *which tile is this one's base?* relationship the form ruling above avoids is that **the background is the tile's own most common colour**, measured — which holds by construction for a tuft, since ground with something on it is mostly ground (76–96% across the authored tiles, and the same flat green `grass_basic` is 100% made of). `BoardMirror.background_colour` is that one answer and both stacks call it: the mirror keys the colour OUT to cut the plants, the generator FILLS the cell's face with it, so the plants cannot end up standing on a field they were not cut from. **A veto on a mechanism is not a veto on the outcome** — masking was rejected at design time for needing a base tile, and the same result came back out of the tile alone.

The structural one is the keeper. **A ground tile is drawn TOP-DOWN, so a flower's y inside it is depth into the cell, not height.** Standing the rectangle up silently converts every depth into an altitude: two flowers drawn at different depths come out one above the other, with the lower one hanging in the air. *This is the same reading error #263 made with the foreshortened `fence_ver` pieces, and it is worth stating as a general rule — **before standing any ground art up, ask what its vertical axis MEANS.***

So a tuft decomposes its tile: background keyed out, what remains split into connected clusters, and **each cluster stands up at its own place in the cell** — x from its centre column, z from its **bottom row**, because in a top-down drawing the lowest drawn pixel is where the plant meets the ground. Each is planted on its own base, so every plant touches the tile.

Two consequences worth knowing:

- **Only clusters above `BoardMirror.TUFT_MIN_CLUSTER_PIXELS` stand up**, and the threshold is measured rather than picked: the shipped sheet's clusters are 2-px specks or 23-px-plus objects with nothing in between. A speck loses nothing by staying flat, because the tile keeps its full bake — it is still drawn, just not duplicated. Standing every speck up as well is [#311](https://github.com/Phaazoid/Godoiosis/issues/311), and needs one mesh per cell plus a per-quad billboard to stay affordable, because a whole-mesh billboard would swing the plants around the cell centre as the camera orbits.
- **`grass_clover` is not a tuft**, and that is the art's own answer rather than a design call: its content is five 2-pixel dots. It is grass speckle, not clover.

#### A tuft is planted PER PLANT, because a corner cell has no one surface ([#342](https://github.com/Phaazoid/Godoiosis/issues/342), 2026-08-25)

Every other prop is one object standing at `BoardSpace.surface_point` — the cell's surface at its centre, which is all a one-body prop can be asked about. **A tuft is the exception, and it is exactly the exception #427's corner tool made visible:** its plants are spread across the square, and a square with four independent corner heights is not level under them. Planted against the centre, the plants toward the high side are buried in their own ground and the ones toward the low side hang over it.

Each cluster therefore reads **`BoardSpace.surface_height_at` at its own point** — the same answer a sliding sprite reads, so the plant and the tumble agree about where the ground is. It stays **upright** rather than tilting with the face: these are `BILLBOARD_FIXED_Y` sprites and a plant grows up whatever the hill does, which is why `surface_transform` — the seam #342 was filed predicting — is the wrong one. Exactly zero lift on a level cell, so nothing on a flat board moves.

Its twin is a rule about every prop, not about tufts: **a prop follows its ground.** `_reconcile_prop` early-outs on identity, and that identity was the TILE alone until #342 — so moving the ground under a rock, a tree or a flowerbed left it where it was sown. #471's law one store along; the identity carries the cell's corners now, and a corner change REBUILDS rather than re-places, because a tuft has no single position to move.

`BoardMirror.tuft_scale` is the Objects-tab knob (#272; it was a Look knob until then) — a real one, because a tuft is a runtime `Sprite3D` unlike the baked block props. It scales through **`pixel_size`, never node scale** (a Y-billboard rebuilds its basis from the camera, and `pixel_size` scales the base offset with it, so a plant shrinks *toward* the tile), it never moves a plant's place in the cell — where a flower grows is not a matter of taste — and its setter re-sizes tufts already standing, since props reconcile only when their tile or their ground changes.

**Tufts are the one prop form that casts no shadow**, and that is a count rather than a look call: `Prolog` paints over a thousand tuft cells against a dozen lamps and trees.

#### The facing is a SET OF EDGES, and it is a second column (#263, 2026-08-15)

`prop_shape` says what form a tile takes; it cannot say which way that form points, so the facing is its own authored column, `wall_edges` — a declared second representation per Law #4, because the two answer different questions. Folding direction into the shape would mean `PLANE_EW` / `PLANE_NS` / `PLANE_CORNER_ES`… for one concept.

**It is a mask of cardinal edges, not a yaw**, because the pieces an artist draws include corners and a corner reaches *two* directions. Each authored edge becomes a half-length slab from the cell centre out to that edge, so **a straight run is two collinear halves — one wall — and a corner is two perpendicular halves — an L. One rule, no corner special case**, and it falls out that each half wears the matching half of its tile's art, so a straight run reassembles the whole sprite un-squashed.

**The facing is per-TILE, and the payoff is that nothing at runtime holds a yaw**: the meshlib item is already keyed per tile, so the generator bakes each piece's orientation into its own mesh and `BoardMirror` plants a fence with the same `_make_prop_block` it plants a crate with. If a sheet ever needs one generic fence tile placed in both axes, the override belongs in the reader (`GridUtils.wall_edges_at_cell`), not in a second column — at the cost of that zero-runtime property.

Two things were **measured** on the way, and both reversed an assumption the issue was filed on:

- **Godot's own alternative-tile transform flags cannot serve.** They were the recommended candidate — an existing-but-unused mechanism rather than an invented convention — but no authored board uses one (0 non-zero alternatives in 5,712 cells across all three), the in-game Tile Brush cannot write one, and a transform bit rotates the **2D** sprite too, so it cannot carry a 3D-only facing without drawing a front-on palisade lying on its side.
- **Not every piece's art can be a wall face.** In this sheet the east-west pieces are drawn face-on (15×13, top-aligned) and are worn directly, keeping the #250 rule that the 3D shows the game's tiles. The north-south pieces are drawn edge-on — 7×16, successive posts stacked *down-screen* — which is a top-down foreshortening, not a picture of a wall; on a plane facing east it renders as a tower of logs. Those faces are **generated in the tile's own measured palette**, the same reconciliation #274 already made for solid props.

A plane is also the one prop form NOT sized by its art's opaque bounds: it is thin by definition in the axis it does not run along, so its thickness and height are generator constants. Being baked, they get no live knob at all — the same call `PRISM_PROFILE` records.

##### WHICH slabs wear the tile's own art is a fact about the MATERIAL, not the axis (#554, 2026-08-26)

The bullet above reads as a rule about walls and is a rule about **palisades**: face-on across, foreshortened along. The stone wall the sheet also ships is drawn as a **plan of its footprint in both axes**, so its sprite is a picture of no wall at all — `stone_wall_hor_top` is opaque in 5 of its 16 rows, and worn on a slab it renders as a grey ribbon floating over an invisible one.

So the axis test became **`GridUtils.plane_own_art_edges`**, a mask of the edges whose slab wears the sprite: `EW_EDGES` for a palisade, `0` for masonry, and every other slab takes the generated face. It is keyed on **`Terrain.Kind`**, which is already what this generator asks for *what a tile is made of* — a `ROCK` block wears stone down its sides — so the material question gets one answer rather than a column of its own. The generated face forks the same way: `_prop_side`'s `PLANE` arm draws a running-bond masonry course for `ROCK` and the palisade for everything else, and it is the only shape that forks on kind, because a wall is the only form this sheet draws in more than one material.

**A corner is one patch now, not two.** With no face-on axis, both of a stone corner's slabs share the single generated face — so `_patch_widths_for` had to ask the same question the walk asks, which is why it takes the `TileData` rather than a shape and a mask.

Pinned from both ends, because either alone is blind: `tests/presentation/test_board_mirror.gd` asserts the rule per material (nothing in a running game reads it, so a wrong answer reddens nothing), and **`tests/law/test_a_wall_face_covers_its_slab.gd`** asserts the baked artifact — every slab's art must be opaque over **more than half** its rows, measured off the committed meshlib and the atlas that mesh itself names. Half is a definition of *mostly*, deliberately **not** `PLANE_HEIGHT`, which is a feel value the palisade art happens to match to the row (13/16).

### Block props are GENERATED, not commissioned (#264 + #274, 2026-08-15)

The block form looked blocked on art, and it was — but on *one face*. **The blocker was never the shape: it was that a single 3/4 sprite cannot supply a top face**, and at the board's ~40° pitch you see plenty of top. Everything else was already free: the GridMap stacks, and `gen_lookdev_assets.gd` had built cubes with independent top and side UV rects since Stage 0.

So the generator supplies the missing half. **Every face is generated in that sprite's own measured palette** — planks on a crate, staves on a pot, per-facet stone on a boulder — packed into extra rows of the same composited atlas the ground already uses, so the board is still one texture.

> **The atlas is a PNG on disk as of [#540](https://github.com/Phaazoid/Godoiosis/issues/540) (2026-08-26), reversing "no PNG is written".** That clause was a *rendering* rule dressed as a storage one: what the #250 trap actually forbids is an atlas imported with mipmaps, not an atlas on disk, and the fire sheet three sections up had already shown the answer — author the `.import`. Embedding it turned out to have its own cost. An `Image` sub-resource behind an `ImageTexture` **cannot keep a stable id**: `set_image()` uploads to the RenderingServer and keeps no reference, so `get_image()` rebuilds an anonymous Image and every save mints a fresh one — `lookdev_meshlib.tres` went dirty on any editor save that rewrote it, three times in its own history, for an edit nobody made. **Only an `ext_resource` survives a save**, and the only Texture2D that is one is a file. `Art/LookDev/ground_atlas_0.png` (one per tileset source) imports lossless, no mipmaps, `detect_3d/compress_to=0` and `process/fix_alpha_border=0` — the last because it rewrites the RGB of transparent pixels, invisible under NEAREST filtering with an alpha scissor but enough to make the imported atlas differ from the composed one, which is what `_write_atlas` compares to catch a stale import. Pinned by `tests/law/test_no_embedded_image_resources.gd`. It also costs 458 KB less in the pack and 650 KB less in the repo, the atlas compressing ~22:1 as PNG against the raw RGBA8 an embedded Image ships.

**The sides started as the sprite and that lasted one playtest (#274).** A sprite cannot *wrap*, so #264 put the whole sprite on every facet — and the dev's verdict was precise: *"the rocks and the pots need it most, their sprites do not map to their models."* A crate is a box, so a box-shaped drawing lands on its four sides tolerably; a ten-sided barrel rendered as **ten overlapping copies of itself**. Generating the strip fixes it structurally rather than cosmetically:

- **Each facet owns a distinct, equal, contiguous slice of the side strip**, inset by its own half texel. One UV rule for both prisms — whether the slices read as a continuous wrap (a pot) or as separate stone faces (a boulder) is decided by the *texture*, not by the mesh code.
- A prism's strip is therefore one atlas patch **per facet**: slicing a single 16px patch into ten facets would leave 1.6 texels each.
- **No baked shading.** The material is shaded, the sun is real, and a prism's facet normals already differ, so lighting does that work and the albedo stays flat — the convention every look-dev texture holds to.

**This is the one place the 3D deliberately does NOT show the game's tile art**, which is worth declaring because #250's whole finding was the opposite. The reconciliation is that the *colours are still measured from that art* — a prop's palette is its own sprite's dominant shades, read back rather than invented — and that a volumetric object genuinely cannot wear one 3/4 drawing, which #264 measured rather than assumed. A billboard is the one form a sprite maps onto correctly, and billboards still wear theirs.

**Material is not yet a question the data can answer.** Crate and chest are both `CUBE` and share one plank recipe; they are both wooden boxes, so that is honest until something complains. Note that `terrain_type` **cannot** be pressed into service for it — barrel, chest, rock and lantern all carry `Terrain.Kind.ROCK` and crate carries no kind at all, the same counterexample set that stopped `stands_up` being inferred from kind in #255.

**The `ROUND` prop was authored `pot` until 2026-08-15**, and several dev quotes above still say so. The profile made it read as a barrel and he kept the reading rather than re-tuning toward a pot: *"those pots resemble barrels now. And I'm going to make the call — that's actually better. Pots were just a random texture in the sheet I was using. Barrels make more sense in the context."* Worth recording because it is the tile that changed to match the geometry, not the other way round — **the generated form settled what the content was**, which is a thing procedural greybox can do and a commission cannot.

Two rules worth keeping:

- **The mesh is sized by the art's OPAQUE BOUNDS, not by the cell.** A rock is 32% transparent, so a cell-wide cube around it is mostly air. Measuring makes a small sprite a small object with no tuned offset anywhere. **A billboard is PLANTED by the same measurement** — a tile region may carry transparent padding (the lantern's art stops 5 rows above its region's bottom edge), and planting by the region left the visible lamp floating a third of a cell for as long as billboards have existed. One rule, `BoardMirror.opaque_bounds`, read by both stacks.
- **A prism's silhouette is a PROFILE**, a list of (height fraction, radius fraction) rings, not a single taper. Two rings make a truncated cone standing on its widest part, which is the opposite of a vessel — a pot is narrow at the foot, widest at the belly and drawn back in at the rim (dev, 2026-08-15: *"the geometry needs to come back to a central point on the bottom to make them look round"*). The numbers are a feel value with no runtime knob, because the mesh is baked: rounder is a line in the table plus a regenerate.
- **The footprint is square.** A 3/4 drawing says nothing about depth, so inventing a second number would be a guess dressed as a measurement.
- **But the art gives a HEIGHT only where the art is drawn UPRIGHT** (#323, 2026-08-16), and that is the second declared exception to art-sizing beside the plane's. A crate and a barrel are drawn upright, so their vertical extent is a height. The `FACETED` rock is a top-down cluster of boulders, so its 16 rows are mostly **depth into the cell** — read as height they build a solid 1.0 cells tall on a 0.875 footprint, i.e. taller than it is wide, which is *why* the dev's word for it was "column" (*"too much like columns, not blocky/crunchy enough"*). A shape whose art cannot answer *how tall* declares it instead: `FACETED_HEIGHT_OF_WIDTH` is a proportion of the measured footprint. **This is the third time the same misreading has cost a build** — #263's foreshortened `fence_ver`, #280's flowerbed, now this — and the first time it landed on a solid's height rather than on standing art up. The general rule is already stated above under the tuft; what this adds is that it applies to a mesh's *proportions*, not only to decomposition.

**What a boulder needs beyond a profile (#323).** Two rings could not be fixed by jitter alone, because the irregularity was in the wrong axis: the wobble was drawn once per facet and reused down the whole solid on purpose, so the footprint was an irregular polygon *extruded straight up* — every facet edge dead vertical. `PRISM_JITTER` is now three fractions per shape — **facet** (the original per-facet radius wobble), **ring** (a further wobble drawn per facet *per ring*, which is what tilts the edges off vertical), and **angle** (facets no longer evenly spaced around the axis). A barrel takes none of it; turned things are regular by definition. Fewer facets is the other half of "blocky": the rock went 7 → 6, which incidentally fixed a wrap seam, since `_prop_side` walks tones as `1 + (facet * 2) % 3` and at 7 facets that put the same tone on both sides of the seam.

**This is the project's normal pipeline, not a compromise** — every look-dev ground texture is RNG-generated too, and that is the art that passed Stage 0's gate. The honest ceiling is coherent greybox: a generated rock reads as a faceted lump, not as a rock someone drew. **When an artist arrives the textures swap and the meshes stay**, so the commission line below still holds — it is now a quality upgrade rather than a prerequisite.

**Consequence for the commission**: the sprite sheet must say, per prop, which form it is — and blocky props are best ordered as a top + side pair rather than as a single 3/4 view. That is cheap to specify up front and expensive to retrofit, which is exactly the bar the two conventions above are held to.

---

## Tier 1 — finishing the HD-2D canon

Proven Squeenix-style ingredients Stage 0 didn't include. All stage-5 material.

- Particles: dust motes in light shafts, embers above BLAZE, drifting leaves/pollen, low ground-fog cards. **Filed 2026-08-26 as [#551](https://github.com/Phaazoid/Godoiosis/issues/551), scoped to the AMBIENT half only** — motes, pollen/leaves, ground-fog cards — because every other clause already has an owner: embers + smoke + haze over BLAZE is [#455](https://github.com/Phaazoid/Godoiosis/issues/455)'s (which calls it *"the single most-earned item here"*), rain and snow are [#277](https://github.com/Phaazoid/Godoiosis/issues/277)'s, which punts its own particles forward in as many words, tile debris is [#523](https://github.com/Phaazoid/Godoiosis/issues/523)'s, and the unit channel is [#358](https://github.com/Phaazoid/Godoiosis/issues/358)'s. The measured state that made it P1 rather than someday: **there is not one particle node in the repo** — no `GPUParticles3D`, `CPUParticles3D` or `ParticleProcessMaterial` outside `addons/` — so four open tickets each want a particle and not one of them has anywhere to put it. Whichever builds first invents that answer on its way to something else, which is Law #4 failing in its usual way: late, and once there are two.
- God rays through interior windows (volumetric fog + tight shafts).
- Animated pixel water with real reflections and foam edges (Octopath 2's showpiece). **[#552](https://github.com/Phaazoid/Godoiosis/issues/552) slice 1 SHIPPED 2026-08-26 — a moving, lit, legible surface; foam/shoreline and reflection are separate and #552 stays open.** Three things it settled. **(1) The fork it existed to answer: a cell's own SURFACE is its meshlib item, a MARKER is a per-cell node** ([#324](https://github.com/Phaazoid/Godoiosis/issues/324)'s fire) — so `Scenes/LookDev/water.gdshader` replaces the water items' top material, the GridMap batches every water cell into one draw, and the waves run off **world XZ** so a lake reads as one body of water rather than as N tiles rippling privately. This is the codebase's second `.gdshader` and the convention the next one copies: lit `shader_type spatial` (never `unshaded`, which is what makes the mood presets grade it with no table row), OPAQUE, and it **perturbs `NORMAL` without ever displacing a vertex** — `BoardSpace.lie_on`, `surface_point`, the hover bracket and every markup quad assume a flat top face at a known Y. **(2) [#543](https://github.com/Phaazoid/Godoiosis/issues/543)'s legibility raise is answered from the RULES' own flag** — the generator bakes `deep` from the tile's `walkable`, and the base colours are the two tiles' authored `modulate`, which reaches the flat view too (see [terrain.md](terrain.md) → *Water — shallow vs deep*). Measured before the fix and worth keeping: the sheet painted **both** tiles the identical `(77, 155, 230)`. **(3) Water stopped wearing its own surface down its sides** — the one kind that did — and now pairs a top with a generated `water_side.png`, as `grass_top`/`dirt_side` and `stone_top`/`stone_side` always have. Two things it deliberately did not do. A **FROZEN** cell shows moving water under a flat ice icon (`OverlayMirror` mirrors FROZEN as a marker, per [#455](https://github.com/Phaazoid/Godoiosis/issues/455)'s *"genuinely flat"*); the meshlib route carries no per-cell state, so the fix is the same board-sized water mask the foam pass needs — one channel saying *frozen*, and the surface holds still and goes pale. And the shader draws its own faint **cell seam**, because a lake driven off world position erases the grid, and on water the hover bracket is otherwise the only thing saying where a tile ends — `BoardSpace.SIDE_RIM` is built to make that seam invisible and SSAO cannot see a coplanar boundary. Thirteen `GameKnobs` rows tune all of it, as global shader uniforms rather than material parameters, because writing to the meshlib's material would mutate a generated artifact at runtime.
- **Slice 1b (2026-08-27) fixed two knobs that moved nothing, and they turned out to be one problem with the ice read.** `Body shade` ran only on side-facing geometry in surface 0 — the four RIM quads, and `BoardSpace.SIDE_RIM` is `0.004`, a rim [#559](https://github.com/Phaazoid/Godoiosis/issues/559) built to be invisible — while the walls in surface 1 wore a plain material the shader never saw; the shader wears BOTH surfaces now and forks on the world normal, taking a second sampler (`body_tex`) because the two surfaces carry different UVs and one sampler would smear the whole tilesheet down every wall. `Shallow bed` was per-ART-PIXEL noise at ±20% on the water's own colour: below what the eye resolves at a playing distance, and a bed made by tinting the water can never look like a bottom. **The compositing ORDER was half of it** — the mottle multiplied the surface bands, so it read as grain painted over the highlights rather than as something underneath. **And that is the ice fix, not a separate one.** Contrast, ripple and specular all make bright hard highlights, so the only expressive channels the first slice shipped could push a pale cyan surface further toward ice and nowhere else; what separates shallow water from a frozen pane is that you see the BOTTOM through it, the bottom is WARM, and **caustics travel over a bed that stays still** — ice moves all of itself or none of it. So the bed is a real layer now (its own authored colour, a pebble grain in art pixels, a ridged caustic net whose speed derives from the wave speed) composited UNDER the bands. **Worth stating for the later slices: reflection cannot rescue an ice read, it deepens one** — that is [#455](https://github.com/Phaazoid/Godoiosis/issues/455)'s own point, that SSR is what would make FROZEN read as a literal mirror.
- **Slice 1c (2026-08-27) made every water dial PER TYPE, and the lesson generalises past water.** Shallow's character was a fixed RATIO off deep's — wave scale ×1.7, speed ×1.35, body shade ×0.6 — living in the shader as constants, justified at the time as *"the character split, not the pace"*: the knobs set how fast the pair goes, these only say which is busier. **That is a dial you cannot turn.** One Wave speed moved both types together, so *shallow choppy, deep glassy* was unrepresentable, and the dev found it the moment he tried (*"we need these dials separate for the different water types"*). **A RATIO BETWEEN TWO AUTHORED THINGS IS ITSELF AN AUTHORED THING** — burying it in a const does not stop it being a feel value, it makes it a feel value with no surface, which is the tuning rule violated while appearing to follow it. Eight values split into deep/shallow pairs (the six surface ones plus body shade and cell seam), the five bed/caustic knobs renamed with `shallow_` since they were already shallow-only by nature, and the constants **deleted** rather than kept as a fallback — a deleted seam cannot drift back. The shader picks with `mix(shallow, deep, deep)`, which is exact because `deep` is baked 0 or 1 and stays sensible if a fractional depth is ever authored. Two things worth carrying: the split shipped as a **visual no-op** (each shallow default is the old ratio already folded in, so the board looked identical and only the panel changed — his tuned values are authored content and a split that silently re-tunes them loses his evening), and **cell seam splitting was his call over mine** — the bed's mottle already breaks shallow water up while a deep expanse has nothing else going on, so the two have genuinely different grid-legibility needs. Twenty-one rows, and Water took its own sub-tab at that size.
- **Slice 2 (2026-08-27) is the shoreline, and the real deliverable is the board-sized water mask under it.** [#552](https://github.com/Phaazoid/Godoiosis/issues/552) objected to keeping water a MeshLibrary item precisely because *"a foam edge has to know its neighbours, and a meshlib item knows nothing about the cell next to it"* — the dev took the meshlib route anyway, and this is where that debt comes due. **`BoardMirror._rebuild_water_mask` builds one texel per cell, white where that cell is water**, pushed as a global `sampler2D` beside the tuning globals; the shader turns a world position into a texel with a single `vec4` rect, because `BoardSpace.CELL_SIZE` is 1.0 and a 2D cell's `y` **is** the world `z`. **The elegant part is free: texel centres land on CELL centres, so `filter_linear` hands over a distance-to-shore ramp — 1.0 well inside the water, exactly 0.5 on the shared edge with land — with no distance field baked and no neighbour walk anywhere.** `repeat_disable` clamps, so water running off the board meets its own value and does not foam against the void. It rebuilds from **both** sync doors (`sync` and `sync_cells`), since only one of those is on the path a brush edit takes. Four knobs, per type per slice 1c's rule, and the foam colour's **alpha is its strength** — a surf hue and how much of it there is are one decision, not two. The band breathes on the wave field the shader already computes, because a static band is a painted outline rather than surf, and it composites **after** the cell seam on purpose: the seam draws every boundary, and a grid line through the surf is what a shore must not have. **Declared 3D-only ([#292](https://github.com/Phaazoid/Godoiosis/issues/292), with [#285](https://github.com/Phaazoid/Godoiosis/issues/285) as the model):** the flat view's water is a tile *pick* and a shoreline is a sub-tile gradient no tile pick can express, and that view already carries the one distinction the rules make. Two things it cost. **The type-ambiguity law from 1c had to grow a category** — the mask names no water type and never can — so `BOARD_GLOBALS` is a declared exemption whose membership is asserted in *both* directions, since a hole a future knob can fall into unnamed is the law quietly deleted. And the three cases that each parsed `global uniform` lines for themselves all broke at once on the sampler's `: filter_linear` hints, which is what forced them onto one helper. **Measured, and it invalidated a test that was passing:** headless, `ImageTexture.get_image()` answers the FIRST image the texture was ever given and never changes — a second `set_image`, even at a different size, still reads back the original. Two mask cases were green because each ran on a fresh texture; the case that mattered (*the board changed, did the mask follow*) could not see its own subject until the assertions moved to the `Image` at the push funnel. **What this unblocks:** the FROZEN-over-moving-water item three paragraphs up wanted exactly this mask and now needs only a channel; so does distance-from-shore for [#578](https://github.com/Phaazoid/Godoiosis/issues/578).
- Weather: rain/snow with wet-tile specular response; per-preset lighting already exists to receive it.
- Per-map color grades; the four look-dev presets were the seed and are now **real** ([#253](https://github.com/Phaazoid/Godoiosis/issues/253) parts 1 and 3, 2026-08-15). The Moods tab saves named `LookPreset`s to `Resources/LookPresets/`, and twelve ship: Day / Sunset / Night / Overcast ported from `look_dev.gd` — whose own copy [#393](https://github.com/Phaazoid/Godoiosis/issues/393) then DELETED, the look-dev scene resolving those four by NAME through `LookKnobs` instead, so the seed is not a fork — the un-tamed **Forest Fire** that got #212 filed, Dawn, Storm, a deliberately-overcooked **Diorama** that exists to show what the tilt-shift knobs do, and the four **Opus** grades below. Dev rulings, 2026-08-14/15: a preset stores the **whole table** (a diff-preset would let a later scene re-tune silently re-skin every mission that never mentioned that knob) — and it stores **scene mood, not game settings**, so camera *framing* rides along while camera handling, board markup and prop geometry do not (all three have since LEFT the look table outright — #272, then #373). **Part 2 landed the same day and CLOSED #253**: `ScenarioData.look_preset` names the board’s look, `battle3d` applies it on every board load, and `Resources/DefaultLook.tres` is what a board wears when it names nothing — so `Battle3D.tscn`’s inline values have stopped being a second source of truth for "what does this board look like". Everything ABOVE that base layer — weather overriding it, battle flashes interrupting and unwinding — is [#278](https://github.com/Phaazoid/Godoiosis/issues/278), and weather itself is [#277](https://github.com/Phaazoid/Godoiosis/issues/277).
- Camera micro-sway; tasteful, deterministic impact shake. **Not a ticket of its own — noted onto [#520](https://github.com/Phaazoid/Godoiosis/issues/520) (the battle-zoom camera director) on 2026-08-26**, whose scope already named *a shake* in one word, with a shorter note on [#534](https://github.com/Phaazoid/Godoiosis/issues/534) where the post-turn pass meets [#188](https://github.com/Phaazoid/Godoiosis/issues/188)'s ask for the same feedback from the unit side. `CameraRig3D` has neither today — no shake, no sway, no noise source at all — and the only "shake" in the codebase is `UnitVisuals`' 2D sprite tween, which is a unit effect and not a starting point for a camera one. Two things the wording carries: *deterministic* is load-bearing under Law #1 (a curve over time, never a noise roll), and **micro-sway is the half nobody had named** — it is a *resting* behaviour, so it inherits #519's CINEMATIC/BOARD profile fork rather than living only inside a zoom.
- Emissive pixel art (see Conventions above).

## Tier 2 — modern-3D tricks on a pixel diorama

- **Decals as persistent battle scars**: scorch after BLAZE, frost creep for CHILLED, footprints in mud/snow lasting the mission. Cheap, stateful storytelling.
- **SSR so FROZEN water is literally a mirror** — beauty that *communicates the state*.
- Heat-haze distortion above fire and torches (screen-texture displacement).
- Wind sway on foliage sprites — gusts synced to the *Gust* carving.
- Drifting cloud shadows (animated fog-density or projected noise).
- Hovered-unit rim light replacing the 2D modulate highlight.
- Snap-orbit transitions with a settle/ease; light as UI (the aim pulse becomes emissive glow + a faint point light on targeted units).
- Normal-mapped sprites (see Conventions above).

## Tier 3 — Iosis-only: systems made visible

The tier nobody else can copy, because it renders systems Iosis alone has.

- **Elemental states as materiality.** The paired-state pattern (marker + clock) gives clean enter/exit hooks for material transitions: WET darkens and sheens, FROZEN mirrors, CHILLED frosts outward with breath-puffs on units standing in it, SHOCK arcs across cell borders, BLAZE gets embers + smoke + haze. Thermal-loop reactions become staged set-pieces — temp-shock a crack-flash and steam burst, douse a hiss, grass ignition creeping tile to tile *in the direction it actually propagated* (the resolver knows).
- **Render the future.** Law #2 means the resolver computes the exact post-execution world — every other tactics game's preview is RNG soup; ours is truth. A hold-to-peek "spectral diorama" of the resolved end state (ghost sprites, ghost fires, ghost outcomes staged on the board) is a marketing-grade feature whose data structure (`ResolvedPlan`) already exists. The strongest single idea on this wall.
- **Alchemy as art direction.** Glowing ground sigils for channeled carvings (aura-colored, per-affinity palettes), channel-threads of light from alchemist to carving — and the thesis-level version: the classical alchemical stages are *color* stages (blackening → whitening → yellowing → **reddening: iosis itself**). A mission or campaign arc whose grading walks that sequence makes the game's name its visual spine. **This one has left the wall: `Opus 1 Nigredo` / `2 Albedo` / `3 Citrinitas` / `4 Rubedo` ship as real presets (#253 part 3), so the question is no longer "would it read" but "does it" — load them in order and look.** They are grades only; the per-affinity sigils and channel-threads above are untouched.
- **Will and Crisis**: entering Crisis desaturates the world for a beat while the berserker alone stays vivid (screen grade + per-sprite exemption).
- **The downed clock** as a fading ring decal under the body — readable and moody. **It now has a plain
  readout to earn its way past** ([#322](https://github.com/Phaazoid/Godoiosis/issues/322),
  2026-08-21): the turns left are digits beside the downed glyph in the head channel. So this is the
  #259 shape — a built number owed a presentation — with one question attached, since a ring under
  the body would put *what this unit IS* in the channel #346 gave to *what this INTERACTION is
  about*.
- **Squad cohesion** drawn as a soft light tether/field (the `SquadCohesion.field` is already computed; render it instead of tile fills).
- **Zones**: capture/extraction as diegetic alchemical light columns, intensity tracking progress.
- **Turn count drives the sun** — dawn on turn 1, dusk by turn 12; time pressure made visible. (Pure presentation; the rules never read the clock.)
- **The shove-off-cliff kill is REAL as of #259 (2026-08-20)** — it still owes this earned presentation: a slow focus-racked camera tilt, the tilt-shift rig doing dramatic work.

## Tier 4 — the far wall (flagged as such)

- Battle intros zooming from a tabletop map into the living diorama; UI as parchment-and-brass instruments framing it (the "toy soldiers" conceit).
- **Defeat as the diorama reveal — the twin of the intro above (scratchpad, 2026-08-19).** Losing a battle pulls the camera *out*, and out, and out, until the battlefield is seen to **be** a diorama: a strategist stands over the table, mulling a plan that did not work. The player is then offered **watch the replay** (to study the failure) or **try again**. Two things make this cheaper than it sounds and one makes it expensive. Cheap: the HD-2D stack already *literally renders the battle as a diorama*, so the reveal is a camera move rather than a new asset class — `CameraRig3D` is the rig, and `MissionEndBanner` is the surface that already owns the defeat moment; the "watch the failure" half is a straight consumer of [#209](https://github.com/Phaazoid/Godoiosis/issues/209)'s replay substrate and buys nothing until that exists. Expensive: **the strategist is a character in a scene**, i.e. real art and a real staging question, which is what keeps this on the far wall rather than in Tier 3 with the other camera work. **The story value is the part to preserve if it is ever cut down**: every defeat reframed as *a plan failing on a table* rather than as your people dying — which is a tonal claim about what a loss means, and it costs nothing to honor in wording long before the camera move exists.
- Fog-of-war as physical volumetric fog carved by torch/unit light — needs vision rules that don't exist yet.
- FROZEN reflections showing *planned* ghost positions instead of the present — deliciously on-theme (the ice previews the plan), possibly too weird. Kept on the wall per instructions.
- Photo mode — the look-dev scene's free camera and per-ingredient toggles are accidentally 80% of one already.

---

## The reference shelf (mooch deliberately)

- **Octopath Traveler I/II** — the post stack itself (DoF + selective bloom), OT2's water as the bar for Tier 1, and the map→battle transition framing.
- **Triangle Strategy** (dev-requested 2026-08-12) — *the tactical sibling*, closest commercial cousin to Iosis and the richest mine here:
  - **Elevation-heavy battle maps** — proof HD-2D handles real tactical verticality (multi-story towns, cliffs, ladders); the direct reference for #116's presentation.
  - **Elemental terrain interplay** — fire spreads, ice melts, rain leaves puddles that conduct lightning: the nearest shipped VFX language for the thermal loop, quickdry/chill/temp-shock included. Study how it *telegraphs* states at tactical camera distance.
  - **The camera pair** — orbiting diorama view plus a pulled-back tactical overview toggle. That overview is philosophically our 2D sandbox living inside the 3D engine; a cheap readability win to keep on the wall.
  - **UI anchored in 3D** — floating unit banners, the turn-order ribbon, damage forecasts pinned above sprites: stage-4 reference material.
  - **Shove-off-ledge presentation** — falls and height damage staged legibly; again #116.
- **FFT / Tactics Ogre / Fell Seal** — the 2D-elevation trick catalog (sprite offsets, stacked tile sides, drop shadows), i.e. the evidence base for the dev's "a Z level is just a variable" ruling above.

## Mobile & quality tiers (the Forward+ question, answered 2026-08-12)

Godot supports per-platform renderer overrides (`rendering_method.mobile`), so the Forward+ switch costs one line to undo *per platform*. The real constraint is the stack: as of 4.7, volumetric fog / SSR / SSAO are Forward+-only, while glow and DoF (and, likely, decals) survive on the Mobile renderer — **re-verify per feature at port time**. The mitigation is work PC scaling wants anyway: the look-dev scene's per-ingredient toggles are a quality-tier system in embryo (a "low" tier fakes fog with billboard cards, drops SSR/SSAO, keeps glow + DoF). Octopath's own mobile release proves the look scales down; a 14×14 diorama is tiny by its standards. Steam Deck is the nearer target and runs Forward+ natively.
