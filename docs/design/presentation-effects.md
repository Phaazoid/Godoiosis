# Presentation & effects — the HD-2D idea wall

**Status: an idea wall plus two locked decisions.** Solicited by the dev on 2026-08-12, the day Stage 0 (#203) passed its GO gate: *"a full thought experiment, all ideas on the wall."* Nothing below the Decisions section is a commitment — it is the candidate pool for #176's stage 5 and beyond, kept so it can't evaporate from chat. The look-dev scene (`Scenes/LookDev/LookDev.tscn`) is the standing playground where any of it gets prototyped before it's real — and since #212 (2026-08-15) the **Moods tab** in the dev-tools window tunes the *shipping* view live, so a value on this wall can be judged on a real board rather than in the diorama.

**Canon checked through #386 (2026-08-19).**

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

**A global is the DEFAULT, an object may override it** (dev, 2026-08-16). `BoardMirror` is the only
place that resolves the two, so nothing downstream knows a global exists.

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
- **Markup LIES ON the surface it marks; anything that STANDS on one stays upright ([#281](https://github.com/Phaazoid/Godoiosis/issues/281), 2026-08-15).** Dev: *"they should be flat against the ground, even on slopes."* `BoardSpace.surface_transform` is the one answer to how a flat thing lies on a cell — position *and* orientation, with `surface_point` as its origin so the two halves cannot drift. The tilt derives from `Terrain.rise_direction`, the same call the ramp wedge's own yaw comes from, so ground and markup can never disagree about which way a slope climbs. Units, flames and props keep reading `surface_point`, and billboards and the hover bracket (a cell *volume*) are declared non-tilting. **The tilt carries a stretch**: a ramp face is 1.414 cells long, so markup that only rotated would leave it bare at both edges — stretching is also what makes an arrow foreshorten exactly as the ground under it does. Both values are derived geometry, not taste, so neither is a Look knob.
- **Board clicks skip events entirely.** The picker calls `game._on_left_click` / `_on_right_click` (the dispatchers game.gd's own `_unhandled_input` only feeds), and `game.board_input_delegated` stands the 2D derivation down so one physical click cannot act twice. That bool is the whole arc's only game.gd input edit; unset, the flat 2D game is bit-for-bit unchanged — **all hosting mutations are runtime**, never authored into `Main.tscn`.
- The corner PiP survives as a **dev debug view** (F4), not a player-facing mode. The launch-time chooser named above is still stage 4d.
- **A mirror that copies a FLAG inherits every writer of that flag — mirror the QUESTION instead ([#232](https://github.com/Phaazoid/Godoiosis/issues/232), found in play, 2026-08-14).** 4c copied `$MapSprite.visible` to get planning-ghost parity, and `Unit._show_downed_sprite` writes that same flag for an unrelated reason (swapping in the separate downed art) — so going down made a unit vanish from the diorama one line after the mirror had correctly given it the downed pose. The fix is Law #4 at the source: `UnitVisuals.projected` is now declared, so the two questions stop sharing storage. The twin, same commit: the faction tint is set on the **Unit node** and 2D multiplies it down the tree for free, so copying only the child's `modulate` left every enemy un-reddened in 3D — the mirror takes the product. **The general rule for anything polling the 2D: copy what the 2D *renders*, not the field it happens to be stored in.**
- Both of the above were **green under the suite**: `test_downed_and_death_reconcile` asserts the texture swap and passes against a unit nobody can see. Parity tests have to assert what reaches the screen.
- **Draw ORDER is part of the mirror's contract, and the 2D's z-order is the authority for it** (found in play 2026-08-14: freeze icons drew over path arrows and planning ghosts). `BoardOverlays.LAYERS`' `sort` had terrain state at the top of its range while the 2D puts it at `TERRAIN_Z_INDEX` — *above the board, below unit sprites* — with arrows above that. The two orders are now tied together by a test that reads both sides, so retuning a sort is free but **contradicting the 2D reds**. Beneath that sits a structural rule the 3D had simply been missing: **`BoardOverlays.UNIT_RENDER_PRIORITY` puts every unit sprite above every overlay layer by construction** — the twin of the 2D's "tile overlays sit below `Unit.BASE_SPRITE_INDEX`". Planning ghosts are `UnitSprite3D`s, so they inherit it; before it they were priority 0 and *arrows* drew over them too, which nobody had reported yet.
- **Anything that starts writing depth must first be checked for COPLANARITY — the two failure modes are opposite, and fixing one hands you the other** (fire, 2026-08-14, twice in one day). A flame that did *not* write depth lost to whatever did, which is how a body lying in fire swallowed it. Switching it to `TRANSPARENCY_ALPHA_DEPTH_PRE_PASS` fixed that and immediately produced the worst z-fighting on the board, because a centred 0.7-tall quad lifted 0.35 has its **bottom edge at exactly y = 0** — coplanar with the tile it stands on, seen at the grazing angle a pitched camera looks from. Harmless for as long as it stayed out of the depth buffer. The clearance is now a **clamp** (`BoardMirror.flame_base_lift`), not a default, so no authored knob can put the quad back in the ground; that is the flame's twin of `BoardOverlays.fill_lift`, and **every new depth-writing surface owes the same check**. The residual — a flame and a unit sprite are both camera-facing planes through the same point, so they are coplanar by construction wherever a unit stands in fire — outlived both attempts, and **it is not a trade between two artefacts, which is what this bullet claimed until 2026-08-15 ([#298](https://github.com/Phaazoid/Godoiosis/issues/298))**. Both are `BILLBOARD_FIXED_Y` quads whose origins share the cell's X/Z, and a Y-billboard yaws about its own origin — so they are not two planes sitting close together, they are the **same plane**, and the flame fights the sprite whichever way `flame_writes_depth` is set. Swallowed ([#243](https://github.com/Phaazoid/Godoiosis/issues/243), closed — it stopped reproducing) versus speckled (#298, live) is which way per-fragment precision fell, not a mode anyone picks. `flame_lift` reaches neither, because **Y is the one axis that cannot separate two vertical coplanar planes** — so the fix has to be geometry that separates them: an offset toward the camera, non-billboarded fire, or the particle version already on the Tier 1 wall below. **#324 took the first of those, and the reason it is a fix rather than a number is that it is recomputed every frame from the LIVE camera** — a baked offset is a guess about where the viewer is, and free orbit is exactly the thing that invalidates a guess. See *Fire is an effect, not a sprite* below.

### The camera contract, amended: free orbit rests, Q/E realign (#176 stage 4d, 2026-08-14)

The original contract locked **"yaw snapping in 90° steps"**. The dev asked the sharper question — *do we need to snap to anything at all?* — and the answer from the code was no:

- **Sprite facing never depended on it.** `UnitSprite3D.facing_flip_for` judges each step against the **live** camera basis, so it is correct at any continuous yaw today; the future `frame_for(unit_facing, camera_yaw)` seam quantizes the *relative* angle internally.
- **"Units can't hide behind terrain" is helped, not threatened** — free rotation reaches every angle rather than four.
- The genuine cost is **texel shimmer at off-axis rest**, which is aesthetic and about the *resting* pose, not about what happens mid-drag.

**So: yaw orbits freely and rests wherever the player leaves it; Q/E step to the next 90° detent, realigning in one press.** The crisp axis-aligned pose is now an affordance rather than a cage. A corollary the amendment forced: facing was only re-judged when a unit *moved*, so any rotation left standing sprites facing the old angle — snapping never protected against that either; the mirror now re-judges on camera turn.

Bindings are knobs, not canon: `orbit_button` was built to default to middle-drag so right-click could keep its press-to-cancel meaning, with the click/drag threshold built so flipping it was an inspector change. **The dev flipped it to right-drag after playing it (2026-08-14)** — *"you don't need to drag the mouse when canceling orders, so the overlap is a non issue"* — which is the knob working as intended; cancel now fires on release-under-slop, and moving the binding back moves it back to press.

Also settled here: **the camera follows the action by mirroring the 2D camera** (which `AIController` already pans to each acting squad) rather than growing a second follow seam — so `Pacing.AI_SQUAD_PAN` keeps one number and one reader, and the 3D inherits the 2D's easing exactly. The gate is `ai_locked`, deliberately *not* the broader board lock, which also covers menus. **Entering an AI turn also squares the camera up** to the nearest detent (dev call, 2026-08-14): free orbit is the player's, but an enemy phase reads on an axis-aligned board. It fires on the *edge* into the turn rather than every frame, so the day orbit is allowed to stay live under an AI turn it squares up once instead of fighting the drag.

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

**That diff used to be a whole-board walk, and the property it bought is now a law instead ([#319](https://github.com/Phaazoid/Godoiosis/issues/319), 2026-08-16).** Re-reading everything every frame caught every writer with *no trigger site to remember*, which was the point — and it cost O(board) per frame, i.e. a whole 60fps budget on Prolog before anyone painted anything. The trade: writes now announce which cells moved (`BoardGrid.paint`/`erase`/`reset`, `BoardHeights.set_cell`), the poll reconciles only those, and the cost goes flat in board size. **The "no trigger site" guarantee did not survive that and was not meant to** — `tests/law/test_board_writes_announce.gd` carries it now, and `tile_map_data` is the declared exception a door cannot cover (a bulk property write, made safe by `board_loaded` → `rebuild()`). Numbers and the two traps — a lowered floor still full-syncs; the board rect grows in place but shrinks by re-deriving — are in [`docs/performance.md`](../performance.md).

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

Two smaller rulings ride along. The icon is the **2D's own**, not a 3D copy, so a re-drawn Cover reaches both views — which is also why its `detect_3d/compress_to` had to be cleared in the same diff (#250's trap: first 3D use silently re-imports a shared texture to VRAM + mipmaps, degrading the 2D that draws it too). And `cover_scale` is a **second** knob beside `tuft_scale` rather than a shared one, on the lantern-vs-flame rule: two different objects at two different drawn sizes, and one number would force whoever tunes the second to un-tune the first. (Both were Look knobs until [#272](https://github.com/Phaazoid/Godoiosis/issues/272) moved them to the Objects tab — see *Where a presentation value is authored* below.)

### Fire is an EFFECT, not a sprite standing on a tile ([#324](https://github.com/Phaazoid/Godoiosis/issues/324), 2026-08-16)

Fire came back in three separate feel-checks — #215's close (*"the fire looks not great"*), the #236/#243 depth fight, then the v0.39.0 playtest (*"the fire effect needs fixing too"*) — and each time it was tuned rather than designed. What shipped until now was **one static `QuadMesh` wearing the look-dev TORCH texture**, 0.5 × 0.7 in a 1×1 cell: no frames, no motion of any kind, and a lamp's art doing duty as terrain fire. The knobs were never the problem; the effect had never been designed, only positioned.

Four rulings, and each is reusable past fire:

- **A cell on fire is not one flame.** `flame_count` quads stand on a ring of radius `flame_spread`, seeded so the scatter is DERIVED from the cell — one tile always burns the same way, no two burn in step, and nothing needs a per-cell store to remember it. The same shape as #280's tufts one level up: *several small things placed across the square* is what reads as the square being the thing, and it is why a single sprite in the middle always read as an object standing on a tile.
- **Motion belongs in the ART, and the art is a sheet.** Eight looping frames generated by `tools/lookdev/gen_lookdev_assets.gd` (analytic, not per-frame noise — every term is periodic in `frame / count`, so the loop closes with no seam), stepped by sliding `uv1_offset` along `uv1_scale`. A shader could have faked fire without any texture, and was rejected for the reason the whole generated-greybox pipeline exists: **when an artist arrives the textures swap and the meshes stay**, and a sprite sheet is what an artist delivers. The sheet imports **lossless with no mipmaps and `detect_3d/compress_to` cleared** — block compression bleeds colour across frame boundaries and mipmaps blend neighbouring frames into each other, which is a hazard a single-image texture does not have.
- **Every strobing effect ships THROUGH #217's switch, never beside it.** `BoardMirror.flame_animated` is that switch's first tenant and its only reader here: off holds the frames still and the light at steady energy — *a still flame, never a missing one*, which is what [#217](https://github.com/Phaazoid/Godoiosis/issues/217) requires of every toggle-off state. It is excluded from `LookPreset` capture, and that exclusion is the sharper half of the ruling: **an accessibility choice is the player's, so authored content must not be able to reach it.** That settings surface now EXISTS (#350: `PlayerSettings` + `SettingsScreen`), so the player-facing half of this switch is a table entry in the store rather than new UI — declare it there, never beside the effect.
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

`BoardMirror.tuft_scale` is the Objects-tab knob (#272; it was a Look knob until then) — a real one, because a tuft is a runtime `Sprite3D` unlike the baked block props. It scales through **`pixel_size`, never node scale** (a Y-billboard rebuilds its basis from the camera, and `pixel_size` scales the base offset with it, so a plant shrinks *toward* the tile), it never moves a plant's place in the cell — where a flower grows is not a matter of taste — and its setter re-sizes tufts already standing, since props reconcile only when their tile changes.

**Tufts are the one prop form that casts no shadow**, and that is a count rather than a look call: `Prolog` paints over a thousand tuft cells against a dozen lamps and trees.

#### The facing is a SET OF EDGES, and it is a second column (#263, 2026-08-15)

`prop_shape` says what form a tile takes; it cannot say which way that form points, so the facing is its own authored column, `wall_edges` — a declared second representation per Law #4, because the two answer different questions. Folding direction into the shape would mean `PLANE_EW` / `PLANE_NS` / `PLANE_CORNER_ES`… for one concept.

**It is a mask of cardinal edges, not a yaw**, because the pieces an artist draws include corners and a corner reaches *two* directions. Each authored edge becomes a half-length slab from the cell centre out to that edge, so **a straight run is two collinear halves — one wall — and a corner is two perpendicular halves — an L. One rule, no corner special case**, and it falls out that each half wears the matching half of its tile's art, so a straight run reassembles the whole sprite un-squashed.

**The facing is per-TILE, and the payoff is that nothing at runtime holds a yaw**: the meshlib item is already keyed per tile, so the generator bakes each piece's orientation into its own mesh and `BoardMirror` plants a fence with the same `_make_prop_block` it plants a crate with. If a sheet ever needs one generic fence tile placed in both axes, the override belongs in the reader (`GridUtils.wall_edges_at_cell`), not in a second column — at the cost of that zero-runtime property.

Two things were **measured** on the way, and both reversed an assumption the issue was filed on:

- **Godot's own alternative-tile transform flags cannot serve.** They were the recommended candidate — an existing-but-unused mechanism rather than an invented convention — but no authored board uses one (0 non-zero alternatives in 5,712 cells across all three), the in-game Tile Brush cannot write one, and a transform bit rotates the **2D** sprite too, so it cannot carry a 3D-only facing without drawing a front-on palisade lying on its side.
- **Not every piece's art can be a wall face.** In this sheet the east-west pieces are drawn face-on (15×13, top-aligned) and are worn directly, keeping the #250 rule that the 3D shows the game's tiles. The north-south pieces are drawn edge-on — 7×16, successive posts stacked *down-screen* — which is a top-down foreshortening, not a picture of a wall; on a plane facing east it renders as a tower of logs. Those faces are **generated in the tile's own measured palette**, the same reconciliation #274 already made for solid props.

A plane is also the one prop form NOT sized by its art's opaque bounds: it is thin by definition in the axis it does not run along, so its thickness and height are generator constants. Being baked, they get no live knob at all — the same call `PRISM_PROFILE` records.

### Block props are GENERATED, not commissioned (#264 + #274, 2026-08-15)

The block form looked blocked on art, and it was — but on *one face*. **The blocker was never the shape: it was that a single 3/4 sprite cannot supply a top face**, and at the board's ~40° pitch you see plenty of top. Everything else was already free: the GridMap stacks, and `gen_lookdev_assets.gd` had built cubes with independent top and side UV rects since Stage 0.

So the generator supplies the missing half. **Every face is generated in that sprite's own measured palette** — planks on a crate, staves on a pot, per-facet stone on a boulder — packed into extra rows of the same composited atlas the ground already uses, so the board is still one texture and no PNG is written (which would re-import to VRAM with mipmaps and bleed the atlas — the #250 trap).

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

- Particles: dust motes in light shafts, embers above BLAZE, drifting leaves/pollen, low ground-fog cards.
- God rays through interior windows (volumetric fog + tight shafts).
- Animated pixel water with real reflections and foam edges (Octopath 2's showpiece).
- Weather: rain/snow with wet-tile specular response; per-preset lighting already exists to receive it.
- Per-map color grades; the four look-dev presets were the seed and are now **real** ([#253](https://github.com/Phaazoid/Godoiosis/issues/253) parts 1 and 3, 2026-08-15). The Moods tab saves named `LookPreset`s to `Resources/LookPresets/`, and twelve ship: Day / Sunset / Night / Overcast ported from `look_dev.gd`, the un-tamed **Forest Fire** that got #212 filed, Dawn, Storm, a deliberately-overcooked **Diorama** that exists to show what the tilt-shift knobs do, and the four **Opus** grades below. Dev rulings, 2026-08-14/15: a preset stores the **whole table** (a diff-preset would let a later scene re-tune silently re-skin every mission that never mentioned that knob) — and it stores **scene mood, not game settings**, so camera *framing* rides along while camera handling, board markup and prop geometry do not (all three have since LEFT the look table outright — #272, then #373). **Part 2 landed the same day and CLOSED #253**: `ScenarioData.look_preset` names the board’s look, `battle3d` applies it on every board load, and `Resources/DefaultLook.tres` is what a board wears when it names nothing — so `Battle3D.tscn`’s inline values have stopped being a second source of truth for "what does this board look like". Everything ABOVE that base layer — weather overriding it, battle flashes interrupting and unwinding — is [#278](https://github.com/Phaazoid/Godoiosis/issues/278), and weather itself is [#277](https://github.com/Phaazoid/Godoiosis/issues/277).
- Camera micro-sway; tasteful, deterministic impact shake.
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
- **The downed clock** as a fading ring decal under the body — readable and moody.
- **Squad cohesion** drawn as a soft light tether/field (the `SquadCohesion.field` is already computed; render it instead of tile fills).
- **Zones**: capture/extraction as diegetic alchemical light columns, intensity tracking progress.
- **Turn count drives the sun** — dawn on turn 1, dusk by turn 12; time pressure made visible. (Pure presentation; the rules never read the clock.)
- **When #116 lands**: the shove-off-cliff kill earns a slow focus-racked camera tilt — the tilt-shift rig doing dramatic work.

## Tier 4 — the far wall (flagged as such)

- Battle intros zooming from a tabletop map into the living diorama; UI as parchment-and-brass instruments framing it (the "toy soldiers" conceit).
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
