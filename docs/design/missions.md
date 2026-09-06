# Missions — the closed loop

**Status: ALL FOUR SLICES BUILT 2026-07-28 ([#96](https://github.com/Phaazoid/Godoiosis/issues/96)).** Filed 2026-07-27, when the project acquired a win condition for the first time. Before this, Iosis had ten interlocking systems and no way to finish a battle — which meant a design question could be answered *"is this coherent?"* but never *"does this improve play?"*

**Canon checked through #786 (2026-09-05).**

## What a mission is

A mission is a board you can **lose**. Everything else — selection, capture points, extraction, briefings, rewards — is content stacked on a loop that already closes.

The loop lives in four places, and the split is load-bearing:

| part | lives in | why there |
|---|---|---|
| **the rule** — won, lost, or ongoing? | `MissionRules` (`flow/`, static, pure) | Mirrors `LethalityRules`: one function reading a `BoardContext`, so the game, the headless Play API and the tests cannot each grow their own copy. |
| **the state** — the latches, the objective progress, the ending | `MissionController` (`flow/`, a game collaborator) | Everything a pure predicate structurally cannot hold, plus what the game *does* about an ending. |
| **what a mission requires** | `ScenarioData.objectives` | Authored content, saved with the board. |
| **where a requirement IS** | `ScenarioData.zones` (via `ZoneManager.Kind`) | Geometry. A capture point is a zone of size one. |
| **who the computer plays** | `ScenarioData.ai_factions` (#150) | Authored content, saved with the board — same shelf as `objectives`. Commanding is hotseat-gated, so a mission that declares nobody hands the player both sides rather than stalling — **which is a board the dev authors on purpose** (2026-08-26: *"controlling both sides is important to testing"*), so `BoardLint` warns about it and never refuses it. |
| **what it LOOKS like** | `ScenarioData.look_preset` (#253 part 2) | A preset NAME, not a `LookPreset` reference — a dangling `ext_resource` can fail the whole load rather than degrade, and a Resource field risks embedding the preset on save (#177's trap). Empty, or a name that no longer resolves, falls back to `Resources/DefaultLook.tres`, loudly — which the Moods tab can itself rewrite since #386, so "what an unnamed board wears" is authored rather than only editable by hand. `battle3d` applies it off `board_loaded`; a flat 2D launch has no host and applies nothing. |
| **who the player may BRING, and how many** | `ScenarioData.roster` (#735) + `deployment_cap` (#736) | The pre-mission phase's authored half ([#731](https://github.com/Phaazoid/Godoiosis/issues/731)). `roster` is a NAME resolved against `RosterCatalog.ROSTER_DIR`, for `look_preset`'s two reasons directly below; **empty = this board has no pre-mission phase**, which is what every board saved before #735 is, and is why adding it broke nothing. `deployment_cap` is a MAXIMUM only — a mission cannot demand a minimum force — with `0` meaning *as many as the deployment zone holds*, that sentinel being the field's own default (`round_limit`'s rule). Deliberately **not** derived from the zone's size: force size and starting spread must move independently. Both live on `ScenarioManager` as `current_*` stores with the four-writer contract, not on `MissionController`, which owns the mission's ENDING. |

Plus two UI surfaces: `MissionSelectScreen` (`ui/`) is the game's front door, and `MissionEndBanner` (`ui/`) is the card at the end.

## The pre-mission draw (#737)

A board that names a roster **spawns all of it and draws from that onto its deployment zone, up to its cap** -- the opening position the player then edits (#739, below). `MissionController.deploy_roster` is the whole of it, and `PreMission.deployment_plan` is the pure half that decides who and where (entry order for who, reading order for where, three limits composing: roster size, cap, room).

### The undeployed half is real (#738)

The whole roster spawns as real `Unit` nodes, into **`game.reserve_root`** — because every readout the pre-mission screen needs takes a **wielder** (`can_equip`, `get_live_abilities`, the base → limb → jobs → effects → gear chain), and an undeployed unit answered by a second implementation reading `UnitInstance` directly would drift the first time a stat source is added. `Unit._ready` guards *only* its grid setup behind `if pending_grid`, so an off-board unit has still run `initialize()` and `_seed_starting_kit()`. It is also what makes this the one way a roster unit reaches the board: the draw deploys out of the same set #740's screen lets the player choose from.

**Two rules, and the reserve exists only where both hold.** It is **not under `units_root`** — nine readers across six files take that node to mean *a unit on the board*, so undeployed units there are living player units, the #96 defeat floor never fires, `present_factions` never drops PLAYER, and the AI weighs phantoms at the origin. (The floor, not rout: rout asks about *hostile* factions, so extra player units do not touch it.) And it is **inside `clear_board`'s teardown** — a holding parent outside it survives a board swap pointing into a board that has been freed. `visible = false` is a third, smaller rule: a `Unit` is a `Node2D` with sprites, so ten parked under a visible node draw stacked at the origin in the flat 2D view, where the 3D side is safe by construction because `UnitMirror` scans `units_root`.

**What an undeployed unit may be asked**: wielder-taking predicates, and nothing squad- or cell-shaped. It has no `Squad` — `game.deploy_unit` is what registers one — and its `movement.cell` is a meaningless zero, so undeploy nulls the grid to make a cell question a loud `push_error` rather than a stale answer.

**Undeploy goes through `SquadManager.release`, not `leave_squad`.** That door re-solos the leaver, which is right for a unit that is still standing (downed ejection, loss of contact) and wrong here: it would leave a live `Squad` holding a unit in the reserve, and emit `squad_created` on the way out. `release` is the one exception to *every unit is in exactly one squad*, scoped exactly to whether the unit is on the board. It also forced `Squad._erase_member` to clear `unit.squad`, symmetric with `_add_member` — every caller before this re-added immediately, so a unit naming a squad it had left was unobservable, and `destroy_empty_squad` then freed the object it still named.

**Where it is called is the design.** It sits at the two FRESH-START doors — `begin_mission` and `restart_mission` — beside the arm decision the director already forks on (#182), and never inside `apply_scenario`, which every board load crosses. A save slot records `roster` like any other field, so a deploy down there would fire on `resume_from_slot` *on top of* the units the save just restored, and again on the dev-tools Load and on F2, neither of which is a mission starting. Note the consequence for authoring: **F2 does not deploy** (it calls `reload_current()` alone, one door short of a restart, and never arms either) — the doors that draw are Mission Select and the pause menu's Restart.

**And it runs BEFORE the arm.** `spawn_unit` creates a solo squad per unit, which emits `squad_created`, which an armed `ScenarioDirector` answers by firing `SQUAD_FORMED` beats and advancing the lesson — so a three-unit draw would play its payoff three times before the player had touched anything. The director's own contract says it: a loading board must never trip a lesson or a beat.

**An authored save skips the drawn units.** `Unit.drawn_from_roster` is a transient flag read at exactly one place, `capture_scenario`'s `authored` branch: a roster draw is authored by the *roster*, so writing it into the board's own `unit_entries` would make the next boot draw a second force on top of the one it just recorded — reachable by playing a mission, pressing F1, tweaking a zone and hitting Update. A full capture (a save slot, a bug report) keeps them, because it is restoring a battle rather than re-authoring a board.

### The phase the player stands in (#739)

**The draw is the opening position, not the answer.** `begin_mission` holds the board after `deploy_roster` rather than playing on, and `commit_deployment` is the one way out. #737's *"the player does not linger there yet"* is retired by this: three of the four things that scope deliberately left unbuilt — a commit that can be refused, a back-out through the ring, no-saving-during-the-phase — are built here, now that there is something for each to serve rather than a mechanism whose only job was to survive until this ticket. The fourth, a **restart buffer**, stays out and is [#763](https://github.com/Phaazoid/Godoiosis/issues/763): the walk is deterministic, so a retry re-draws the same characters onto the same cells and only *hand* placements are re-made.

**`MissionController._deploying` is the INTENT; `GameState.PRE_MISSION` is what the board shows for it.** It has to be a flag of its own for the reason `dev_mode_enabled` is one — `game._base_state()` decides what the board rests at and `clear_selection` *writes* `game_state` from it, so a state derived from `game_state` would answer PICKING_TARGET in the middle of a squad pick and rest the board on IDLE afterwards, dropping the player out of deployment the first time they form a squad with every later click reaching the battle ring. Its one entry, `_open_deployment`, sets the flag **and** rests the board on the new base state — setting the flag alone leaves `game_state` wherever the arrival left it. Its one exit, `commit_deployment`, clears the flag **before** `_begin_turn`, because `start_faction_turn` rests on `_base_state()` too and turn 1 would otherwise come to rest inside the phase it just left.

**The HUD stand-down rides the flag's SETTER, never the commit.** End Turn and the queue panel stand down; the two readouts stay up, which is not a smaller version of #722's cinematic hide but a different question — a cinematic is nobody *looking*, the phase is nobody *acting*, and #740's board preview inspects through the panel this would otherwise have hidden. End Turn is the load-bearing one: its press gates on `_board_locked_for_player()`, which is false in the phase, so an un-hidden button would run `end_turn()` on a turn that never started. Writing the hide at commit instead is the trap — `abandon_mission` and `resume_from_slot` both leave the phase without passing through it, so the *next* mission would open with no End Turn button at all.

**What stands down leaves a hole, and #774 is the bill for it.** Hiding both battle surfaces left the
board preview showing a lit deployment zone and nothing else — the way back to the menu and the way
into the battle were both keys, on a screen that had just vanished. `PreMissionBar` is the phase's
own corner HUD, built at `_open_deployment` and freed by `_close_deployment_menu` so all three exits
already take it, carrying **Loadout** (the Tab swap) and **Begin Mission** (the Enter commit).
It sits in the slot End Turn just vacated, which `MissionStatusPanel` reserves whether or not that
button is visible.

**The bar's Begin stays live where the screen's greys, on one shared reason.** `commit_deployment`'s
refusal speaks through `TurnBanner`, a plain child of Game — under the screen's `CanvasLayer` that
banner cannot be seen at all, so the screen greys its Begin and puts the reason in a tooltip, while
out on the board the banner is in plain sight and the button can stay live and let the refusal speak.
Two surfaces, two answers, one question: *can the player hear the no.*

**And the commit asks first** (dev, 2026-09-05) — an accidental press must not start a battle
prematurely. `MissionController.confirm_and_commit` is where the card lives, because the commit has
**three** doors and a confirm bolted to one of them is a confirm the other two walk around. The
refusal is *not* asked about first: a card in front of an act already destined to be refused is two
dead ends where one would do, so the empty-force case goes straight to `commit_deployment` and its
voice. The flag is re-read after the await, since a dev key is exempt from the modal freeze and F2 can
end the phase while the card is up.

**What the player may do while standing there.** A click on one of their units opens the ring — the same widget, with nothing to say about a turn: Squad Up / Join / Leave / Disband through their own gates unchanged, plus Undeploy and Inspect. `MainActionMenu.populate` early-returns into `_pre_mission_options` *before* any gate that reads `unit.squad`, because a unit the phase has just undeployed does not have one. A click on an empty deployment cell offers the units still waiting — `ActionMenuController` already takes an arbitrary tree and already routes non-verb leaves through synthetic ids, so the ring *is* the dropdown and no widget was built for it. Undeploy is gated on `drawn_from_roster`: authored units are additive and belong to the board (ruling 2c), and enemies are `units_root` children too.

**Saving is refused during the phase, at `ScenarioManager.save_to_slot` rather than at the pause-menu row.** A slot is a mid-battle snapshot and `capture_scenario` walks `units_root`, so the reserve is invisible to it: a save taken here would record only the units already placed, and the resume — which correctly bypasses the phase — would come back with the rest of the roster gone and no way to finish choosing. The pause menu greys its own row and names the reason; the refusal underneath is the gate.

### The screen itself (#740 + #743)

**Four regions, from his sketch**: the roster's cards top-left, the stash down the whole right side, and along the bottom the force placed so far with the mission's contract cut into it. `PreMissionScreen` is a `ModalCard` that is not a card — unframed, opaque, claiming no `ModalLock` — the way `MissionSelectScreen` is not one, and for a sharper reason: the board underneath has to keep running, because Tab swaps to it.

**It locks the board by joining `game.menu_is_up()`, not by eating clicks.** `battle3d` picks board cells with its own raycast and calls `game._on_left_click` **directly**, gated only on `_board_locked_for_player()` — so a full-rect Control that swallows input is entirely transparent to the 3D view, which is the shipped one, and would have been correct only in the dev-only flat view. Joining that one predicate covers both click doors *and* the camera rig's manual-input gate, and hands all three back the moment the player swaps to the board. It reads **visibility, not existence**: hiding the screen *is* the preview, which is why the screen is hidden rather than freed — the scroll position and anything open survive the look.

**The backdrop is opaque and that is load-bearing.** Nothing is frozen behind it, so `CameraController`'s WASD poll and `HoverPresenter._process` are still running; translucent, the player would watch the board pan under their own menu. Same rule as `MissionSelectScreen`, different reason (that one hides an abandoned board).

**`MissionController` owns the lifecycle and closes it at every exit** — commit, `reset()` (F2, a board swap, Load Game) and **`abandon_mission`, which needs its own call** because that path never reaches `clear_board`, so nothing else would ever take the screen down and it would outlive its mission holding units the next load frees.

**The card**: the unit fills the left (sprite, name, limbs, job, live abilities, the eight effective stats), what it *carries* fills the right as the same row the stash uses — six of them, because that is `MAX_INVENTORY_SIZE` — and the strip along the bottom is weight and effective DEF plus the deploy toggle. Every number is read, never re-derived: `get_effective_stat`, `get_effective_def`, `get_weight`, `get_live_abilities`, which is exactly what ruling 7 spawns the whole roster as real `Unit`s to make possible. **A card whose unit is going wears the friendly ink around it** (`READOUT_ALLY`, dev 2026-09-05, from his original mockup) — on the **border**, never the fill, because the fill is the ground every chip and number on that card is read against; the content margin is held across both states so a card does not resize the instant it deploys. `game.is_deployed` is the one answer behind it: `units_root` membership is what "deployed" means, and the outline, the toggle's own label and the screen's toggle handler all ask it there rather than spelling it three times.

**A REGION THAT SCROLLS NEEDS `SIZE_EXPAND`, NOT `SIZE_FILL`.** A `ScrollContainer` lays its child out at that child's **combined minimum** unless the child's horizontal flags carry `SIZE_EXPAND` — `Control`'s default `SIZE_FILL` does not — and every content label on this screen is `clip_text`, so that minimum is *zero by design*. The stash shipped with only its vertical flag set and rendered as rows three pixels wide. `PreMissionScreen._scroller` takes its content and sets the flag itself now, so the growth law has one owner. Worth knowing beyond this screen: the failure is silent, it looks nothing like a missing flag, and a case asserting a list is *inside* a scroller is structurally blind to it.

**The job is the one thing on the card the player can EDIT** ([#742](https://github.com/Phaazoid/Godoiosis/issues/742), 2026-09-05). Its title area is a single-select picker over the whole `JobCatalog` — no certification, no cost, no gate, because #61 parked all three — with *none* leading the list, which is where every roster character actually starts: nothing under `Resources/Units/` authors a starting job at all. It writes through `Unit.set_sole_job`, never into `unit_instance.jobs`, and the card judges nothing: the screen performs the pick, exactly as it performs a gear move. One-at-a-time binds at the **roster** (ruling 10) so the model stays uncapped for enemies; a unit somehow holding two is named and the picker declines rather than silently truncating — the outcome that ruling rejected when it refused to cap the picker instead.

**A JOB CAN TAKE ARMOUR OFF, AND THAT IS WHY EACH OPTION CARRIES ITS COST.** Wear gates read the **body** — base → limb → jobs → effects — so a job's `stat_nudges` moves the answer, `_settle_stat_change` strips what no longer fits, and *picking the old job back does not put it back on*. It is reachable in shipped content: the Ballast Harness demands DEX 4 or less, Celest has DEX 4, Water Walker nudges DEX +3. So each option's tooltip states what picking it would do — the stats and DEF that move, the piece that comes off and what it demanded, the abilities gained and lost — built by `Unit.with_jobs`, which lends the unit the hypothetical body: it swaps the job list, **takes off the gear that body cannot hold**, asks, and puts all three back. The strip is not an extra; without it DEF previews unchanged and an ability granted by the doomed plate never shows as lost, which are the two readings the warning exists for. A **tooltip** rather than #745's in-place annotation, for a physical reason: the popup is its own window and it opens over the card's stat grid.

**The block reason lives on the card and nowhere else** (dev, 2026-09-05). `EquippableData.can_equip_reason` takes a **wielder**, so the stash — which has no unit selected — structurally cannot say whether a thing is usable. [#744](https://github.com/Phaazoid/Godoiosis/issues/744) built the sentence and the card's one helper became a pass-through, so every row and tooltip started naming the actual gap without an edit to either surface. The stash's own question is the *wielder-free* one — `ArmorData.requirement_text`, what a piece demands with nobody holding it — and the two share one grammar (`_gate_text`) so a gate cannot be spelled two ways on two surfaces. What the equip gate still cannot see is the **wield lock**: `can_wield_equipped` is a firing question, so a one-armed unit equipping a two-handed weapon is refused nothing here and finds out at turn 1 ([#776](https://github.com/Phaazoid/Godoiosis/issues/776)).

**Nothing in the card may demand width from its content.** The grid divides its row three ways and an `HFlowContainer`'s minimum width is its widest child, so one long ability name would walk the whole column out of the region — #685's failure, one surface over. Every content-bearing label is `clip_text` with the full string on hover, so the card's minimum size is a constant.

**Two extractions rather than second implementations.** `MissionStatusPanel.briefing_rows` is now the one builder for the objective and FAIL-IF rows, so the briefing *before* the battle and the status *during* it cannot word a condition differently. `UnitInstance.LIMB_SHORT`/`LIMB_FULL` moved beside the enum they name, `info_panel` being a scene script with no `class_name` whose vocabulary had gained a second reader.

**Begin carries its own refusal.** `commit_deployment`'s "Deploy someone first" speaks through `TurnBanner`, a plain child of Game, while this screen sits on a `CanvasLayer` — so under the menu that banner cannot be seen at all, and a dead Begin button would be silent. It disables at zero with the reason on hover; the banner still covers the Enter-on-the-board path.

**Repositioning is the board preview's own verb (#772).** Undeploy and the empty-cell click could change *who* was placed but not *where*, so moving one unit a single cell meant undeploy-then-redeploy, which puts them back on the first free cell rather than the chosen one. `Reposition` on the phase ring opens `game.enter_cell_pick_mode` over `MissionController.reposition_cells(unit)` — **the generic cell pick, not the dev tools' armed move**: it takes the legal cells up front and *marks* them, so "deployment tiles only" is enforced by construction and visible before the click, where `DevController.arm_move` carries no candidate set and refuses silently. #116's rescue haul already picks a destination cell this way.

**Swapping is allowed** (dev, 2026-09-05): a cell another *roster-drawn* unit holds is a legal target and the two trade places. Authored units are not swappable, for the reason Undeploy is gated the same way — they are the board's, additive to the draw (ruling 2c).

**And a reposition that breaks cohesion ejects the member there and then**, in the preview. `SquadManager.enforce_contact()` is the sweep, so this is not a new rule — it is a **third settle point** beside the end of a resolution pass and turn start, and the one the player reaches deliberately. The other two answer a displacement nobody chose; this answers the player placing a member out of their leader's reach on purpose, so the consequence is shown at the moment of the decision rather than a turn after it, with nothing on screen to connect it to.

The ring paid for it: `DEPLOY_GROUP` held one verb and so collapsed to a terminal slice named for its only child, which a second verb breaks. It is **Placement** now — what the pair answers together, where the unit stands and whether it stands at all.

**`MissionController._roster_units` keeps the roster in ENTRY order.** Deploying and undeploying *reparent* between `units_root` and `reserve_root`, so both lists reshuffle every time the player changes their mind and a grid drawn off either would reorder mid-decision. Worth knowing that this is currently belt-and-braces for the grid — `_refresh_cards` rebuilds only when the roster's size changes, so the order settles at build time either way — and is kept as the contract underneath rather than deleted; the store's own guarantee is what the suite pins.

### What the numbers say before you commit ([#745](https://github.com/Phaazoid/Godoiosis/issues/745))

**Most of the derived half was already built** — `ArmorData.mechanical_text` (#44),
`TransmutationData.mechanical_text` (#166) and `WeaponInstance.attack_detail` (#485) all read their
numbers at display time. What nothing pinned was the property those tickets exist FOR: that retuning
a value re-words the readout. Every case added here changes a number and asserts the text followed —
a snapshot of expected strings pins the exact opposite.

**Preview-at-decision is the new mechanism**, and it shows in the card's own stats grid rather than a
second readout: the value a player compares against has to be the one already in front of them. Two
hovers, two questions — gear IN HAND over a card asks *should this go to this one* (the decision the
screen exists for, and the one the stash cannot answer alone since `can_equip_reason` takes a
wielder), and an empty-handed hover over a carried row asks the smaller *what would equipping this
do*. **A refused piece shows its #744 sentence in place of numbers**, because previewing a piece a
unit cannot use is a lie and finding out at the click is the surprise both tickets exist to prevent.

**THE HOVER REBUILDS NOTHING**, and that is the same law #741 minted arriving from the other
direction: a redraw frees the row the cursor is on, and `mouse_exited` never fires on a freed node,
so the preview would stick for ever one frame after appearing. Pinned by NODE IDENTITY rather than by
text — a rebuild that restores the same values is invisible to a text compare, which a mutant proved.

**And the flavour wire was broken.** `WeaponInstance.make()` has never copied its template's
`description` and `copy_equippable` only copies instance-to-instance, so authoring a line on a family
reached nothing a player could hover. `Item.describe()` is the one door now and `WeaponInstance`
reads THROUGH to its template — re-wording a family re-words every weapon built on it, saved
scenarios included, with no migration. Only then were the seven base-weapon descriptions worth
writing. **Flavour never states a number**: a value in prose goes stale while the data stays right,
which `test_derived_readouts.gd` enforces over every authored weapon file. Weight reads 0 for everyone until #120's authoring pass (dev's call — the slot is shown so the gap is visible rather than forgotten).

### Gear moves, and the stash that owns it ([#741](https://github.com/Phaazoid/Godoiosis/issues/741))

**The phase's gear is a COPY, and `Loadout` is what holds it.** The stash used to be read straight off
whatever `RosterCatalog.resolve()` returned, and that is Godot's resource **cache** — the same object
for every resolve in a session. The first item moved out would have depleted the authored `Roster` for
every mission after it, which is ruling 3 broken by one drag. Nothing on disk was ever at risk (nothing
saves a roster); the cached object was. `Loadout.from_roster` copies through `copy_equippable()`, the
same grant the unit side already made in `apply_unit_state`, and `MissionController` builds one in
`deploy_roster` — where the Roster is already in hand — and drops it in `reset()`, the pair of edges
`_roster_units` lives on.

**Four directions are ONE function, because the stash is a null owner at either end.** `move(item,
from, to)` with `null` meaning the stash covers stash→unit, unit→stash and unit→unit without three
near-copies, and a drop back where it started is a no-op rather than a refusal — a drag lands on its
own row constantly.

**One rule, two inputs.** Clicking and dragging both ask `move_block_reason` and both act through
`move()`. A drag that judged for itself would be a second answer to "may this move" — the shape #744
had just finished collapsing one layer down, and the reason `GearDropZone` takes its judge and its act
as callables rather than reaching for the screen.

**Both refusals are the OWNING END's own sentence**, which is why `Unit` grew `add_block_reason` and
`remove_block_reason` with `add_item`'s bare `false` and `remove_item`'s silent prosthetic guard
derived from them. An installed prosthetic sits *in* the inventory, so a mover that did not read that
guard would let a player trade away someone's arm — and a mover that re-asked `is_installed_prosthetic`
and worded its own sentence would be the second gate #744 exists to prevent.

**A REDRAW NEVER RUNS INSIDE THE CLICK THAT CAUSED IT.** Every handler is reached from a row's own
signal, and a refresh frees every row to rebuild them — the emitting one included, which Godot refuses
outright ("Attempted to free a locked object"). The first move a player made would have errored rather
than happened. `PreMissionScreen._redraw` defers, and that is a rule for any surface that rebuilds
itself in response to one of its own children.

**The selection is DATA, never a row.** A successful move frees every row on screen, so a selection
holding a node dangles at the exact moment the feature starts working (#107's shape).

**The stash shows what a piece DEMANDS, never whether it fits** (dev, 2026-09-05). `requirement_text`
is the wielder-free question and the only one a list of loose gear can answer; the wielder-relative
sentence stays on the card, where there is a unit to validate against.

## Objectives: declared explicitly, located by zones

**Fork A was called twice, and the second call overrode the first.** The original plan was a `MissionData` resource wrapping a scenario — the *"authored mission vs. saved sandbox"* split, by analogy with `WeaponData` template-vs-instance. **That analogy was wrong** (dev, 2026-07-28): template-vs-instance exists because many instances share one template and diverge. A mission and its board are 1:1, so a wrapper is an extra hop and a pointer to keep valid, not a split. There is **one** board resource, `ScenarioData`, and there is no `MissionData`.

What a mission requires is a list on that resource:

```gdscript
@export var objectives: Array[MissionRules.Objective] = []   # empty = plain rout map
```

- **`ROUT`** — no faction hostile to the player has an active unit left.
- **`CAPTURE`** — every `ZoneManager.Kind.CAPTURE` zone claimed.
- **`EXTRACT`** — every surviving player unit inside a `Kind.EXTRACTION` zone.

Objectives **compose by AND**: every declared one must be MET. Authorable OR-composition is **unfiled scope** — it was #101's fork F and outlived that issue's close; see *What #101 did NOT ship* below for the grouping question (a flat flag can't express *"A and (B or C)"*).

An **empty list is a plain rout map**, which is what every scenario saved before objectives existed still is — that fallback is why the change broke nothing.

### Why explicit, when implicit worked

Slices 3–4 originally derived the objective from what was painted: a CAPTURE zone on the board *was* a capture objective. That was neat and it was wrong (dev, 2026-07-28), for three reasons that all showed up as soon as the question "how do I add a rout clause?" was asked:

1. **Rout has no geometry**, so an implicit-from-zones scheme cannot express it at all — rout could only ever be the fallback, never a clause alongside a capture point.
2. **A mis-picked Zone Kind silently rewrote the win condition.** A patrol zone typo'd as CAPTURE turned a rout map into a capture map with no diagnostic.
3. **No decorative or optional zones** — painting was load-bearing, so geometry could never be authored ahead of the rule that uses it.

Zones now supply **geometry only**. The cost is a second source of truth, which is what the guard below exists to close.

### Zones overlap, and a zone's kind locks at creation (2026-08-12)

Two authoring rules replaced the original one-zone-per-cell store: **zones overlap freely** — the motivating case is a patrol area containing a capture point — and **a zone's kind is fixed when its first cell is painted** (repainting never retypes; changing kind = delete and repaint, which closes the trap where continuing to paint under an existing name with a different Kind picked silently converted the whole zone). Consequences: "the zone at this cell" stopped being a well-formed question — the kind-sensitive reader is `MissionController.capturable_zone_at(cell)` (the uncaptured CAPTURE zone there, which the menu gate and `CaptureAction`'s stamp both read) — and brush erase is **scoped to the picked zone**, since an unscoped erase could never carve one zone out from under another. Where two capture zones overlap, claiming one leaves the other capturable from the shared cell.

### `Kind.DEPLOYMENT` — where the player's force starts (#736)

The fourth kind, and the first that is neither an AI leash nor an objective: it is **where the pre-mission phase may place the units the roster offers**, painted like any other zone and overlapping freely — a deployment area inside a patrol zone is a reasonable board. It draws plainly in both views, like CAPTURE, rather than being gated to the Tile Brush tab like PATROL: that gate exists to keep AI internals out of play, and where the player may stand is the opposite of a secret.

**It disappears when the battle starts** (dev, 2026-09-04). Not by a second visibility input — `redraw_zones`' existing `hidden` list already means *this zone has stopped being information*, which is exactly what a deployment area becomes once placement is over. `MissionController.hidden_zone_names()` is the one answer to that list (claimed capture zones, plus every deployment zone once a turn has begun), and `_begin_turn` is the single door every arrival takes — mission select, restart, resume, sandbox — while the dev-tools Load path takes none of them. So the zone is visible while authoring, visible for the whole of the pre-mission phase -- which sits between the load and that door -- and gone from turn 1 onward, with nothing #737 or #739 had to add. That is the rule paying for itself twice: the phase is exactly the stretch in which a deployment area is still information, and the list already said so.

Two `BoardLint` findings guard the pair, both gated on a roster being named (a cap on a board with no pool caps nothing): a board that offers a roster and paints no deployment zone (**BLOCKS**), and a cap larger than that zone's deduped cell count (**DEGRADES** — fewer units deploy than the author asked for, and the mission plays).

**That first tier MOVED, and the move is the rule working.** #736 filed it at DEGRADES because a tier is judged against what the code in the tree does with the board, and #736's tree read no roster at all — such a board booted with its authored cast and played exactly as before. #737's draw is what changed the answer: no zone means nobody deploys, so a board whose player force *is* the roster opens on a turn with nothing to command, the faction auto-skip bounces PLAYER→ENEMY forever, and `is_contested` never latches (it needs an active player unit), so there is no defeat either. No win, no loss, only Quit — which is `_check_objectives`' own shape, a requirement declared with no geometry to satisfy it.

### The guard: declared without painted

An objective ticked with no matching zone painted can never be met — the mission is unwinnable. Three things catch it, all reading the one rule (`MissionController.objectives_missing_geometry`):

- **Authoring time.** The dev Scenario tab's objective checkboxes render a live warning naming every declared-but-unpainted objective. This is the one that matters; it is cheaper than finding out mid-playtest.
- **On demand.** Scenario ▸ Properties ▸ **Check board** ([#390](https://github.com/Phaazoid/Godoiosis/issues/390)) reports it alongside the board's other authoring faults, and CI runs the same pass over every shipped mission.
- **Load time.** `MissionController.set_objectives` `push_error`s once per missing objective.

At runtime the unpainted objective reads **PENDING, not NONE** — deliberately. The map really is unwinnable, and silently dropping the objective would quietly convert a broken map into a *different, playable* one, which is a far worse failure than a loud one.

## Losing on purpose: the lose-condition list and the turn clock ([#101](https://github.com/Phaazoid/Godoiosis/issues/101), 2026-08-26)

#96 gave the game exactly one way to lose: the player has no active unit left. That is the floor, not the design — every interesting mission fails in a way that is *not* "everyone died". **The asymmetry is the point: win conditions are things the player DOES, lose conditions are things they fail to PREVENT**, and they are what make a map exert pressure. A capture point with no clock is a puzzle you solve at leisure.

**Fork A was called their own list** (dev, 2026-08-26), not negated objectives:

```gdscript
@export var lose_conditions: Array[MissionRules.LoseCondition] = []   # empty = only the floor
@export var round_limit := 0                                          # 0 = no limit
```

*"Protect unit X"* and *"unit X must survive"* really are the same statement, so the reason is not expressiveness — it is that the two are asked at **different moments** (an objective is checked for completion, a lose condition continuously) and that **a failure has to name a reason** for the banner, which an objective never does.

- **`SQUAD_LOST`** — the #96 floor. Always on, never authored.
- **`ROUND_LIMIT`** — the objectives were not met within `round_limit` rounds.
- **`NONE`** is a sentinel meaning *nothing fired*, not a condition.

**Lose conditions compose by ANY**, stated rather than inherited from a loop's shape: the first one that fires ends the mission. Losses are rarely conjunctive.

**`MissionRules.AUTHORABLE` is what the Scenario tab offers**, and it is a const rather than "every enum value" — so the sentinel and the always-on floor are excluded by a *decision* that a reader can see, the same way `CAPTURE` sits explicitly in `AIArchetype.MAIN_ACTION_NEVER`.

### The order two conditions are asked in

`evaluate` takes `failure` exactly as it already takes `progress` — `MissionController` computes it, the rule stays pure — and the order is load-bearing at both ends:

1. **The squad wipe is asked FIRST**, so mutual destruction is still a DEFEAT (unchanged doctrine) and a squad lost on the round the clock expires reports **SQUAD_LOST**, the more concrete thing that happened.
2. **Every VICTORY path is asked BEFORE an authored failure.** Finishing on the last allowed round is finishing *in time*; a clock must not steal a win the player earned.

`MissionController.failure_for` names the reason and `evaluate` decides the outcome. Both read the one `faction_has_active_units` predicate — `evaluate` keeps its own wipe branch because callers that pass no failure (the headless Play API) still need it.

### Where the clock lives — fork B

**The count is battle-scoped, the limit is authored**, the same split objectives already have: `MissionController._rounds_elapsed` (cleared by `reset()`, saved with the #87 snapshot) against `ScenarioData.round_limit`. A **round**, not a turn: the cycle is N-faction and rebuilt from the board each hand-off, so a round is the only stable unit.

**There is ONE increment point**, `game._on_round_completed`, beside the terrain tick. `TurnManager` emits `round_completed` before `turn_started`, so the very next `check()` — turn start, after the downed clocks tick — is the one that sees it. **No new evaluation seam was added**; fork E's three points still are the three points.

`round_limit = 0` means **no limit**, and that sentinel *is* the field's own default, so a board that never authored a clock cannot read as one that authored a zero-round one. A declared `ROUND_LIMIT` with no limit is the **unpainted-geometry guard's twin**: `MissionController.lose_conditions_missing_setup` is the one rule, read live by the Scenario tab, shouted once by `set_lose_conditions`, and reported as BLOCKS by `BoardLint`. It reads as broken and says so — it does not fire, and it is not silently dropped.

### What the player sees — forks C and D

Fork D's prerequisite was already built: [#134](https://github.com/Phaazoid/Godoiosis/issues/134)'s `MissionStatusPanel`. The clock is a row on it under its own **FAIL IF** header — a countdown listed among the objectives reads as something to achieve — and it is built off the declared list, so the next condition needs no panel edit.

**One bug this surfaced, worth knowing because it is the shape a HUD gate always has:** `game.refresh_mission_status` hid the whole panel on `objectives.is_empty()`. A mission authoring a clock and *no* objectives therefore rendered no countdown at all — precisely the unplayable state fork C exists to prevent. The gate asks about lose conditions too now.

**Fork C was called: colour the clock as it runs out, no modal** (dev, 2026-08-26). The threshold is a feel value, so it ships as a knob rather than a guess — `MissionStatusPanel.URGENT_ROUNDS` / `URGENT_COLOR`, two `GameKnobs.CLASS_KNOBS` rows under a **Mission** sub-tab. They are class rows and not property rows for a structural reason worth recording: `KNOBS` resolves node paths against the **Battle3D host**, and the status panel is 2D UI under the game's own `ui_layer`, so the node table structurally cannot reach it. Both rows re-apply through `game.refresh_mission_status` when written, or the slider would move nothing until the next turn — which is exactly when it is being dragged (#324's rule).

The **banner names the reason**: `MissionRules.defeat_reason` is the one place the wording lives, so the card holds no second copy of *"Your squad has fallen."*

### What #101 did NOT ship

**#101 is CLOSED** (dev, 2026-08-26): with the seam built, the rest of it was three unrelated features sharing one design capture, so they were split out and it closed rather than becoming an umbrella. That number is history now — the successors are:

- **[#571](https://github.com/Phaazoid/Godoiosis/issues/571) — defend a point.** An enemy taking a friendly zone. The first non-player-faction objective, and what *The AI and CAPTURE* below is waiting on. Its real cost is not the condition: **a captured zone has no OWNER** (`_captured_zones: Array[String]`, and `CaptureAction.execute` discards its own actor), so "captured" is a per-zone boolean that only works while the player is the only faction that can claim one.
- **[#572](https://github.com/Phaazoid/Godoiosis/issues/572) — protect a unit.** Escort and VIP. Same shape: the rule is nearly free on this seam, and the gap is that **`ScenarioUnitEntry` has no stable identity field**, so a mission has nothing to point at when it names a person.
- **Authorable OR-composition (fork F)** — grouped OR-lists inside an AND, so a mission can be won by *either* taking the point *or* routing. **Not filed**, deliberately: the lean was always *arriving only when a real mission design wants it*, and this section is the record until one does. A flat `require_all` flag is the version to avoid — it cannot express *"A and (B or C)"* and gets outgrown.

The Play API's blindness to all of this went to **[#46](https://github.com/Phaazoid/Godoiosis/issues/46)**, the Play API evergreen, rather than becoming a fourth issue.

Previewing *"this move loses"* in the queue is still fork B's question, now that the clock it was parked against exists.

## `MissionRules.Progress` vs `MissionRules.Objective`

Two enums that are easy to confuse, so: **`Objective`** is *what is required* (ROUT/CAPTURE/EXTRACT), **`Progress`** is *how far along the mission's requirements are as a whole* (NONE/PENDING/MET). `Progress` was called `Objective` in slice 1 and was renamed when real objectives arrived.

`NONE` is not `PENDING`. Conflating them is exactly how "this scenario has no objective" becomes "this scenario is instantly won" — the same class of bug as the `contested` latch below.

## Doctrine

### An authored objective is the ONLY way to win

If a scenario declares objectives, routing the enemy wins nothing unless `ROUT` is one of them. The first draft had victory as `objective OR rout` — a consolation win so that killing everything while unable to reach the point couldn't softlock the map. **Overruled (dev, 2026-07-28): lockout is a level-design problem.** Maps get built so the player cannot lock themselves out; a map where they can and do should be a *loss*, which is [#101](https://github.com/Phaazoid/Godoiosis/issues/101)'s business, not a rule that hands out a win nobody earned.

### Mutual destruction is a DEFEAT

If the last player unit and the last hostile fall in the same resolution pass, the mission is **lost**. `MissionRules.evaluate` checks defeat first for exactly this reason. A wipe you don't survive is not a win — and the alternative would reward trading a whole squad for the last enemy, which is the opposite of what the Will/death ladder is for.

### `contested` — a dev scratchpad is not a mission

A board holding only enemies satisfies "the player has no active units" perfectly, and it is obviously not a defeat. The board alone cannot distinguish **wiped out** from **never here** (`present_factions` drops factions whose units are all dead, so the record of who started is gone).

So the caller latches it: `MissionRules.is_contested(board)` is true while both sides have a commandable unit, and `MissionController` remembers that it was ever true. `evaluate` is *handed* that latch rather than reading it live — a live read could never end a mission, because the moment one side is wiped the board stops being contested.

The practical effect: **dev sandbox boards stay inert.** Spawn five enemies in the Unit tab with no player units and nothing fires. No `dev_mode` flag was needed.

### Extraction counts the DOWNED

"Surviving" means **not dead**, so a downed unit *inside* an extraction zone is extracted exactly like an active one — alive and in the zone means they get out. What blocks the objective is a living unit *outside* the zone, and a downed one out there cannot walk in on its own: someone has to reach them with `RescueAction`, which revives to 1 HP and ACTIVE.

**Zero surviving players reads PENDING, not MET (2026-08-12)** — the `counts.y == 0` twin of capture's unpainted-geometry guard. Without it `0 == 0` counted as everyone-extracted, which ticked Extract on the HUD during load (`set_objectives` refreshes the HUD before units spawn; `apply_scenario` now re-pushes the HUD once the board is fully built). For `evaluate()` the guard never decides anything — DEFEAT is checked first.

That is the whole design of the rescue-under-pressure mission. Counting only ACTIVE units would let you leave a body behind and still win (fork C: **surviving**, not starting).

### Capture is instant and uncontested

One main action, standing anywhere inside the zone, and the **whole zone** is claimed — a multi-tile objective is one objective, not N of them. Nobody takes it back (fork D). Hold-for-N-turns and enemy re-capture are a strictly bigger design that needs enemy objectives to mean anything first.

## When the rule is asked — fork E: pass-end, not turn-end

`MissionController.check()` runs at every point board state can change *and settle*:

1. **End of a resolution pass** (`OrderExecutor.execute_orders`, right after `_process_downed_pending` and *before* its squad-validity guard, so a squad that wiped itself can't skip the check) — covers damage, downs, deaths, counters, Crisis, and movement into an extraction zone.
2. **After the end-of-turn burn** (`game.end_turn`) — a burning tile can take the last unit.
3. **Turn start, after the downed clocks tick** (`game._on_turn_started`) — an expiring downed countdown kills, and that is the one death that happens outside a pass.

Turn-boundary-only evaluation would have been simpler and dishonest: **a friendly AoE can down your own last unit mid-pass**, and the game should say so at that moment rather than taking more orders for a squad that no longer exists.

`AIController.take_faction_turn` guards on `is_over()` so a squad that wipes the player stops issuing orders behind the end-of-mission card.

**Crisis needs no special case.** Crisis fires at the moment of a would-be-down and stands the unit back up ACTIVE, so `faction_has_active_units` is already correct when the pass settles. No self-revive from a *downed* state exists, which is what makes all-downed genuinely terminal.

### The infinite turn-pass this replaced

`game._on_turn_started` auto-skips a faction with no commandable units, guarded so an all-downed board can't recurse forever. That guard existed specifically to survive the exact state that *should* be a loss; the predicate was right there and nothing treated its result as an outcome. It **stays** — an uncontested sandbox board can still reach all-downed, and the guard keeps that inert rather than hung.

## Fork B: the queue does not preview the win

Law #2 says the queue never lies — it does not say the queue must surface every consequence. The lethal skull already tells you the last enemy dies; declining to *also* tag it "this wins" withholds nothing and asserts nothing false.

Capture turned out to be the cheap case to preview (a cell test against the resolved destination) and it still wasn't built — the question is better asked alongside [#101](https://github.com/Phaazoid/Godoiosis/issues/101)'s clock, because *"this move loses"* is the version that actually matters for fairness. **That clock now exists (2026-08-26) and the question is still open**: fork C shipped the countdown plus a colour cue as the whole warning, deliberately short of previewing a losing move.

## Mission start resets battle state (the #87 seam, finally executed)

The persistence seam has always said battle-scoped state resets each mission — but **nothing had ever fired a mission-start event**, so that rule had never run. `MissionController.reset()` is the first thing to do it, called from `ScenarioManager.clear_board()`.

**Resolved by [#87](https://github.com/Phaazoid/Godoiosis/issues/87) (2026-07-30), and the answer was NOT a flag on the load.** A scenario file *is* its board, so a load restores whatever the file recorded, and an authored mission simply recorded nothing — `reset()` runs first (via `clear_board()`), then `MissionController.restore_progress()` writes a mid-battle snapshot's captured zones, `contested` latch and round count (#101) back over the blank slate. `outcome` is deliberately not saved: it is derived from those plus the board, so the next `check()` re-reaches it.

The reset side is **real and exercised since [#737](https://github.com/Phaazoid/Godoiosis/issues/737)** — the roster → board flow above, where units arrive off a mission's roster carrying no battle state *by construction*, because every battle-scoped field lives on the transient `Unit` or on a non-`@export` `WeaponInstance` var. *(Its character-file half is real since [#177](https://github.com/Phaazoid/Godoiosis/issues/177): the cast lives in `Resources/Units/` and an authored mission re-reads those files on every load. What is still future is results carrying **between** missions — and the mission-boundary concept that needs is [#70](https://github.com/Phaazoid/Godoiosis/issues/70)'s debt, not a roster feature.)*

`clear_board()` also empties the zone store, which `load_scenario` refills — without that, the Sandbox board inherited the previous mission's zones (and therefore its objectives' geometry).

## Mission select

The game boots into `MissionSelectScreen`, not a board. `TestBoard` was retired as the boot path (dev, 2026-07-28) and is a labelled dev row on the menu; `game.spawn_sandbox()` is its one remaining call site, so retiring it entirely is still a one-line deletion.

- **Missions** are scenarios under `Scenarios/missions/` — the folder convention `Scenarios/fixtures/` already set. `save_scenario` already creates directories, so saving a scenario named `missions/Camp` needs no new code.
- **Scenarios & fixtures** (everything outside `missions/`) are listed below the missions and are selectable — during development these *are* the content.
- A board arriving from the menu has nobody's turn *started* (`load_scenario` only restores whose turn it *was*), so `MissionController._begin_turn` fires the banner and `start_faction_turn`. Without it a mission saved on an AI faction's turn would sit there doing nothing, because `turn_started` only ever fires from `TurnManager.end_turn`.
- **A turn HANDOFF resets actions; a menu arrival trusts the file ([#144](https://github.com/Phaazoid/Godoiosis/issues/144)).** `reset_faction_actions` fires from `game._on_turn_started`, not from `start_faction_turn` — the menu paths call the latter, and a resumed save's restored `Squad.has_acted` must survive the arrival. It lived inside `start_faction_turn` until #144, which meant every menu-driven load silently handed acted squads their actions back; nobody saw it because only the dev-overlay Load (which skips `_begin_turn`) had ever loaded a mid-battle snapshot. Pinned both directions by `tests/flow/test_turn_handoff_reset.gd`.
- **...AND THE HAND-OFF SHEDS WHAT NOBODY EXECUTED** (dev ruling, 2026-09-03, out of [#709](https://github.com/Phaazoid/Godoiosis/issues/709)). The same call now drops every OTHER faction's queued orders. An order queued and not run used to survive the whole enemy turn — and it could never happen, because the reset above discarded it unexecuted at that faction's own next turn — so while it stood, `PlanResolver` seeded that unit from `get_projected_destination()` and placed it at the queued destination, while `queue_action`'s whiff gate placed a foreign unit where it stands. **Two answers to where the player is, during the one turn something else is aiming at them.** Nothing is lost by shedding early; only the resolver, the gate and the AI could observe the difference, and they disagreed. It rides `reset_faction_actions` because that is the one step BOTH walks share — `game._on_turn_started` and both of `play_session`'s end-turn paths — where `TurnManager.end_turn` knows no squads and a new signal would be wired in one walk and not the other (#714's shape). Through `SquadManager.shed_orders`, never a raw `action_queue.clear()`: the raw clear emits nothing, which is why an un-executed move's path arrow and projected ghost outlived the order that drew them.


## Player save slots (#144)

The [#87](https://github.com/Phaazoid/Godoiosis/issues/87) snapshot got its player doors on 2026-08-11: **Save Game** / **Load Game** rows on the pause menu, and a **Load Game** row on the title screen (shown only when a slot is filled). Three fixed slots at `user://saves/slot_N.tres` — `user://` because `res://` is read-only once exported, and anything under `Scenarios/` becomes a selectable board via the folder scan and #9's suite (the `BugReporter` precedent, and the same pin shape guards it in `tests/flow/test_save_slots.gd`).

- A slot is a `SaveGame` resource: the full `ScenarioData` snapshot (**`authored = false`** — the #177 reference mode records nothing for cast units, which is exactly wrong for resume) plus `mission_path`, `saved_at`, and `Build.version()`.
- **Resume aims `last_loaded_path` at the ORIGIN mission**, so Restart and F2 return to the mission start and no dev tool can ever point Update at a slot.
- Save rides Restart's gate (missions only -- a sandbox save would have no origin), and since #739 it is REFUSED during the pre-mission phase as well: `capture_scenario` walks `units_root`, so the reserve is invisible to it and a save taken while placing would come back with the rest of the roster gone. The gate is in `save_to_slot` rather than on the pause-menu row; the row greys itself off the same question. Whole-campaign saving (mission-to-mission carryover) is deliberately out of scope here; it needs [#70](https://github.com/Phaazoid/Godoiosis/issues/70)'s mission boundary and is filed separately.
- The queued action plan is still deliberately unsaved (#87's exclusion); the save screen says so to the player.
- The UI is `SaveLoadScreen` (one card, SAVE/LOAD modes) + `ConfirmCard` (the player-facing, in-viewport twin of `DevWidgets.confirm_delete`) for overwrite and lost-progress confirms.

The end-of-mission banner offers **Retry** (hidden when the board wasn't loaded from disk), **Mission Select**, and **Stay** — which unlocks the finished board for inspection with the dev tools while leaving the mission over and the turn cycle stopped.

## The AI and CAPTURE

`CAPTURE` sits in `AIArchetype.MAIN_ACTION_NEVER` for all three archetypes, and `tests/law/test_ai_action_coverage.gd` forced that to be an explicit decision.

**This is not the Burrow-style drift** (Rev shipped for Rushdown 2026-08-06; Burrow followed in
[#726](https://github.com/Phaazoid/Godoiosis/issues/726), 2026-09-03 — the drift is closed, and
the example is now historical). There is nothing for an AI faction
to *win* by capturing, because enemy objectives are out of #96's scope — the point is the player's. The AI contests it positionally, which it already does: Rushdown walks into the approach, and a Sentry squad zoned over the point defends it with no AI code at all. Revisit when non-player factions get objectives of their own, which is [#571](https://github.com/Phaazoid/Godoiosis/issues/571), *defend a point*.

## Known gaps

- **The Play API cannot see authored objectives, and now cannot see lose conditions either.** `play_session.mission_outcome()` calls the same `MissionRules.evaluate`, but with no `MissionController` it passes `Progress.NONE` and no `failure` — so headless runs evaluate every board as a rout map with no clock, and there is no `capture` command to queue. Headless coverage of the loop stops at rout/defeat. The clock is precisely the kind of rule headless play is good at pressure-testing, so this is worth closing before the conditions with geometry land. **Tracked on [#46](https://github.com/Phaazoid/Godoiosis/issues/46)**, the Play API evergreen — it is a headless-interface gap rather than a mission one, and it already had a home.
- **The end-of-mission banner's three choices are untested.** `_end_mission` awaits `MissionEndBanner.show_banner`, and a button press cannot be given headlessly, so RETRY (reload + re-begin the turn), MISSION_SELECT (back to the front door) and STAY (unlock the board, mission stays over) are verified only in play. Coverage stops at the board reaching `MISSION_OVER` with input locked. *(The rest of `MissionController` IS covered as of 2026-07-29 — `tests/flow/test_mission_controller.gd`, 31 cases on a real game scene, pinning both latches, AND-composition, whole-zone capture, extraction counting the downed, declared-but-unpainted reading PENDING, and DEFEAT beating a met objective in the same pass; falsified against seven mutations, each caught by its own test. The "game scene segfaults in the runner" belief that had blocked this was false — see [#114](https://github.com/Phaazoid/Godoiosis/issues/114).)*
- ~~**No mission-status UI.**~~ BUILT [#134](https://github.com/Phaazoid/Godoiosis/issues/134) (2026-08-11) — `MissionStatusPanel` shows every declared objective and its live progress. The prerequisite [#101](https://github.com/Phaazoid/Godoiosis/issues/101) fork D named is now in place.
- **`CaptureAction`'s icon is a placeholder** (the board target marker).

## Not in scope for #96

Campaign layer (mission ordering, unlocks, roster carried between missions, between-battle recovery) · objectives for non-player factions · story/briefing framing, rewards, acquisition · ~~**lose conditions beyond the last unit falling**~~ — the SEAM and the turn clock landed as [#101](https://github.com/Phaazoid/Godoiosis/issues/101) (2026-08-26, see *Losing on purpose* above); defend-a-point is [#571](https://github.com/Phaazoid/Godoiosis/issues/571) and protect-a-unit [#572](https://github.com/Phaazoid/Godoiosis/issues/572).

## What this unblocks

- [#70](https://github.com/Phaazoid/Godoiosis/issues/70) — between-missions-only job swap. **Satisfied by construction since [#742](https://github.com/Phaazoid/Godoiosis/issues/742) (2026-09-05)** rather than enforced: the pre-mission phase is the only player-facing place a job changes, so there is no mid-mission swap to refuse. The dev editors stay unrestricted, which is correct — they are dev tools. Worth re-reading the ticket on that basis; what it may still want is the CAMPAIGN half (progress pausing, dormant jobs), which needs #186 and belongs with the trio in [jobs.md](jobs.md) *Parked*.
- [#87](https://github.com/Phaazoid/Godoiosis/issues/87) — the mid-battle-save split above. **BUILT 2026-07-30**; `restore_progress()` is the restore half, and `ScenarioData` now carries the captured zones, the `contested` latch and the round count (#101).
- ~~[#101](https://github.com/Phaazoid/Godoiosis/issues/101) — lose conditions.~~ **BUILT and CLOSED 2026-08-26** (see *Losing on purpose* above); it did reuse `check()` and the objectives list wholesale, exactly as predicted. Its unbuilt half became [#571](https://github.com/Phaazoid/Godoiosis/issues/571) and [#572](https://github.com/Phaazoid/Godoiosis/issues/572).

Cross-refs: [level-concepts.md](level-concepts.md) (the set-piece pool missions will draw from), [will-and-death.md](will-and-death.md) (why all-downed is terminal, and why extraction counts the downed), [ai-tactics.md](ai-tactics.md), [resolution-pipeline.md](resolution-pipeline.md) (the persistence seam).
