# Presentation & effects — the HD-2D idea wall

**Status: an idea wall plus two locked decisions.** Solicited by the dev on 2026-08-12, the day Stage 0 (#203) passed its GO gate: *"a full thought experiment, all ideas on the wall."* Nothing below the Decisions section is a commitment — it is the candidate pool for #176's stage 5 and beyond, kept so it can't evaporate from chat. The look-dev scene (`Scenes/LookDev/LookDev.tscn`) is the standing playground where any of it gets prototyped before it's real — and since #212 (2026-08-15) the **Look tab** in the dev-tools window tunes the *shipping* view live, so a value on this wall can be judged on a real board rather than in the diorama.

**Canon checked through #274 (2026-08-15).**

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
- **Overlays render UNSHADED** (dev ruling): gameplay markup must never read as terrain, which is why fills are unshaded quads rather than Decals — a Decal's albedo modulates the lit surface by construction.
- **Board clicks skip events entirely.** The picker calls `game._on_left_click` / `_on_right_click` (the dispatchers game.gd's own `_unhandled_input` only feeds), and `game.board_input_delegated` stands the 2D derivation down so one physical click cannot act twice. That bool is the whole arc's only game.gd input edit; unset, the flat 2D game is bit-for-bit unchanged — **all hosting mutations are runtime**, never authored into `Main.tscn`.
- The corner PiP survives as a **dev debug view** (F4), not a player-facing mode. The launch-time chooser named above is still stage 4d.
- **A mirror that copies a FLAG inherits every writer of that flag — mirror the QUESTION instead ([#232](https://github.com/Phaazoid/Godoiosis/issues/232), found in play, 2026-08-14).** 4c copied `$MapSprite.visible` to get planning-ghost parity, and `Unit._show_downed_sprite` writes that same flag for an unrelated reason (swapping in the separate downed art) — so going down made a unit vanish from the diorama one line after the mirror had correctly given it the downed pose. The fix is Law #4 at the source: `UnitVisuals.projected` is now declared, so the two questions stop sharing storage. The twin, same commit: the faction tint is set on the **Unit node** and 2D multiplies it down the tree for free, so copying only the child's `modulate` left every enemy un-reddened in 3D — the mirror takes the product. **The general rule for anything polling the 2D: copy what the 2D *renders*, not the field it happens to be stored in.**
- Both of the above were **green under the suite**: `test_downed_and_death_reconcile` asserts the texture swap and passes against a unit nobody can see. Parity tests have to assert what reaches the screen.
- **Draw ORDER is part of the mirror's contract, and the 2D's z-order is the authority for it** (found in play 2026-08-14: freeze icons drew over path arrows and planning ghosts). `BoardOverlays.LAYERS`' `sort` had terrain state at the top of its range while the 2D puts it at `TERRAIN_Z_INDEX` — *above the board, below unit sprites* — with arrows above that. The two orders are now tied together by a test that reads both sides, so retuning a sort is free but **contradicting the 2D reds**. Beneath that sits a structural rule the 3D had simply been missing: **`BoardOverlays.UNIT_RENDER_PRIORITY` puts every unit sprite above every overlay layer by construction** — the twin of the 2D's "tile overlays sit below `Unit.BASE_SPRITE_INDEX`". Planning ghosts are `UnitSprite3D`s, so they inherit it; before it they were priority 0 and *arrows* drew over them too, which nobody had reported yet.
- **Anything that starts writing depth must first be checked for COPLANARITY — the two failure modes are opposite, and fixing one hands you the other** (fire, 2026-08-14, twice in one day). A flame that did *not* write depth lost to whatever did, which is how a body lying in fire swallowed it. Switching it to `TRANSPARENCY_ALPHA_DEPTH_PRE_PASS` fixed that and immediately produced the worst z-fighting on the board, because a centred 0.7-tall quad lifted 0.35 has its **bottom edge at exactly y = 0** — coplanar with the tile it stands on, seen at the grazing angle a pitched camera looks from. Harmless for as long as it stayed out of the depth buffer. The clearance is now a **clamp** (`BoardMirror.flame_base_lift`), not a default, so no authored knob can put the quad back in the ground; that is the flame's twin of `BoardOverlays.fill_lift`, and **every new depth-writing surface owes the same check**. The residual — a flame and a unit sprite are both camera-facing planes through the same point, so they are coplanar by construction wherever a unit stands in fire — has no geometric fix and is exposed as `flame_writes_depth` for the dev to judge, since the two modes simply trade which artefact you get.

### The camera contract, amended: free orbit rests, Q/E realign (#176 stage 4d, 2026-08-14)

The original contract locked **"yaw snapping in 90° steps"**. The dev asked the sharper question — *do we need to snap to anything at all?* — and the answer from the code was no:

- **Sprite facing never depended on it.** `UnitSprite3D.facing_flip_for` judges each step against the **live** camera basis, so it is correct at any continuous yaw today; the future `frame_for(unit_facing, camera_yaw)` seam quantizes the *relative* angle internally.
- **"Units can't hide behind terrain" is helped, not threatened** — free rotation reaches every angle rather than four.
- The genuine cost is **texel shimmer at off-axis rest**, which is aesthetic and about the *resting* pose, not about what happens mid-drag.

**So: yaw orbits freely and rests wherever the player leaves it; Q/E step to the next 90° detent, realigning in one press.** The crisp axis-aligned pose is now an affordance rather than a cage. A corollary the amendment forced: facing was only re-judged when a unit *moved*, so any rotation left standing sprites facing the old angle — snapping never protected against that either; the mirror now re-judges on camera turn.

Bindings are knobs, not canon: `orbit_button` was built to default to middle-drag so right-click could keep its press-to-cancel meaning, with the click/drag threshold built so flipping it was an inspector change. **The dev flipped it to right-drag after playing it (2026-08-14)** — *"you don't need to drag the mouse when canceling orders, so the overlap is a non issue"* — which is the knob working as intended; cancel now fires on release-under-slop, and moving the binding back moves it back to press.

Also settled here: **the camera follows the action by mirroring the 2D camera** (which `AIController` already pans to each acting squad) rather than growing a second follow seam — so `Pacing.AI_SQUAD_PAN` keeps one number and one reader, and the 3D inherits the 2D's easing exactly. The gate is `ai_locked`, deliberately *not* the broader board lock, which also covers menus. **Entering an AI turn also squares the camera up** to the nearest detent (dev call, 2026-08-14): free orbit is the player's, but an enemy phase reads on an axis-aligned board. It fires on the *edge* into the turn rather than every frame, so the day orbit is allowed to stay live under an AI turn it squares up once instead of fighting the drag.

**The opening shot is the player's squad, not the board (dev feel-check, 2026-08-14: fitting all 64×40 of Prolog opened too far out to play from).** These are two different questions and the rig now takes both — `frame(shot, bounds)`: the *shot* is what is on screen at load, the *bounds* are the box the view may never leave, and only the bounds set the zoom ceiling and the pan limit. Solving the ceiling off a close shot would have clamped the player out of ever seeing the rest of the map, which is the same class of bug as the cells-passed-as-a-distance one this stage fixed. Falsification note worth keeping: the obvious test — *are the player's units on screen at load?* — **passes against a window aimed at the board's centre** on both authored missions, because both squads start near the middle. The aim itself has to be asserted, or "opens on your squad" is pinned by nothing.

### The mirror is LIVE, and the turn-boundary approximation is retired (#231, 2026-08-14)

Stage 4a shipped two declared cadences: the board mirrored on `board_loaded`, and tile states re-read at `turn_started`. Both were honest v1 approximations, and both became wrong the moment authoring moved into the 3D view — you painted and nothing happened until F2, which is the round trip the whole dev-tools-in-3D arc exists to kill. They are gone.

**Fire is now reconciled per cell and polled**, so a mid-pass ignition appears when it happens. That also removes the artefact the old cadence produced: a flame that rendered wrong appeared to "come back at the end of the turn" because the *marker* was rebuilt, not the state. Poll rather than signal, and for a reason worth remembering: a `states_changed` signal fires *inside* the resolver's per-effect loop, so it would create and free markers many times within one pass, where a poll coalesces a whole frame into one reconcile.

**Terrain syncs per cell too, but only while `DEV_MODE` is active** — the sim never paints terrain, so the diff stays entirely out of the shipping game while still catching every writer with no trigger site to remember. (An engine signal was the first choice and does not exist: `TileMapLayer.changed` does **not** fire on `set_cell`/`erase_cell` in 4.7. Measured, with a property write as the control.)

Two rules this settled, both general:

- **A repaint can add or erase a COLUMN**, which is what the picker table and the camera bounds derive from — refresh them with it, or the cell you just painted is unclickable. Bounds only, never a re-frame: painting a tile must not yank the camera, matching what `CameraController.refresh_bounds` has always done in 2D.
- **Authoring scaffolding mirrors only while the 2D shows it.** `ZONE_PATROL` (the brush's default kind) and the picked-zone highlight had no 3D twin at all; giving them one means mirroring *cells and visibility*, because the 2D reveals those layers solely while the Tile Brush tab is up. Mirror the question — "should this be on screen" — never the field the cells happen to live in.

### Conventions the art commission must carry (pending look-dev experiments)

Two Tier-1/2 ideas below change *what art gets ordered*, so they are experiments to run in the look-dev scene **before** any commission, then locked into #176's conventions list:

1. **Emission channel** — windows, runes, crystals authored with an emission mask so bloom picks them selectively. Cheap to demand up front, impossible to retrofit across a finished sprite library.
2. **Normal-mapped pixel art** — generated from sprites (e.g. Laigter-class tools) so flat-lit art still takes directional light convincingly. This *amends* the flat-lit convention rather than breaking it (albedo stays flat; the normal map carries the depth). Decide by eye in the look-dev scene.

### A prop's FORM is authored art data, not a rendering choice (#255, 2026-08-15 — MEASURED, not predicted)

Stage 5b stood every object-shaped tile up as a billboard and the dev judged the result: *"most of it looks awful… things that are supposed to be blocky, like the chest and the crates, look so odd like this, they really want to be textures on a 3D model. The fences don't work at all. The lamps, surprisingly, are fine. I think **anything that's thin already works in this style**."*

That sentence is the convention, and it is the same split Octopath uses (billboarded foliage and lampposts; real geometry for crates, walls and buildings). **A prop therefore has three possible forms, and which one it is belongs to the ART, decided when it is drawn:**

| Form | What it is | Renders as | Art it needs |
|---|---|---|---|
| **Billboard** | thin, roughly symmetric about its vertical axis — lamps, trees, grass, banners | camera-facing sprite, pivot at the base | one front-on sprite (what a tilesheet already gives) |
| **Oriented plane** | thin but DIRECTIONAL — fences, railings, low walls | fixed-yaw quad, facing authored per piece | one front-on sprite **plus a facing** |
| **Block** | volumetric — crates, chests, rocks, barrels | real geometry standing on the ground block | a **top** texture and a **side** texture, minimum |

**The form is ONE authored column, `prop_shape` on the tileset** (`GridUtils.PropShape`, read by `BoardMirror` and by `gen_lookdev_assets.gd`). It began as #255's `stands_up` bool and was widened by #264 rather than joined by a second column: a tile's shape and whether it stands up are one question, and two answers to it can disagree. `FLAT` is the ground itself; `BILLBOARD` is the thin form; `CUBE` / `FACETED` / `ROUND` are the block form, with the member naming the solid so a crate and a boulder differ without a second seam. #263's oriented plane lands here as a further member.

**Shipped: billboards (#255) and blocks (#264).** The oriented plane is still unbuilt — it needs no new art but does need a piece→facing mapping, which is a *content convention* (Law #4's named hazard) and so is its own decision rather than a detail.

### Block props are GENERATED, not commissioned (#264 + #274, 2026-08-15)

The block form looked blocked on art, and it was — but on *one face*. **The blocker was never the shape: it was that a single 3/4 sprite cannot supply a top face**, and at the board's ~40° pitch you see plenty of top. Everything else was already free: the GridMap stacks, and `gen_lookdev_assets.gd` had built cubes with independent top and side UV rects since Stage 0.

So the generator supplies the missing half. **Every face is generated in that sprite's own measured palette** — planks on a crate, staves on a pot, per-facet stone on a boulder — packed into extra rows of the same composited atlas the ground already uses, so the board is still one texture and no PNG is written (which would re-import to VRAM with mipmaps and bleed the atlas — the #250 trap).

**The sides started as the sprite and that lasted one playtest (#274).** A sprite cannot *wrap*, so #264 put the whole sprite on every facet — and the dev's verdict was precise: *"the rocks and the pots need it most, their sprites do not map to their models."* A crate is a box, so a box-shaped drawing lands on its four sides tolerably; a ten-sided pot rendered as **ten overlapping pots**. Generating the strip fixes it structurally rather than cosmetically:

- **Each facet owns a distinct, equal, contiguous slice of the side strip**, inset by its own half texel. One UV rule for both prisms — whether the slices read as a continuous wrap (a pot) or as separate stone faces (a boulder) is decided by the *texture*, not by the mesh code.
- A prism's strip is therefore one atlas patch **per facet**: slicing a single 16px patch into ten facets would leave 1.6 texels each.
- **No baked shading.** The material is shaded, the sun is real, and a prism's facet normals already differ, so lighting does that work and the albedo stays flat — the convention every look-dev texture holds to.

**This is the one place the 3D deliberately does NOT show the game's tile art**, which is worth declaring because #250's whole finding was the opposite. The reconciliation is that the *colours are still measured from that art* — a prop's palette is its own sprite's dominant shades, read back rather than invented — and that a volumetric object genuinely cannot wear one 3/4 drawing, which #264 measured rather than assumed. A billboard is the one form a sprite maps onto correctly, and billboards still wear theirs.

**Material is not yet a question the data can answer.** Crate and chest are both `CUBE` and share one plank recipe; they are both wooden boxes, so that is honest until something complains. Note that `terrain_type` **cannot** be pressed into service for it — pot, chest, rock and lantern all carry `Terrain.Kind.ROCK` and crate carries no kind at all, the same counterexample set that stopped `stands_up` being inferred from kind in #255.

Two rules worth keeping:

- **The mesh is sized by the art's OPAQUE BOUNDS, not by the cell.** A rock is 32% transparent, so a cell-wide cube around it is mostly air. Measuring makes a small sprite a small object with no tuned offset anywhere. **A billboard is PLANTED by the same measurement** — a tile region may carry transparent padding (the lantern's art stops 5 rows above its region's bottom edge), and planting by the region left the visible lamp floating a third of a cell for as long as billboards have existed. One rule, `BoardMirror.opaque_bounds`, read by both stacks.
- **A prism's silhouette is a PROFILE**, a list of (height fraction, radius fraction) rings, not a single taper. Two rings make a truncated cone standing on its widest part, which is the opposite of a vessel — a pot is narrow at the foot, widest at the belly and drawn back in at the rim (dev, 2026-08-15: *"the geometry needs to come back to a central point on the bottom to make them look round"*). The numbers are a feel value with no runtime knob, because the mesh is baked: rounder is a line in the table plus a regenerate.
- **The footprint is square.** A 3/4 drawing says nothing about depth, so inventing a second number would be a guess dressed as a measurement.

**This is the project's normal pipeline, not a compromise** — every look-dev ground texture is RNG-generated too, and that is the art that passed Stage 0's gate. The honest ceiling is coherent greybox: a generated rock reads as a faceted lump, not as a rock someone drew. **When an artist arrives the textures swap and the meshes stay**, so the commission line below still holds — it is now a quality upgrade rather than a prerequisite.

**Consequence for the commission**: the sprite sheet must say, per prop, which form it is — and blocky props are best ordered as a top + side pair rather than as a single 3/4 view. That is cheap to specify up front and expensive to retrofit, which is exactly the bar the two conventions above are held to.

---

## Tier 1 — finishing the HD-2D canon

Proven Squeenix-style ingredients Stage 0 didn't include. All stage-5 material.

- Particles: dust motes in light shafts, embers above BLAZE, drifting leaves/pollen, low ground-fog cards.
- God rays through interior windows (volumetric fog + tight shafts).
- Animated pixel water with real reflections and foam edges (Octopath 2's showpiece).
- Weather: rain/snow with wet-tile specular response; per-preset lighting already exists to receive it.
- Per-map color grades; the four look-dev presets were the seed and are now **real** ([#253](https://github.com/Phaazoid/Godoiosis/issues/253) parts 1 and 3, 2026-08-15). The Look tab saves named `LookPreset`s to `Resources/LookPresets/`, and twelve ship: Day / Sunset / Night / Overcast ported from `look_dev.gd`, the un-tamed **Forest Fire** that got #212 filed, Dawn, Storm, a deliberately-overcooked **Diorama** that exists to show what the tilt-shift knobs do, and the four **Opus** grades below. Dev rulings, 2026-08-14/15: a preset stores the **whole table** (a diff-preset would let a later scene re-tune silently re-skin every mission that never mentioned that knob) — and it stores **scene mood, not game settings**, so camera *framing* rides along while camera handling, board markup and prop geometry do not. **Still open is part 2**, attaching one to a mission: the default preset becomes the authority at load, so `Battle3D.tscn`'s inline values stop being a second source of truth for "what does this board look like". `Day` is deliberately the authored scene verbatim, so it is that default already.
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
