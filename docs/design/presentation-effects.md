# Presentation & effects — the HD-2D idea wall

**Status: an idea wall plus two locked decisions.** Solicited by the dev on 2026-08-12, the day Stage 0 (#203) passed its GO gate: *"a full thought experiment, all ideas on the wall."* Nothing below the Decisions section is a commitment — it is the candidate pool for #176's stage 5 and beyond, kept so it can't evaporate from chat. The look-dev scene (`Scenes/LookDev/LookDev.tscn`) is the standing playground where any of it gets prototyped before it's real.

**Canon checked through #205 (2026-08-12).**

---

## Decisions

### Two presentations, parallel stacks (dev, 2026-08-12)

The HD-2D presentation (#176) is built as its own parallel stack. **The flat-2D game stays alive, playable, and untouched** — the experimental sandbox, the test harness's home, and the dev tools' host. No feature-parity obligation in either direction.

- A launch-time chooser (which battle scene Mission Select boots) arrives around stage 4, when the 3D side becomes playable. Not before; there's nothing to choose yet.
- **No formal BoardView interface up front.** The interface direction is right, the up-front project is not: an interface designed before its second implementation exists gets shaped wrong. Stages 1–4 build presentation-neutral seams (cell↔world, picker, facing, overlays), each stage leaving the sim/view boundaries it touches cleaner — by stage 4 the interface exists *de facto* and formalizing it is a rename, not a refactor. (The `HoverPresenter`/`MainActionMenu`/`OrderExecutor` extractions are the precedent: extract when the tangle earns it.)
- **The trailer beat** — opening on the flat 2D game, then dramatically becoming HD-2D — stays achievable: a capture cut works today; the live version (both stacks reading one sim, crossfade) becomes a small job once stages 1–4 exist.
- **The clock on the 2D side:** the day elevation enters the *rules* (#116's shove-off-height kill), flat 2D can only render height schematically (numbers on tiles). Acceptable for a sandbox; worth knowing the limit exists.

### Conventions the art commission must carry (pending look-dev experiments)

Two Tier-1/2 ideas below change *what art gets ordered*, so they are experiments to run in the look-dev scene **before** any commission, then locked into #176's conventions list:

1. **Emission channel** — windows, runes, crystals authored with an emission mask so bloom picks them selectively. Cheap to demand up front, impossible to retrofit across a finished sprite library.
2. **Normal-mapped pixel art** — generated from sprites (e.g. Laigter-class tools) so flat-lit art still takes directional light convincingly. This *amends* the flat-lit convention rather than breaking it (albedo stays flat; the normal map carries the depth). Decide by eye in the look-dev scene.

---

## Tier 1 — finishing the HD-2D canon

Proven Squeenix-style ingredients Stage 0 didn't include. All stage-5 material.

- Particles: dust motes in light shafts, embers above BLAZE, drifting leaves/pollen, low ground-fog cards.
- God rays through interior windows (volumetric fog + tight shafts).
- Animated pixel water with real reflections and foam edges (Octopath 2's showpiece).
- Weather: rain/snow with wet-tile specular response; per-preset lighting already exists to receive it.
- Per-map color grades; the four look-dev presets are the seed.
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
- **Alchemy as art direction.** Glowing ground sigils for channeled carvings (aura-colored, per-affinity palettes), channel-threads of light from alchemist to carving — and the thesis-level version: the classical alchemical stages are *color* stages (blackening → whitening → yellowing → **reddening: iosis itself**). A mission or campaign arc whose grading walks that sequence makes the game's name its visual spine.
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

## Mobile & quality tiers (the Forward+ question, answered 2026-08-12)

Godot supports per-platform renderer overrides (`rendering_method.mobile`), so the Forward+ switch costs one line to undo *per platform*. The real constraint is the stack: as of 4.7, volumetric fog / SSR / SSAO are Forward+-only, while glow and DoF (and, likely, decals) survive on the Mobile renderer — **re-verify per feature at port time**. The mitigation is work PC scaling wants anyway: the look-dev scene's per-ingredient toggles are a quality-tier system in embryo (a "low" tier fakes fog with billboard cards, drops SSR/SSAO, keeps glow + DoF). Octopath's own mobile release proves the look scales down; a 14×14 diorama is tiny by its standards. Steam Deck is the nearer target and runs Forward+ natively.
