# 2 — Elemental v1 slice (SHOCK × WET)

**Lane B (you type the gameplay code) · your main hands-on session · soft-depends on Prompt 1** (for the E-tests). Don't run concurrently with Prompt 3 — both touch unit.gd + SquadManager.gd.

```
Project: Iosis (tactical RPG, Godot 4.6, GDScript). Work in C:\Iosis\Godoiosis. Read CLAUDE.md first (the 3 design laws; WeaponData=policy / AttackPattern=geometry; execution order moves -> attacks -> counters), then docs/design/elemental-system.md IN FULL (E1-E8, v1 scope), and docs/design/resolution-pipeline.md IN FULL (the R1-R8 contract — now LOCKED — this build must conform to). Then read the real seams: Classes/actions/AttackAction.gd (the damage calc in create(), ~line 82), Classes/squads/SquadManager.gd (calculate_counterattacks_for_squad and get_display_entries_for_squad — the derived-resolver + preview pattern you mirror), unit.gd + UnitInstance.gd (the transient/persistent seam), Classes/weapons/WeaponData.gd (elemental_damage_type is already there, stubbed "").

Goal: Build the v1 elemental slice end-to-end — ONE reaction, SHOCK × WET -> bonus damage + remove WET — through the plan-time resolution pipeline, proving the architecture.

Collaboration: this is GAMEPLAY code — the user hand-types ALL of it. Deliver every change as a complete typed code block with file/line anchors, and explain the why (the user is learning). After each step lands, READ the actual file before continuing — transcription drift is the top failure mode.

Hard laws: #1 — no RNG anywhere in the resolver. #2 — the queue never lies: the preview must show the reacted number and state change, computed at plan time; execution just replays it.

CRITICAL framing (resolution-pipeline.md): do NOT build a private ElementResolver. Build the GENERAL pipeline seam with two stages (base damage + elemental) plus the ResolvedPlan / ResolvedOutcome types and ONE preview/outcome model (R8). Phase 3 (Will) will add a stage behind elemental — leave room for it (R7: damage final before later stages read it). THREE things are LOCKED for Will's sake — build them now even though no Will stage reads them yet: (a) the threaded hypothetical carries {projected position, element states, HP, Will-slot} per unit, NOT element-states-only — thread HP from day one (R4); (b) the counter stage reads that hypothetical with an always-true liveness flag, so Phase 3 only flips liveness on (R7); (c) the ResolvedOutcome is the single source of truth for damage — AttackAction stops computing it and execute() consumes the ResolvedPlan (R8/E1). The base-damage math currently in AttackAction.create() MOVES into the pipeline (E1/R5).

Build order (from the design doc):
1. Vocabularies as enums/registries, NOT raw strings — there's a standing project rule to prefer enums over strings, and elemental_damage_type / weapon_type are already flagged for it (note: scaling_stat is currently a stringly @export_enum too). Stand up Element and State properly (a domain registry like Stats.gd / WeaponCatalog.gd, or enums). Append-only if persisted.
2. ElementalReaction resource (incoming_element, required_state, damage_mult/bonus, add_states, remove_states, vfx_tag/popup), editable in the reflection dev editor.
3. A boolean state store on the transient Unit (v1 is chain-scoped, so Unit suffices — fork 3 / resolution-pipeline.md persistence seam note this lives on Unit for now, not UnitInstance).
4. The pipeline pass invoked by SquadManager: one walk of the ordered plan, threading a HYPOTHETICAL copy of unit state forward ({projected position, element states, HP, Will-slot} — R4), writing a ResolvedOutcome (resolved damage + state-deltas) per action into the ResolvedPlan — NOT onto AttackAction (R8/E1: AttackAction stops computing damage). BEFORE removing the damage calc from AttackAction.create(), inventory every reader of the current AttackAction.damage value (preview UI, info panels, execute()) so none is missed.
5. Preview surfaces the reacted outcome (E3/R3, Law #2): boosted number + "Electrocuted!" + WET removed in the queue (extend get_display_entries_for_squad's path). Execution becomes pure playback.
6. Author the one reaction as data: SHOCK × WET -> bonus damage, remove WET.
7. Write E1-E8 as tests in the harness (test-first where practical). They are the contract. (E8 = the compositor: test it directly with synthetic effects — multipliers multiply, bonuses sum, state-deltas union, remove-wins on conflict — since v1's single reaction can't stack with itself.)

Done when: alchemist hits WATER (queue shows WET set) -> mechanist hits SHOCK (queue shows the bonus + Electrocuted, WET cleared) -> execution matches the preview exactly -> E1-E8 green.

STAY IN V1 SCOPE. Explicitly OUT: tile/terrain states, over-time (EoT) statuses/timers, magnitude/stacks, multiple elements per attack, more reactions. The doc lists these as deferred — don't build them.

These were open when this prompt was first drafted but are now SETTLED in the ratified elemental-system.md — build to them, don't re-litigate: reaction matching is all-stack (E8 — every matching reaction fires, composed order-independently against the pre-hit snapshot; NOT first-match); counters are in the chain and carry elements (E7, CONFIRMED — a counter may complete a combo); combos are faction-agnostic (friendly/self-combos are legal — faction governs only hits_allies, not whether a reaction fires). Surface a fork only if a genuinely NEW one appears mid-build.
```
