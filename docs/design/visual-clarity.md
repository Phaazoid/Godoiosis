# Visual Clarity — working guidelines

Home for the board-legibility & action-queue readability pass. Umbrella issues:
[#44 Visual Clarity Overhaul](https://github.com/Phaazoid/Godoiosis/issues/44) (board side) and
its child [#49 Action Queue UX](https://github.com/Phaazoid/Godoiosis/issues/49) (the queue widget).

This is a *guidelines* doc, not a spec — it captures the principles we're holding the work to,
plus the running order of the queue-UX checklist. Update it as items land.

**Canon checked through #432 (2026-08-21).**

## Principles

1. **The queue never lies (Law #2), and now it must also be legible.** Every row previews exactly
   what execution does. Clarity work may *reformat* what a row says, never *change* what it claims.
   If a number is shown, it comes from the resolved outcome (`action.resolved`), never a re-computation.

2. **One motif per meaning — keep them distinct.**
   - **Flash** (pulsing brightness, like the Execute button) = "act now / attention here."
   - **Glow / steady highlight** = "this is the thing you're hovering / it's related."
   - **Mute / desaturate** = "this is inactive or out of focus" (e.g. non-active squad icons).
   - **Color-code** = validity (valid vs invalid target/cursor), reusing
     `CursorController.CursorState.VALID/INVALID`.
   - ~~**BREAK banner**~~ — **RETIRED 2026-08-09 with the BREAK doctrine's repeal** (resolution-pipeline
     R9, [#155](https://github.com/Phaazoid/Godoiosis/issues/155)/[#158](https://github.com/Phaazoid/Godoiosis/issues/158)):
     plans no longer diverge, so the moment this motif marked cannot occur. Never built. The full-screen
     flash is now an unclaimed motif — if a future meaning wants it, it still must be reserved for
     exactly one thing, or the signal dies.
   Don't let two motifs collide (e.g. don't also *flash* something that's merely highlighted).

3. **Most important info first, at a glance.** A row should read left-to-right in priority order:
   who → does what → to whom → for how much → with what consequence. Lethality (DOWNS/MAIMS/KILLS)
   and elemental reactions are consequences and sit after the numbers.

4. **Progressive disclosure over density.** When a section gets crowded (volleys, long combos),
   collapse-and-expand beats cramming. The default view is the summary; detail is one click away.

5. **Numbers carry units of context.** A bare `-5` tells you the hit; `12 -> 7` tells you whether
   it matters. Prefer showing the *consequence* of a number, not just the number.

6. **The tooltip doctrine — never require memorizing the table** (from the 2026-07-04 transmutation
   grill). Hovering any elemental effect on the field shows an easy-access list of what it reacts
   with; hovering any carried rune, same deal. The elemental/transmutation system is deliberately
   too big to memorize — reactive tooltips are the contract that keeps discovery fun instead of
   homework. (Board-side #44 scope; pairs with the codex's "public geometry, private lexicon"
   policy in [transmutation-model-proposal.md](transmutation-model-proposal.md).)

   *Progress ([#135](https://github.com/Phaazoid/Godoiosis/issues/135), 2026-08-11):* the
   unit-state and tile halves are BUILT — state icons (hover card + inspect bar) explain
   themselves in place, and **every real tile carries a hover card** (playtest round 2: icon +
   kind header, states with live clocks, and which elements can touch it — filtered through
   `TerrainReaction.applies_to_tile`, the resolver's own deposit gate), all reading
   `Glossary.short` (`Classes/core/Glossary.gd`, the one term registry). Every attack row's
   readout ends with its targeting channel — `(unit)` / `(tile)` / `(unit/tile)`, one spelling
   on `AttackData.targets_text`. The global tooltip delay went 0.5 → 1.0s the same round (the
   note `project.godot` cannot carry: dev, *"most people know what attack and move mean"* — the
   readouts stay, they just stop popping up mid-flow). Still open here: the rune "reacts-with"
   list — #167's inventory tooltip shows recipe/payload/strain, not reactions.

## #49 Action Queue UX — CLOSED, all items shipped

**Found stale during the 2026-07-16 design-doc sweep:** this checklist read as an active running
order with only item 2 checked off, but issue #49 is closed and every item is built — verified
directly against `Classes/ui/queue/SquadActionQueueControl.gd` / `ActionQueueRow.gd` /
`AttackAction.gd`. Kept as a build-record (the principles above stay live guidelines):

1. **More info per row — damage + target HP before -> after.** — **DONE.**
   `AttackAction.get_outcome_summary()` renders `-N (before->after)`, with a dedicated honest form
   for CRISIS rows (extended alongside #57).
2. **Counters render after all attacks.** — **DONE** — `ActionQueueDisplayEntry.build_for`
   builds COUNTER as its own section, last, with skipped counters hidden.
3. **Group a volley into one expandable row.** — **DONE** —
   `SquadActionQueueControl._collect_volley_group` / `_add_volley_group`, per-actor expand/collapse
   state (`_expanded_actors`), `ActionQueueRow.setup_volley_summary`.
4. **Outer scrollbox for the whole queue.** — **DONE** — `_section_scrolls: Array[ScrollContainer]`,
   one per section plus the outer list.
5. **Click-drag to reorder attacks.** — **DONE** — full drag machinery (`_drag_row` / `_drag_section`,
   `reorder_attacks_requested` signal) in `SquadActionQueueControl`.

## Tooltip / popup legibility — open items (added 2026-07-29)

Collected at @Phaazoid's direction while building [#90](https://github.com/Phaazoid/Godoiosis/issues/90) and [#88](https://github.com/Phaazoid/Godoiosis/issues/88). All three are "the text is there but the player can't use it" problems, which is this umbrella's remit.

1. **Popup line width — DONE 2026-07-29.** Long tooltips ran off the right edge of the screen and became unreadable (found by feel-test on a new ability description). Godot's built-in tooltip is a `Label` with autowrap **off**, and autowrap is a property rather than a theme item, so there is no global switch — every tooltip in `Classes/ui/` now routes through `UiText.wrap()` (`TOOLTIP_WIDTH`, playtest-tunable). Pinned at **runtime** by `tests/ui/test_tooltip_rendering.gd`, which populates the real inspect panel with a unit dressed in the authored content that caused the regression, walks the live `Control` tree, and asserts every rendered tooltip is already in wrapped form (`wrap(t) == t`, valid because `wrap` is idempotent). Known trade-off: a single word longer than the width overflows its line rather than breaking mid-word — `wrap` leaves it alone, so it does not read as a violation.

  > **Corrected 2026-08-01 (suite audit).** This was originally pinned by a **source-level** law at `tests/law/test_tooltip_wrapping.gd` that grepped each `Classes/ui/` function for the token `UiText`, justified by "this layer has zero runtime coverage (#114)". That premise was **false** — [#114](https://github.com/Phaazoid/Godoiosis/issues/114) measured the game scene instantiating cleanly under the runner, and `tests/ui/test_game_scene_smoke.gd` had said so since 2026-07-29. The runtime replacement is strictly stronger: falsified against a site that wrapped at the **wrong width**, which the source scan could not see because `UiText` still appeared in the function.
2. **A rune has no meaningful inventory tooltip — DONE 2026-08-10 ([#167](https://github.com/Phaazoid/Godoiosis/issues/167), filed during #166 playtest, a #44 sub-issue).** `inventory_panel._tooltip_for` had a `WeaponInstance` branch and an `ArmorData` branch; a `RuneData` fell through to the generic case and showed only its name plus flavour text. The new branch is a readout, not new machinery: a temper/size/used-capacity headline, then one line per inscribed carving built from the exact `attack_detail`/`attack_block_reason` pair #166 built for the Transmutation submenu's rows (same detail-then-reason order, so the two surfaces read consistently) — a carried-but-unequipped rune, or one force-stripped by a maim, now explains itself the same way an equipped one's submenu does. Read against the panel's own unit (the tooltip's wielder), since the numbers are per-wielder. Pinned by `tests/ui/test_rune_inventory_tooltip.gd`, sibling fixture to #166's `tests/ui/test_menu_catalogue_rows.gd`, asserting on the rendered slot tooltip rather than the builder function in isolation.
3. **The Transmutation submenu reads as a catalogue, not just a picker — BUILT 2026-08-10 ([#166](https://github.com/Phaazoid/Godoiosis/issues/166); the item was #88's, filed as a ticket out of [#157](https://github.com/Phaazoid/Godoiosis/issues/157)'s plan and a #44 sub-issue).** #157's equip gate killed the fully-dead-rune case but is "at least one channelable carving", so a partial rune's dead entries permanently owe the player a reason — the gate made this readout more necessary, not less. Both dev-requested parts shipped, and the mechanism under them is deliberately general:
   - **Un-channelable carvings are LISTED and greyed with a reason.** `RuneData.choice_attacks` is now the catalogue (every inscription), matching `WeaponInstance.secondary_attacks`, which always returned all extras and let the row disable them; whether a given carving can be paid for is asked per entry.
   - **Every row carries a hover readout** — recipe · payload · strain, derived per wielder (`TransmutationData.mechanical_text`, the carving's answer to the role `ArmorData.mechanical_text` plays for a worn piece). Deliberately derived rather than authored: an `AttackData.description` for prose can be appended as one more line whenever it is wanted, at the same cost.
   - **The generalization, which is the reusable part: a menu can only grey what it can explain.** The reason a row is dead belongs to the data layer, not the menu — `EquippableData.attack_block_reason(wielder, attack)`, answered per kind (a weapon reports readiness in its family's own `status_text()` words, a rune reports aura), with `Unit.is_attack_fireable` **derived** from it so the refusal and its explanation can never drift (Law #4). The menu side is one row builder, `MainActionMenu._entry(name, blocked_reason, detail)`, which any other menu can adopt without new machinery. The one hardcoded reason string that used to live in the menu is gone.
   - **Which options get listed-and-greyed is still per-menu policy, and only this one changed.** The Weapon Action *self-verbs* (Reload/Rev/Burrow) stay hidden when unavailable, because `can_reload()` conflates "this family cannot reload at all" with "the magazine is already full" — they need that distinction before they could honestly say why. `populate()`'s top-level rows likewise stay omit-when-unavailable; a permanently full main menu is a UX change, not a readout fix.
   - This is also **why the category opens for a single carving** rather than requiring two: with descriptions and greyed entries it is informative even when it offers no alternative choice. Note the category's *row* still gates on something ACTIONABLE (`Unit.has_transmutations`, the same loop `has_weapon_actions` uses) — the catalogue is what's inside it, not what opens it.

## Reading a turn: pacing and history (added 2026-07-29)

From the scratchpad, @Phaazoid's note about AI turns being unreadable. One observation, two issues,
because they solve different halves: **pacing** helps you read a turn *as it happens*, a **log** lets
you read it *afterwards*. Both are #44 children.

- **[#118](https://github.com/Phaazoid/Godoiosis/issues/118) — a beat between actions. BUILT
  2026-08-10.** The filed half was right but was only half the problem: an AI turn read *backwards*.
  `OrderExecutor._execute_action_sequence` advanced the instant an action reported
  `execution_complete` (a lunge is 0.18s, so a three-unit swing phase was ~0.5s) and the AI's plan
  went from queued to resolving with no frame in between — while the one part that already had a
  pace, `CameraController.pan_to`, spent **2.0s per squad** gliding. So the fix both adds time and
  takes it away; the dev's words were *"parts are too fast, but others are too slow."*

  **`Classes/core/Pacing.gd` is the one seam — a tuning table, not a system**, in the shape of
  `UiLayers`: five constants with exactly one reader each (`AI_SQUAD_PAN`, `AI_PLAN_READ`,
  `AI_ACTION`, `PLAYER_ACTION`, `TURN_HANDOFF`), plus `beat(host, seconds)`, which every pause routes
  through. The two pre-existing numbers moved onto it rather than being duplicated — the pan's
  default arg, and `game.start_faction_turn`'s hardcoded `create_timer(1.0)`, whose TODO read
  *"later make small waits between each enemy movement"*, i.e. this ticket.

  Three decisions worth keeping:
  - **The beat lands BEFORE each action, never after.** That spaces a phase off the previous one for
    free — the parallel move phase, then each side-channel batch — so there is no separate
    between-phases pause to keep in sync, and no trailing pause before the squad's turn ends. An
    empty batch returns early, so a phase with nothing in it costs nothing.
  - **AI and player are two values off one read.** `execute_orders` keys on the same
    `is_ai_faction` call its invalid-plan concede already makes (#103), so a hotseat faction with AI
    off is a *human* and paces like one. `PLAYER_ACTION` is **0.0** by dev call (2026-08-10): an AI
    plan is being read for the first time, a player's was authored by the person watching it.
  - **`AI_PLAN_READ` is skipped when the squad only holds position.** Queueing repaints the queue
    panel, arrows, ghosts and target markers synchronously, so the pause buys a real readout — but a
    squad with nothing to do would just add dead air per squad, which is the complaint being fixed.

  **The headless escape in `beat()` is a safety property, not a convenience** (same gate
  `ReportUploader.is_configured` and `BugReporter.capture_frame` use): `execute_orders` is awaited
  directly by nine test call sites, so a literal timer at an await site would put real wall clock on
  every case that resolves a plan. `pan_to` got the same escape and snaps instead of tweening —
  `tests/ai` went **19.0s → 7.5s** on that alone. `play/play_session.gd` is untouched and stays at
  zero unconditionally; it is the synchronous mirror by design.

  **What the suite pins, and what it cannot.** `tests/core/test_pacing.gd` asserts exactly one thing
  — a beat costs a headless run **zero frames** — measured in frames rather than seconds so there is
  no duration threshold to hard-code and **no assertion anywhere about what any of the five numbers
  are** (dev, 2026-08-10: tuning by feel must never turn the suite red). Falsified against its own
  bug: delete the headless check and it waits the full 30s and goes red. It cannot see that the
  beats are *wired in* — they are zero headless by construction — which is the `went_downed` shape
  (#103): the gate for that, and for the five numbers themselves, is watching an AI turn, never a
  green run.
- **[#119](https://github.com/Phaazoid/Godoiosis/issues/119) — a reviewable battle log.** Nothing
  like it exists yet. The principle this doc contributes: **share the widget, never the data
  source.** The queue is a *live derived preview* rebuilt from the plan on every change
  (`ActionQueueDisplayEntry.build_for`), while a log is a *frozen record of what executed*, whose
  inputs are gone by the time it's read. Rendering log rows through `ActionQueueRow` is right and
  cheap; handing the log a squad and a plan and calling `build_for` is Law #4 with the sign flipped —
  one code path answering both "what will happen" and "what did happen".

  What a log must show that **no queue row ever did** *(halved 2026-08-09: the other half was
  post-BREAK reality, and the BREAK repeal — resolution-pipeline R9 — means execution never diverges
  from the preview, so there is no post-divergence state to report)*: every event that isn't a player
  order at all — end-of-phase burn damage, Crisis outcomes, expiring downed clocks, squad ejections,
  terrain deposits. Those are precisely the events players miss, and they are invisible to the queue
  by construction.

## The volume above a unit ([#229](https://github.com/Phaazoid/Godoiosis/issues/229), BUILT 2026-08-15)

4c's move to billboarded selection icons opened real estate the flat board never had, and the dev's
read was that it is *better* than the 2D placement and worth building on. **The first deliberate
occupant is a health readout**, and until it shipped **nothing showed HP on the board in either
view** — the hover card was the only answer, which costs a glance away from the diorama.

The rulings, all dev calls, all made before building:

- **Hover-only, and health alone.** Status icons, Will and turn state stayed out. At most one unit
  is hovered, so the crowding question the umbrella worried about does not arise yet — it returns
  the moment anything here becomes always-on. **#313 below is that moment**, and it answered the
  crowding question by folding the prediction into the SAME bar rather than adding a second one.
  **#350 is the LITERAL case** — every unit, always, because the player asked — and it answered the
  same way, widening #313's crowding knob instead of growing a second one. What that density does to
  bars that OVERLAP is named as still-open in its section below.
- **A bar AND a number**, world-scaled like the icons beside it rather than screen-constant: it
  belongs to the scene, not to the glass. Consequence to accept: it shrinks as you zoom out.
- **Two flat colours, never a ramp.** Fill is what the unit HAS, red backing is what it has lost.
  A bar that also changes hue as it shortens says the same thing twice.
- **It stacks UNDER the selection icons.** Crown/squadmate on top, health tucked beneath. (The
  target reticle was in that list until #346 retired it to the ground channel — see below.)

Three findings that generalise past this ticket:

1. **`shaded = false` is not "unlit".** It skips direct lighting only; volumetric fog, glow, filmic
   tonemap and DoF all still run. Gameplay markup that must not be atmospheric needs
   `disable_fog`/`disable_ambient_light` on an explicit material — which means `Sprite3D` and
   `Label3D` cannot do it, since neither exposes one. **Whole-frame post has no per-object
   exemption at all**; true immunity needs a separate render pass, which nothing has paid for yet.
2. **One display means ONE billboard.** Per-object billboarding rebuilds each element's basis about
   its own origin, so any world-space displacement shears as the camera orbits, and the in-plane
   offsets that survive it are not applied identically by every node type (a `Label3D` moves its
   glyphs and its outline by different amounts, which renders as a doubled, overlapping copy).
   Rotate the parent; lay the children out in ordinary local space.
3. **Anything hung over a unit's head must MEASURE the art, not assume a height.** Map sprites carry
   transparent padding — the same fact [#279](https://github.com/Phaazoid/Godoiosis/issues/279)
   pinned a floating lamp on — and it differs per sprite, so a fixed offset from the feet sits at a
   different apparent height on every unit. `UnitSprite3D.art_top_height()` is the one answer.

**The flat view has no counterpart and that is a real gap, not a design** — filed to
[#292](https://github.com/Phaazoid/Godoiosis/issues/292); #313 below inherits that gap rather than
widening it, and its 3D-only scope is declared there. Successor still open:
[#314](https://github.com/Phaazoid/Godoiosis/issues/314) (Fire Emblem-style tick blocks that
explosively fall away). [#188](https://github.com/Phaazoid/Godoiosis/issues/188) wants damage
numbers in the same volume and should share whatever seam #313 settled.

## The same bar shows the FUTURE ([#313](https://github.com/Phaazoid/Godoiosis/issues/313), BUILT 2026-08-16)

Law #2 says the queue never lies and Law #1 says there is no randomness, so a queued plan does not
*forecast* a unit's HP — it *is* what that HP will be. This draws it: while a plan is queued, every
unit it changes wears a readout with a **notch** at the predicted HP and the span between there and
now filled in. **Presentation only.** It computes no damage; if it ever needs to, that is the bug.

The rulings, all dev calls, all made before building:

- **A notch on ONE bar**, not a ghost twin beside it. Current and predicted are one fact about one
  unit, and a second bar over everybody the plan touches is exactly the crowding #229 deferred.
- **Anyone the plan CHANGES** — which reaches enemies your own attack will hit, allies caught in
  splash, and anyone a derived counter strikes, which is most of the value; and it reaches nobody
  the plan leaves alone, with no second rule to maintain. *(Spelled "predicted HP differs from
  current" until #354 below, which is where that spelling failed.)*
- **The alarm is the NAMED RUNGS ONLY** — predicted DOWNED, KILLED or CRISIS. "Too low" as a
  fraction would have been a new game rule needing a home and a justified number; the ladder
  already names the outcomes worth flinching at.
- **3D only, declared** rather than drifted — the flat view has no health readout of any kind to
  diverge from, which is #229's gap and not a new one.

Three things that generalise past this ticket:

1. **The plan-level number is the HYPO, not an outcome's `target_hp_after`.** That field is per HIT;
   a unit struck twice has two of them and neither is what the pass leaves behind.
   `PlanResolver.projected_hp` / `projected_lifecycle` — kept alive on the plan by #124 for exactly
   this class of question — is the whole-pass answer, and it covers derived counters for free.
2. **The display clamp is a SEAM, and it had one user before this.** The threaded HP goes negative
   on a fatal hit; the queue panel had been clamping that to 1-for-a-down and 0-for-a-kill inline.
   A second spelling over the unit's head is Law #2 broken at the point it is being rendered, so the
   ladder moved to `LethalityRules.displayed_hp` and both surfaces read it. It **mirrors execution**
   (`_go_downed` clings at exactly 1) — which this ticket also read as a free teardown, *"the readout
   puts itself away"*, and #354 below is that claim being wrong.
3. **A pulse must not become a second writer of the thing it pulses.** The existing rule is that a
   live pulse OWNS `sprite.modulate`; a 3D readout has no modulate, its colour is a material. So
   `Pulse` now takes the PROPERTY name (the cadence is the one thing every "look at this" cue must
   agree on) and the bar exposes a colour property the tween drives, leaving its own `_paint` the
   single writer of albedo. The redraw had to become value-diffed for the same reason — an
   unguarded rebuild repainted over the tween sixty times a second.

**"No prediction during an AI turn" is what this ticket claimed, and it is FALSE — measured
2026-08-18 while building #354.** The reasoning was that `resolved_plan_for` guards on squad
identity so an AI squad's resolve never matches the player's active squad; but `active_squad` is set
by `SquadManager.queue_action`, which Law #3 makes the AI's own door, and `execute_orders` resolves
for whatever squad it is running. So both sides name the AI squad and they match: an enemy order
puts a doomed bar over the player unit it is about to hit. Whether that is a leak or a *feature* (it
lands during `Pacing.AI_PLAN_READ`, the beat that exists so a drawn AI plan can be read) is an open
dev call, filed rather than decided.

Successor filed the same day and **BUILT 2026-08-19**: [#350](https://github.com/Phaazoid/Godoiosis/issues/350)
— a player toggle pinning **every** bar on, which was one more disjunct in this same visibility
expression and then almost entirely a question of where a player setting lives. See *Every bar, if
the player says so* below. Note also that the predicted-down alarm is a **pulse**, so it joins
[#217](https://github.com/Phaazoid/Godoiosis/issues/217)'s photosensitivity registry — a registry
whose first member (fire) shipped, and which since #350 has a home (`PlayerSettings`) and a page.

## The readout belongs to the PLAN, not to the board ([#354](https://github.com/Phaazoid/Godoiosis/issues/354), FIXED 2026-08-18)

#313's readout was gated on *predicted HP differs from current*, and that one comparison was
answering three questions at once. Two of its answers were wrong, and the dev found the loud one in
play: **bars winked out one at a time, each at the exact moment of impact.** Nothing re-resolves
during a pass, so the prediction stays frozen while live HP drains to meet it — and the instant a
unit's hit lands the two numbers agree and *its* bar switches off, at the single moment the bar is
most worth looking at. The quiet one was the same collision standing still: a unit at exactly 1 HP
that the plan fells has a predicted HP of 1 (the display clamp mirrors `_go_downed`'s cling), so it
never wore a bar at all and never raised the felling alarm.

**Dev call: through the end of the resolution PASS**, not the mission — every bar that was up when
Execute was pressed stays up until the whole exchange finishes, then they drop together. The
mission-long reading would have been [#350](https://github.com/Phaazoid/Godoiosis/issues/350)
arriving as a default rather than a toggle, inheriting its unanswered crowding problem.

- **Membership is a question about the PLAN, so it is asked of the plan.** `PlanResolver.plan_changes`
  compares the hypo's end state to the hypo's *own* baseline — `_Hypo.start_hp` was already threaded,
  and `start_lifecycle`/`start_in_crisis` join it — so the answer is settled when the plan is and
  cannot go false as execution applies the very damage it predicted. No latch, no new owner, no
  "the pass is over" event to fire.
- **Only the FILL tracks the board.** A bar now drains down to its notch as the hit lands, instead of
  vanishing at impact. Membership, notch, span and alarm are all the plan's.
- **Nothing new dismisses them**, because `OrderExecutor._end_squad_turn` already did: it is the one
  terminal state of a pass and it always empties the queue, which nulls `active_squad` and takes the
  previewed plan with it. That covers the AI concede (same call) and a mission ending mid-pass
  (`MissionController.check()` is not awaited, so the end-of-turn still runs in the same frame).

Two things that generalise past this ticket:

1. **A display CLAMP can never also be a membership test.** `displayed_hp` exists to flatten a
   sentenced unit's number onto what execution will really leave it at — which is exactly the
   information a "did anything change?" question needs, destroyed. Ask the raw threaded value.
2. **The previewed plan and the last resolve are different questions while a pass is running.** A
   kill mid-pass fires `unit_died` → `game._on_unit_died` → `refresh_action_queue` → `resolve_plan`,
   re-resolving a queue whose earlier attacks have already landed. `OrderExecutor.executing_plan` is
   the plan being played out, and `battle3d._previewed_plan` prefers it. **That re-resolve is also a
   live Law #2 break in EXECUTION** — it overwrites `AttackAction.resolved` on attacks that have not
   run yet, and `execute` is pure playback of that field — filed separately; this change only makes
   the readout immune to it.

## Every bar, if the player says so ([#350](https://github.com/Phaazoid/Godoiosis/issues/350), BUILT 2026-08-19)

The third and final reason a readout is up, and the only one that is a **preference** rather than a
derivation: the player asked for all of them. #229 was hover, #313 was the plan; this is *show me
the board at a glance*, and the dev asked for it at #313's merge.

The model half is one more disjunct in the same expression — `hovered or foretold or always_on` —
with no new per-unit state and nothing computed. **What made it a ticket is that the toggle had
nowhere to live**, which is the part worth keeping.

The rulings, all dev calls, all made before building:

- **It gets a SETTINGS SCREEN, not a keybind and not a checkbox bolted to the pause card.**
  `presentation-effects.md` had already ruled that a settings surface, once it exists, *drives*
  #217's photosensitivity switch rather than a second one growing beside it — so the choice was
  build the surface or build the second switch. `SettingsScreen` is `GlossaryScreen`'s shape exactly
  (a `ModalCard`, reachable from the pause menu **and** the title screen, because a preference set
  before the first mission is one nobody has to pause to find).
- **The page is a PROJECTION of `PlayerSettings.DEFS`**, so it never learns a setting's name. That
  is the whole point of paying for a table with one row in it: #217 is a store edit, not UI work.
  A test pins "every declared setting gets a row" so the property cannot quietly lapse.
- **Persisted, not session-scoped.** `user://settings.cfg` via `ConfigFile`, keyed by the enum
  member's NAME — `Experiments`'s shape, minus its cull-the-flags doctrine, because a setting is a
  promise to the player rather than an experiment. A static class, not an autoload; this project
  has none, and `Stats` / `Elemental` / `Experiments` are all class-level statics.
- **Two states, and the toggle governs the HOVER reason only.** A bar that is up because a queued
  plan is about to change that unit stays up either way. Law #2 says the queue never lies, and #354
  had just finished ruling that a prediction survives to the end of its pass; a preference that can
  hide what the queue is promising would undo both. "Off" is #229's behaviour, not "no readouts".
- **Bars only; the digits stay a hover reward.** Reused rather than re-decided — `ghost_shows_number`
  had already answered this one level down for prediction bars, so the knob simply **widened**
  (renamed `unhovered_shows_number`, since the question is *how crowded may this volume get* and
  that does not change with why a bar happens to be up). One knob, not one per reason.

Two things that generalise past this ticket:

1. **A global static read is a hermeticity hazard in the SUITE, not just in the game.**
   `PlayerSettings.is_on` falls through to `user://settings.cfg`, so any suite asserting *which*
   units wear a bar would silently read the developer's own saved preference and red on a machine
   where the toggle is on. Both bar suites now call `reset_for_test()` in `before_test`. Any future
   store with a disk fallback owes the same seam on the same day it is written.
2. **The gate is ONE named expression, deliberately.** [#357](https://github.com/Phaazoid/Godoiosis/issues/357)'s
   state-icon row rides it rather than growing its own, so a second visibility rule in `UnitMirror`
   is the bug — the ticket said so before it was built, and what shipped is stronger than the
   ticket asked: the icons hang off the bar, so there is no second rule to keep in step.

**Still open, and named rather than fixed: `render_priority` is a GLOBAL sort key in the alpha
queue, not a per-bar one.** Each `UnitHealthBar` claims `UNIT_HUD_RENDER_PRIORITY + 0..+6` for its
five coplanar quads and its label, so two bars that overlap on screen interleave **by layer rather
than by distance** — a far bar's notch and digits draw over a near bar's outline. #245 already
proved priority beats depth here (a flame at priority 0 sat under a `Layer.TERRAIN` overlay at 2 and
read as erased). It could not show while at most one bar was up; at always-on it can, and a bar is
`bar_width_texels` 26 ÷ 16 px-per-cell = **1.63 cells wide**, so two units on *adjacent* cells
overlap before any camera pitch is considered. The fix, when the dev's eye says it is needed, is to
collapse the quads into one mesh at one priority (vertex colours) so bars sort by depth against each
other. Deliberately not built: this ticket is the toggle, and whether the crowding actually reads
badly is a question only play answers.

**3D only, inherited** — the flat view still has no health readout of any kind to toggle, which is
#229's gap under [#292](https://github.com/Phaazoid/Godoiosis/issues/292) and not a new one.

## Two marker channels, one rule ([#346](https://github.com/Phaazoid/Godoiosis/issues/346))

The volume above finally has a rule about what may occupy it, and it came from measuring rather
than arguing. [#316](https://github.com/Phaazoid/Godoiosis/issues/316) made the target-pick GROUND
marker visible for the first time (it had pointed at an atlas coord the sheet never had), and Squad
Up then marked every candidate twice — a tile under the recruit and an `IconType.TARGET` billboard
over its head. Seeing both at once, the dev's call was that **the ground one reads better**.

- **Ground / tile = what this INTERACTION is about.** Transient, mode-scoped, cursor-driven:
  pickable candidates, reach, selection, the cells a thing would affect.
- **Above the head = what this UNIT IS.** Persistent, mode-independent: element states, downed /
  maimed, Crisis, and the hover health readout #229 already put there.

**Retired by this rule:** `IconType.TARGET`, whose only producer was `draw_create_squad` — the
target-pick ground marker is now the single answer to *which unit may I pick*. `CURSOR` and
`INVALID` went with it as never-produced leftovers. **`CROWN` and `SQUADMEMBER` were answered by
[#325](https://github.com/Phaazoid/Godoiosis/issues/325), and the dev's verdict after playing both
styles (2026-08-19) was a MIX rather than a winner:** membership is a per-squad coloured RING under
each member; leadership is the **original crown over the head**, unchanged from before the ticket,
including its timing — hover *any* squad member and that squad's leader wears it. The legacy green
squares lost outright and are **deleted**: no toggle, no second style, `SQUAD_MARKER_RINGS` gone.

The leader wears **both** — a ring because they are a member, the crown because they lead — and
that is the two-channel rule of this section working rather than an exception to it: the ring says
what this INTERACTION is about, the crown says what this UNIT is.

**The interim design — the crown as a badge on the health bar — is deleted, and why it lost is
worth keeping.** It read fine in isolation; what killed it is that it made leadership conditional
on a *different* marker's visibility. [#350](https://github.com/Phaazoid/Godoiosis/issues/350)
landed a day later and made the health bar a player preference that is **off by default**, so a
squad leader silently had no persistent 3D marker at all. Neither ticket was wrong on its own and
neither could see it; it appeared only in composition. **The rule that falls out: a marker answering
"what is this unit" must not ride another marker's visibility gate** — which is also the standing
caution for [#357](https://github.com/Phaazoid/Godoiosis/issues/357), whose state-icon row is
specified to ride exactly that gate. Riding it is a choice about defaults, not a free consolidation.

**Two things are now single-sourced by the deletion**, both Law #4 in miniature: `ICON_TEXTURES` is
the one answer to what a marker type LOOKS like (applied once at `setup`, so `_style_icon` only ever
decides tint and z — it used to assign textures too, a second place a marker's art came from), and
`OverlayMirror._icons` routes by TYPE rather than by mode (CROWN to the head channel, everything
else to the ground). The per-type y-stagger went with the squares: CROWN is the head channel's only
tenant, so there is nothing left to stagger against.

**The premise this ticket was filed on was wrong, and the correction generalises.** #325's body
said `Layer.SQUAD` "already draws the squad's footprint" — measured false while planning: that
layer is the Squad Up / Join Squad *candidate bubble*, `SQUAD_RANGE` is the cohesion leash, and
the head-icon channel (`OverlayManager.icons_by_unit`) was the **only** membership marker in the
game. So the build RELOCATED that one channel rather than restyling a fill, and the icon
lifecycle never moved. Third instance of [#228](https://github.com/Phaazoid/Godoiosis/issues/228)'s
law — *an issue's own premises are stale-able; re-derive from the code before building.*
**The 2D/3D asymmetry the badge introduced is gone with it** — both views now draw the same head
crown, so there is nothing here for [#292](https://github.com/Phaazoid/Godoiosis/issues/292) to
carry.

**The ring became a STANDING marker behind a player setting (#423 slice 1, dev call 2026-08-21).**
Planning [#423](https://github.com/Phaazoid/Godoiosis/issues/423)'s form/dissolve/shatter animation
found that the thing it proposed to animate does not persist: `SQUADMEMBER` icons are produced only
by selection and hover paths and destroyed by `clear_selection_icons`, exactly as the sentence above
says — *the icon lifecycle never moved*. #325 relocated the ring from head to ground and left it a
**selection** marker wearing a membership meaning.

**That killed the half #423 called most valuable, and the reason generalises.** The ticket's best
argument was that the two *un-previewed* ejections are where feedback earns most. But
`OrderExecutor.execute_orders` clears the icon channel BEFORE the pass and both ejection sweeps run
after it, and the turn-start sweep fires when nothing is selected — so **at both settle points there
was no ring on screen to shatter.** A marker's visibility schedule is part of what it can express:
an interaction-scoped marker cannot carry an event that happens when no interaction is open, however
right the marker looks the rest of the time. Fifth instance of
[#228](https://github.com/Phaazoid/Godoiosis/issues/228)'s law.

So the animation waits, and what shipped first is the lifecycle it needs:
`PlayerSettings.ALWAYS_SHOW_SQUAD_RINGS`, **off by default**, which keeps every multi-member squad's
rings up instead of only the squad being looked at. It is a toggle rather than a switchover on
purpose — the same play-both-then-decide shape #325 itself used, and the loser gets deleted.
`game.refresh_squad_rings` is the one sweep; it REBUILDS the channel rather than adding to it,
because `create_unit_icon` only ever adds and a squad shrinking back to one member has to lose its
rings. It is gated on having squadmates (`Unit.has_squad`'s question) and deliberately **not** on
`ring_hue`, which is dealt once at the first squadmate and never reset — that gate would leave a
lone leftover wearing a colour forever.

**Two findings worth keeping.** First, **persistence is what made a stale copy visible**:
`OverlayIcon` stored the cell it was built on and `OverlayMirror` anchored on that copy, which was
invisible only because markers were rebuilt constantly — the instant one outlived a move it sat on
the cell its unit had walked off, in both views. The marker now asks its UNIT where it is
(`OverlayIcon.current_cell`), one answer read by the 2D position and the mirror alike, which is
[#308](https://github.com/Phaazoid/Godoiosis/issues/308)'s law arriving on a second shelf. Second,
**standing rings deliberately stand down for a whole resolution pass**: a marker sits on its unit's
*projected destination*, which mid-pass is a cell the unit has not reached, so a ring left up would
jump ahead of the unit rather than travel with it. Riding the animated position is a separate build.
The restore is the LAST line of `_end_squad_turn`, because that method opens by clearing the channel.

Both views move together, so there is nothing here for
[#292](https://github.com/Phaazoid/Godoiosis/issues/292) to carry.

Two things the retirement exposed, both worth keeping in mind. **The head icon was never the
general answer**: TARGET was created in exactly one flow, so rescue, intimidate and join-squad had
their candidates marked *nowhere in either view* until #316, and Squad Up only looked right because
someone had patched that one screen. And **the freed channel's first occupant was filed in two
halves (dev direction, 2026-08-18), of which the first is now BUILT:**
[#357](https://github.com/Phaazoid/Godoiosis/issues/357) puts a `StateIcons` row just above each
unit's health bar, and [#358](https://github.com/Phaazoid/Godoiosis/issues/358) — still open —
makes the sprite itself wear its status (wet drip, frost sheen, Crisis), the channel that keeps
states readable when [#350](https://github.com/Phaazoid/Godoiosis/issues/350)'s toggle hides the
bars. Always-on state icons remain the trigger #229 named for the crowding question it deferred —
two states cannot crowd, a longer vocabulary can.

**#357's structural point is that the row has NO visibility rule of its own.** The icons are
CHILDREN of `UnitHealthBar`, so a hidden bar hides them by construction — there is no second
expression to keep in step with the gate, which is what the ticket asked for one level more weakly
(*"specified to ride it"*). Everything else follows the shape the bar's own parts already use — and
that shape outlived the crown badge #325 briefly put beside them (deleted 2026-08-19, above): quads
in the group's local space, so `face()` turns the whole display and nothing gets a billboard basis
of its own; sizes in texels; a POOL that parks extras rather than freeing them, since the count
changes every time a state lands or expires. Three Look knobs (icon size, row clearance, spacing),
preset-excluded like the rest of the Unit HUD group — a mission may not hide what a unit IS.

**CHILLED's art is the FROZEN terrain tile, as a declared placeholder (dev call, 2026-08-19).**
`StateIcons.ICONS` carried WET alone, and the alternative — falling back to a text label in world
space — reads as mush at icon size. The stand-in lands in the shared table rather than at one
surface, so the hover card, the inspect bar and the row all show it, and a real 16px CHILLED icon
is a one-line swap. Two consequences were paid at the same time, both of them Law #4 arriving on
schedule: `ActionQueueRow` had kept its **own** one-entry copy of the art table, which would have
started disagreeing the moment CHILLED existed (it now reads `StateIcons.ICONS`); and the two
source images disagree in size (32px wet, 16px ice), so `populate` now renders every icon at
`ICON_SIZE` — the recipe `HoverInfoPanelControl` already uses to draw these same terrain icons.

The doctrine governing everything that enters these channels (dev, 2026-08-18): *"Having access to
fancy effects doesn't necessitate using them. Using them in the correct places rather than
everywhere makes them have more effect."* Unit status (#358) is a sanctioned place; a fancy effect
everywhere is a fancy effect nowhere.

## Captured from the scratchpad (swept 2026-08-20) — all *captured, not locked*

Six inbox ideas that this doc owns. Each is recorded with what already answers part of it, because in
every case something does.

**A third health-bar state: *damaged only*.** Show every unit's bar except full-health ones (the
hovered unit keeps its bar and its digits either way). Structurally this is a **third value for a
choice that already exists** — `PlayerSettings.ALWAYS_SHOW_HEALTH` (#350 above) is today hovered-only
vs always-on, and the gate is deliberately **one named expression** (`hovered or foretold or
always_on`), so this is a third disjunct there and **not** a second visibility rule. The real cost is
UI, not model: `SettingsScreen` is a pure projection of `PlayerSettings.DEFS` and `DEFS` describes
**booleans** — a three-way setting is the first non-checkbox row the table has ever had, so it either
grows a widget kind or the question is re-cut as two independent bools. Worth noting *why* it was
asked for: #350's own open note flags that always-on bars can **crowd** (`render_priority` sorts
globally, and a bar is 1.63 cells wide, so adjacent units overlap) — "damaged only" is a *crowding*
answer as much as a preference, which is an argument for it and also a hint that the crowding fix
may be the better ticket. **The `foretold` disjunct must survive any cut** — Law #2 says a bar the
queue is promising to change cannot be hidden by a preference.

**Unit sprites should LOOK hurt.** Art reflecting health, so a nearly-dead unit reads as nearly dead
without a bar at all. This is **the same thread as the Crisis-sprite item below** — sprite-as-status,
art-gated, and the third consumer of [#358](https://github.com/Phaazoid/Godoiosis/issues/358)'s
effect stack. Treat them as one design: whatever answers "how does a sprite show a state" answers
both, and answering them separately is how two effect stacks get built. Two constraints already on
the books: the #346 channel rule says what a unit **is** belongs *on/above the unit* (this qualifies),
and the restraint doctrine — *fancy effects in the correct places rather than everywhere* — bites
hard here, since "every damaged unit" is close to "everywhere". Must reach both views or be declared
on [#292](https://github.com/Phaazoid/Godoiosis/issues/292).

**Squad join / leave feedback on the ring channel.** Animate the per-squad ring under a unit's feet
**forming** on join and **dissolving** on leave; a forceful removal **shatters** it. The genuinely
useful half is *which events to hook*, and it is wider than the menu: **cohesion ejection**
(`SquadManager.enforce_contact`) and **downed ejection** both drop membership at settle points and
are noted in the codebase as **un-previewed** — a squad silently losing a member is exactly the
moment feedback earns most, and it is not a click the player made.

**Two of this capture's premises were measured FALSE while planning it (2026-08-21) — see the #423
slice 1 section above.** The ring was a *selection* marker, so at both settle points there was no
ring on screen to shatter; and the dependency on #358 was wrong, since `OverlayIcon` is its own
overlay node while #358's stack rides the unit's `MapSprite`. The persistence this needs shipped
first as `ALWAYS_SHOW_SQUAD_RINGS`. What remains open is the animation itself, and one design
question the restraint doctrine sharpens: squads re-form often, and three of these firing at once
during a settle is worth designing for rather than discovering.

**Warn when a move ends on — or crosses — an element-afflicted tile.** *(Merged capture: the
action-menu warning recorded 2026-08-18 and the queue-row warning recorded 2026-08-19 are the same
fact asked at two surfaces.)* Before committing a move onto a tile carrying fire (or any later
hazard), say so. Three surfaces want it and they are one question: **prefer** in pathing (the AI and
Group Move half — [terrain.md](terrain.md) owns the rule, and the AI's share files to
[#117](https://github.com/Phaazoid/Godoiosis/issues/117)), **warn** on the action-menu entry, and
**warn** on the queued row. Open: what the notice IS (menu text, an icon, a confirm), and whether it
covers only the **destination** or **any afflicted tile the path crosses** — the second is strictly
more honest and strictly more visual noise. Precedent for the row half: `ActionQueueRow` already
renders element icons off the shared `StateIcons.ICONS` table, so the queue surface has the art.

**A queued move should still offer "Move" — re-entering move planning.** Today the row is *hidden*
once a move is queued (`MainActionMenu.populate` refuses on `has_action_type_queued(MOVE)`), so
re-planning means cancelling the unit's actions and starting over. Re-entry is plausibly "drop the
old move, enter move mode", and the hard part is already solved: by the 2026-08-02 fork a re-planned
move is **never refused for breaking a queued aim** — the aim falls to invalid-in-red instead — so
the invalidation machinery a re-plan needs exists and is exercised. The open half is the gate's
*other* clause: a unit with a **main action** queued also loses Move, and move-before-main is a real
ordering rule (`MoveAction.actor_can_perform`), so re-entry must either preserve it or state why not.
**A menu that greys rather than hides would explain itself** — since #166 a row can only be greyed if
it can say why, which is the shape this wants.

**Streamline move → main action.** After a move commits, open the unit's main-action menu
automatically; or a double-click shortcut. Pure flow-feel, no model question. Open: which gesture,
and whether auto-open irritates on the turns a player only wanted to move. **One caution from this
codebase specifically** — `game.clear_selection()` runs on every menu *pick*, not just cancel
(`ActionMenuController` emits `cancelled` before `action_selected`), and that ordering has already
produced two bugs; anything that chains one menu into the next lands directly on it.

**Player-chosen aim / attack reticule colours.** The dev's half-joking aside at #212 (*"a color
slider to set whatever color they want"*), kept because it is closer than it sounds: the reach fill
is a tunable `OverlayManager.ATTACK_MODULATE` **static** rather than a `const`, the 3D mirrors that
modulate rather than holding its own colour, and since #350 the game **has** a settings surface that
did not exist when this was said. So the pieces are: a store row, a projection row, and a widget
kind that `DEFS` does not have yet (a colour, like the three-way above — the same gap, twice).
Real colour-blindness support would want the whole `BoardOverlays.LAYERS` / `OverlayManager`
modulate set rather than the reticule alone, which makes this a sibling of
[#217](https://github.com/Phaazoid/Godoiosis/issues/217)'s photosensitivity toggle — the other
accessibility knob whose home is that same page. **Note the tuning-surface collision before
building:** those same layer colours are `GameKnobs.CLASS_KNOBS` rows (#373), i.e. dev-tunable
game constants written back into their declarations — a player override is a *second* writer of the
same value and needs a declared relationship with the authored default, not a second seam.

## #44 board-side items (cross-referenced, not in this doc's running order)

Flash-not-glow unit highlights; counter-hover -> show countering enemy's attack range;
enemy attack-range on hover during player turn; real Will bars on panels (HP over a unit's head
landed as #229 above; the PANEL half and Will are both still open); squad-target
cursor color-coding; muted squad icons when another squad is active; simultaneous-movement
legibility (needs design first — the umbrella's core problem).

**A unit IN CRISIS must read as unmistakable at board glance (dev, 2026-08-09 — filed with
[#158](https://github.com/Phaazoid/Godoiosis/issues/158)'s ability re-homing):** the skull in the
hover states-row is the only marker today, and a battle-long no-safety-net state deserves more —
**the map sprite itself should reflect Crisis** (art-gated; needs a sprite/tint/overlay treatment
per unit or a generic one). "It should be very obvious a unit is in crisis mode." Scoped as the
third consumer of [#358](https://github.com/Phaazoid/Godoiosis/issues/358)'s effect stack.

*Authored by Claude (Opus 4.8) at @Phaazoid's direction, 2026-06-26.*
