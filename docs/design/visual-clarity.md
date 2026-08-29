# Visual Clarity — working guidelines

Home for the board-legibility & action-queue readability pass. Umbrella issues:
[#44 Visual Clarity Overhaul](https://github.com/Phaazoid/Godoiosis/issues/44) (board side) and
its child [#49 Action Queue UX](https://github.com/Phaazoid/Godoiosis/issues/49) (the queue widget).

This is a *guidelines* doc, not a spec — it captures the principles we're holding the work to,
plus the running order of the queue-UX checklist. Update it as items land.

**Canon checked through #656 (2026-08-29).**

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
  `UiLayers`: five constants at the time, each with exactly one reader (`AI_SQUAD_PAN`, `AI_PLAN_READ`,
  `AI_ACTION`, `PLAYER_ACTION`, `TURN_HANDOFF`), plus `beat(host, seconds)`, which every pause routes
  through. The two pre-existing numbers moved onto it rather than being duplicated — the pan's
  default arg, and `game.start_faction_turn`'s hardcoded `create_timer(1.0)`, whose TODO read
  *"later make small waits between each enemy movement"*, i.e. this ticket.

  Three decisions worth keeping:
  - **The beat lands BEFORE each action, never after.** That spaces a phase off the previous one for
    free — the parallel move phase, then each side-channel batch — so there is no separate
    between-phases pause to keep in sync, and no trailing pause before the squad's turn ends. An
    empty batch returns early, so a phase with nothing in it costs nothing.
    *(**"Never after" was REPEALED 2026-08-27** — see *The camera STAYS* below. It was written when
    a beat had nothing worth watching on its way out; health-cube debris is what made a trailing
    pause a feature rather than dead air. The rest of this bullet stands: the hold still lands
    before, and it is still what spaces the phases.)*
  - **AI and player are two values off one read.** `execute_orders` keys on the same
    `is_ai_faction` call its invalid-plan concede already makes (#103), so a hotseat faction with AI
    off is a *human* and paces like one. `PLAYER_ACTION` is **0.0** by dev call (2026-08-10): an AI
    plan is being read for the first time, a player's was authored by the person watching it.
  - **`AI_PLAN_READ` is skipped when the squad only holds position.** Queueing repaints the queue
    panel, arrows, ghosts and target markers synchronously, so the pause buys a real readout — but a
    squad with nothing to do would just add dead air per squad, which is the complaint being fixed.

  **The headless escape in `beat()` is a safety property, not a convenience** (same gate
  `ReportUploader.is_configured` and `BugReporter.capture_frame` use): `execute_orders` is awaited
  directly by 34 test call sites across 12 suites (nine at #118; measured again 2026-08-27), so a literal timer at an await site would put real wall clock on
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
- **Two flat colours, never a ramp.** Fill is what the unit HAS, red is what it has lost. A bar that
  also changes hue as it shortens says the same thing twice. *(The rule survived #314 whole; only its
  spelling moved — red was a BACKING showing through the bar, and is a shrunken red cube now.)*
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
widening it, and its 3D-only scope is declared there. **Successor BUILT:
[#314](https://github.com/Phaazoid/Godoiosis/issues/314) replaced the bar with a grid of cubes — see
its own section below; everything above about placement, the one-billboard rule, the unlit materials
and measuring the art still holds, and only the GAUGE itself changed.**
[#188](https://github.com/Phaazoid/Godoiosis/issues/188) wants damage numbers in the same volume;
#314 measured that it does NOT need the shared damage event #229's ticket assumed — the mirror diffs
HP it already reads — so #188 is free to build sprite-level feedback on its own terms.

## The same bar shows the FUTURE ([#313](https://github.com/Phaazoid/Godoiosis/issues/313), BUILT 2026-08-16)

Law #2 says the queue never lies and Law #1 says there is no randomness, so a queued plan does not
*forecast* a unit's HP — it *is* what that HP will be. This draws it: while a plan is queued, every
unit it changes wears a readout with a **notch** at the predicted HP and the span between there and
now filled in. **Presentation only.** It computes no damage; if it ever needs to, that is the bug.

*(The NOTCH was deleted by #314 below. Everything else in this section — who wears one, what the
alarm means, the hypo-not-`target_hp_after` rule — is unchanged; with one cube per point of HP,
colouring the exact cubes the plan takes says where it lands more precisely than a mark beside them,
so the notch became a second statement of one fact.)*

The rulings, all dev calls, all made before building:

- **A notch on ONE bar**, not a ghost twin beside it. Current and predicted are one fact about one
  unit, and a second bar over everybody the plan touches is exactly the crowding #229 deferred.
  *(The one-readout half is what survived #314; the notch itself did not.)*
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
  vanishing at impact. Membership, notch, span and alarm are all the plan's. *(Since #314 the fill is
  a count of standing cubes and the notch is gone; the split it names is unchanged — what the unit
  HAS tracks the board, everything the prediction says belongs to the plan.)*
- **Nothing new dismisses them**, because `OrderExecutor._end_squad_turn` already did: it is the one
  terminal state of a pass and it always empties the queue, which nulls `active_squad` and takes the
  previewed plan with it. That covers the AI concede (same call) and a mission ending mid-pass
  (`MissionController.check()` is not awaited, so the end-of-turn still runs in the same frame).

Two things that generalise past this ticket:

1. **A display CLAMP can never also be a membership test.** `displayed_hp` exists to flatten a
   sentenced unit's number onto what execution will really leave it at — which is exactly the
   information a "did anything change?" question needs, destroyed. Ask the raw threaded value.
2. **The previewed plan and the last resolve are different questions while a pass is running.** A
   kill mid-pass fired `unit_died` → `game._on_unit_died` → `refresh_action_queue` → `resolve_plan`,
   re-resolving a queue whose earlier attacks had already landed. `OrderExecutor.executing_plan` is
   the plan being played out, and `battle3d._previewed_plan` prefers it. *(This paragraph used to end
   by calling that re-resolve a live Law #2 break in EXECUTION as well. It was not — see the next
   section, which closed the re-resolve at its source. The preference stays as belt-and-braces.)*

## A running pass owns its plan ([#361](https://github.com/Phaazoid/Godoiosis/issues/361), FIXED 2026-08-21)

`game.refresh_action_queue` now refuses to re-derive while `order_executor.executing_plan` is
non-null. The gate sits at that shared entry point rather than at the death handler because
**thirteen callers ask that one function the same question**, and `_on_unit_died` is merely today's
loudest; one gate covers the rows, `_preview_plan_effects`' shove and deposit overlays,
`validate_squad_plan`'s `is_valid` writes, `SquadManager._last_resolved_plan`, and
`GuardAction.resolved_spent`. A null squad still clears the panel — *"there is no squad to show"* is
a different question, and a mission ending mid-pass must empty it.

Three things generalise:

1. **The ticket's own diagnosis was wrong, and re-deriving it from the code is what found the real
   shape.** #361 was filed claiming the re-resolve overwrote `AttackAction.resolved` on attacks that
   had not run yet. It never could: `resolve_plan` builds fresh `AttackAction`s every call (victims
   are derived, never stored — the #15 rule) and `execute_orders` iterates a plan it captured in a
   local, so the phantom and the pass share no objects. Damage always landed as previewed. Read the
   code, not the issue text — including the issue's own account of the cause.
2. **It was the READOUT, which inverts #354's parting line.** That ticket said the presentation seam
   could not fix a value execution was reading; in fact execution read nothing, and presentation was
   exactly where this lived. #354 fixed only the health-bar half; the queue rows and the board
   overlays were still being rebuilt from the phantom, mid-pass, in front of the player.
3. **"Cosmetic by accident" is not a settled boundary.** Nothing read the re-resolve's output during
   a pass *yet* — but `GuardAction.resolved_spent` is a stored, still-pending order the resolver
   rewrites, i.e. the door already standing open. The next reader of `_last_resolved_plan` or of a
   stored order during a pass would have inherited a real damage bug for free.

The regression law (`tests/law/test_no_reresolve_mid_pass.gd`) runs a real pass with the kill in the
**middle** of the queue — a kill in slot one leaves no already-landed damage to double-count, so the
phantom comes out numerically identical and the case is blind to its own bug. Falsified two ways:
deleting the gate reds the row assertion with the double-count printed, and *moving the gate below
the resolve* — paint suppressed, re-derivation still running — leaves the rows correct and is caught
only by the stored-plan assertion. The second mutant is the one worth copying: **a gate that
suppresses an EFFECT is not a gate that suppresses the CAUSE, and only a mutant that moves the gate
can tell the two apart.**

## Every bar, if the player says so ([#350](https://github.com/Phaazoid/Godoiosis/issues/350), BUILT 2026-08-19)

The third reason a readout is up, and the only one that is a **preference** rather than a
derivation: the player asked for all of them. #229 was hover, #313 was the plan; this is *show me
the board at a glance*, and the dev asked for it at #313's merge.

The model half is one more disjunct in the same expression — today `hovered or foretold or marked or
preferred` — with no new per-unit state and nothing computed. **What made it a ticket is that the
toggle had nowhere to live**, which is the part worth keeping. (`preferred` was the bare `always_on`
bool until #418 made the preference three-valued; the expression's shape is unchanged.)

`marked` is the fourth, added by [#534](https://github.com/Phaazoid/Godoiosis/issues/534): the
end-of-turn effect pass raises a readout over everyone it is about to burn. It is the *same* reason
as `foretold` — something is about to happen to this unit — reached from the other direction, since
that phase has no `ResolvedPlan` to be read out of and must not fake one. It matters because it is
the phase's whole point: `_settle_health_change` skips a hidden bar, so with the preference off the
pass panned to a unit, damaged it, and showed **nothing at all** — not even the cubes.

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
- **The preference governs the HOVER reason only.** A bar that is up because a queued
  plan is about to change that unit stays up either way. Law #2 says the queue never lies, and #354
  had just finished ruling that a prediction survives to the end of its pass; a preference that can
  hide what the queue is promising would undo both. The quietest setting is #229's behaviour, not
  "no readouts". (Two states at #350; three since #418 below, which did not touch this clause.)
- **Bars only; the digits stay a hover reward.** Reused rather than re-decided — `ghost_shows_number`
  had already answered this one level down for prediction bars, so the knob simply **widened**
  (renamed `unhovered_shows_number`, since the question is *how crowded may this volume get* and
  that does not change with why a bar happens to be up). One knob, not one per reason.

Two things that generalise past this ticket:

1. **A global static read is a hermeticity hazard in the SUITE, not just in the game.**
   `PlayerSettings.is_on` fell through to `user://settings.cfg`, so any suite asserting *which*
   units wear a bar silently read the developer's own saved preference and redded on a machine
   where the toggle was on. The per-suite answer — `reset_for_test()` in `before_test`, which both
   bar suites took — was never *enforceable*, and the bill arrived at
   [#449](https://github.com/Phaazoid/Godoiosis/issues/449): **22 suites instantiate the real board
   and none of them called it.** The rule is structural now — **a headless process honours nobody's
   preferences**, so the store is born with persistence off and the suite reads DEFAULTS, the same
   spelling of *nobody is watching* that `Pacing.beat` uses. Any future store with a disk fallback
   owes the same seam on the same day it is written; `reset_for_test()` keeps its other job, wiping
   a value a suite SET, because `_state` is a static that outlives a case.
2. **The gate is ONE named expression, deliberately.** [#357](https://github.com/Phaazoid/Godoiosis/issues/357)'s
   state-icon row rides it rather than growing its own, so a second visibility rule in `UnitMirror`
   is the bug — the ticket said so before it was built, and what shipped is stronger than the
   ticket asked: the icons hang off the bar, so there is no second rule to keep in step.

**Still open, and named rather than fixed: `render_priority` is a GLOBAL sort key in the alpha
queue, not a per-bar one.** Each `UnitHealthBar` claims `UNIT_HUD_RENDER_PRIORITY + 0..+6` for its
five coplanar quads and its two labels (the HP digits and, since #322, the rescue clock — both at
+6, since neither can overlap the other), so two bars that overlap on screen interleave **by layer rather
than by distance** — a far bar's notch and digits draw over a near bar's outline. #245 already
proved priority beats depth here (a flame at priority 0 sat under a `Layer.TERRAIN` overlay at 2 and
read as erased). It could not show while at most one bar was up; at always-on it can, and a bar is
`bar_width_texels` 26 ÷ 16 px-per-cell = **1.63 cells wide**, so two units on *adjacent* cells
overlap before any camera pitch is considered. The fix, when the dev's eye says it is needed, is to
collapse the quads into one mesh at one priority (vertex colours) so bars sort by depth against each
other. **#314 did most of that for a different reason and the note is now PART-STALE: the gauge is a
grid of opaque cubes, which write depth and therefore sort against each other by distance the way
solid objects should — the coplanar-quad ladder they used to need is gone. What still rides
`render_priority` is the two labels in front, so a far readout's DIGITS can still draw over a near
one's cubes; the cubes themselves cannot. (Round 4 deleted the backing quad, which was the last
thing on that ladder besides the text.) The width figure above is also
superseded — the grid is 41 texels ÷ 32 px-per-cell = 1.28 cells at 20 max HP, and it scales with the
unit's max HP rather than being fixed.** Deliberately not built: that ticket was the toggle, and
whether the crowding actually reads
badly is a question only play answers.

**3D only, inherited** — the flat view still has no health readout of any kind to toggle, which is
#229's gap under [#292](https://github.com/Phaazoid/Godoiosis/issues/292) and not a new one.

### ...and a third value: DAMAGED ONLY ([#418](https://github.com/Phaazoid/Godoiosis/issues/418), BUILT 2026-08-28)

The player picks between three now — **under the cursor** (#229, still the shipped default),
**damaged units**, **every unit** (#350). Nothing about what a player who never opens settings sees
has changed.

The model half is what the section above promised it would be: **one more value of the same
preference, not a second visibility rule.** `_sync_bar`'s gate is still `hovered or foretold or
marked or preferred` — four disjuncts, one named expression — and only the last one moved, from a
bool to a three-valued read. #357's icon row therefore rides the new mode with nothing to keep in
step, exactly as the ruling above intended.

The rulings, all dev calls, all made before building:

- **DAMAGED is HP BELOW MAX, full stop.** The alternative on the table was "anything to report" —
  HP loss *or* a held element state — because #357's row rides the bar's gate, so a full-HP unit
  that is SOAKED wears no icons in this mode until you hover it. Reachable (heal a burned unit to
  full and it keeps the state), and ruled acceptable: the mode's job is to thin the board out.
- **A body needs no clause of its own.** `_go_downed` clings the unit at 1 HP, so it is damaged by
  the ordinary rule and #322's DOWNED glyph and rescue clock stay up. Worth stating because the
  obvious reading of "damaged" would have added a lifecycle term nothing needs.
- **`foretold` is untouched, and gets its own case under the new mode.** The clause the ticket said
  it may not touch. It has its own test rather than resting on the always-on cases, which cannot
  see it: with EVERY set, every bar is up for the preference anyway.
- **No cfg migration.** `ALWAYS_SHOW_HEALTH` became `HEALTH_BARS`, so a saved "always on" resets to
  hovered-only once. That is this store's already-declared behaviour — a deleted member leaves a
  dead cfg key — and the project bans legacy shims. Named because a play-check runs under the dev's
  own `settings.cfg`.

**The real cost was the settings TABLE, and it is paid once.** `DEFS` described booleans and
`SettingsScreen` is a pure projection of it, so this is the first non-checkbox row the page has ever
had. What landed:

- **A row's KIND is derived from the table, not stated in a second field** — a row with `options` is
  a choice. `is_choice` asks that question and there is nothing to keep in step.
- **A generic core with typed façades**: `value_of` / `set_value` / `default_value` are what a
  caller walking `DEFS` uses (`board_fingerprint` is the one such caller), and `is_on`/`set_on` plus
  `choice_of`/`set_choice` sit over them for callers that know their row's kind. `default_of` folded
  into `default_value`. The five production `is_on` readers are untouched.
- **The projection property survives**, which is the whole reason (a) was chosen over two bools: the
  page learns that a row is a toggle or a choice, never *which setting* it is looking at. The test
  that pins "every declared setting gets a row" asks about both kinds — narrowing it to the toggles
  would have retired the property for exactly the rows that needed it.
- **`PlayerSettings.HealthBars`'s values ARE the option indices** — a declared duplicate per Law #4,
  with the enum authoritative and a test holding the two in step. Nothing else could notice them
  drifting: a list one label short leaves EVERY unpickable, silently, with the strip looking right.
- **An out-of-range cfg value falls back to the default.** The cfg is a text file the player can
  open, so an index past the options list is reachable *input*, not a bug.

**The widget is a SEGMENTED STRIP, and an `OptionButton` was structurally out.** A dropdown opens an
embedded `PopupMenu`, and `CLAUDE.md`'s SubViewport gotcha (2) records that those do not dismiss on
outside-click inside `GameView` — the #26 reason the action menu has been Control-based ever since
and "must not go back to a `Popup`". `ReportPanel._build_kind_row` is the same shape already
shipped, and its own comment states the other half of the reason: every choice is readable, and
which one is picked is readable, without a click. Three toggle `Button`s in one `ButtonGroup`, so
"two modes chosen at once" is unrepresentable rather than merely avoided.

### ...and the ZOOM overrides all of it (2026-08-28)

Found in play once the three modes shipped: **a zoomed clash read one-sided.** Under the shipped
hovered-only default the TARGET already wore a bar — `foretold` names everyone the plan changes, and
#354 keeps it up to the end of the pass — while the ATTACKER wore nothing unless it was countered.
The dev's rule: *"healthbars should always be on in the battle zoom, no matter the settings."*

**An OVERRIDE of which mode is in force, NOT a fifth reason to be up.** `bars` reads `EVERY` while a
fight plays, and the gate below it is untouched — still `hovered or foretold or marked or preferred`,
four disjuncts, so #357's icon row keeps riding it with nothing to keep in step. A fifth disjunct
would have claimed the zoom is *its own reason a bar is shown*, which is a weaker and different
statement: what was asked for is that the preference stops applying for the duration.

**The signal is a PASS-level twin of `beat_profile`** — `CameraController.playback_cinematic`,
published by `execute_orders` right after it claims the camera, cleared on both edges by
`set_playback_locked` beside the line, span and weight. **Its lifetime being structural is the whole
design**: "the pass ended" and "this is false" are the same event, so no reader needs a second fact
to know when to stop.

**Why not just read `beat_profile`, which already says CINEMATIC?** Two reasons, both measured, and
each alone is fatal:

- It is **held, not cleared** — its own note says *"between passes the last beat's profile stands"* —
  so a readout gated on it says CINEMATIC for ever after the first clash and never puts the bars away.
- It **toggles within a pass by design**: an action that named no beat publishes `BOARD`, deliberately,
  so the camera sway does not ride in from the previous beat. Bars keyed to it would blink several
  times inside one fight, even with the zoom on ALWAYS.

The mirror in `battle3d._mirror_camera` therefore sits **above** that function's early return, where
`beat_profile`'s own copy sits below it. Below the return the poll simply stops when the lock
releases, which is the same staleness one layer along.

**WHICH passes: `_shows_a_fight`** — cinematic AND a non-empty sheet — extracted from
`_stage_the_fight` rather than written twice, since the tear-out was already asking exactly this pair.
The `cells` half is load-bearing under ALWAYS, where *every* beat is cinematic: an empty sheet means
no main actions, so a pass of nothing but walking is not a fight and forces nothing.

**The crowding note above is why this was asked for**, and it stays open: "damaged only" thins the
board out, which is a *workaround* for overlapping bars as much as a preference. Collapsing the
remaining labels onto one priority is still the fix if the dev's eye says it is needed.

**What the row EXPOSED, found in play the same day: the settings card had no ceiling.** The choice
row is taller than the checkbox it replaced, which pushed the page past the 1280×720 viewport and
left Close off the bottom edge — and since the card swallowed Esc, opening settings locked the game.
Neither half was new: the card was one row from overflowing before #418, and `PauseMenu` and
`GlossaryScreen` ate Esc exactly the same way. Both are fixed at the scaffold — see `CLAUDE.md`'s
`ModalCard` entry for the cancel mechanism and the bound-your-own-body rule.

Two things worth carrying out of it. **A card that fits by showing NOTHING satisfies "the exit is on
screen"** — the first version of the regression case passed against a body collapsed to zero height,
and only a mutant found it; the case now asserts the body is real as well as the exit reachable.
And **the existing round-trip case pressed Close by calling it**, so it stayed green against a button
at y=2145 on a 720-tall screen — #131's *a button nobody can press*, one level up: a test that
reaches a control by reference cannot tell you a player could have reached it.

## Health is a grid of CUBES that fall away ([#314](https://github.com/Phaazoid/Godoiosis/issues/314), BUILT 2026-08-22)

Dev idea from #229's own feel-check: *"In fire emblem, health bars are denoted by a green bar with
individual ticks in it per unit of health, that visually drain. That would be cool to do with 3D
blocks, that visually fall away, explosively."* This replaces #229's bar outright — one cube per
point of HP, and losing HP knocks the cubes that were standing out of the grid.

**Why counting beats estimating HERE.** A continuous bar communicates *roughly how hurt*, which is
the right readout for a game where the next hit's damage is a distribution. Law #1 says there is no
randomness and Law #2 says the queue never lies, so this game's player wants *exactly how many
points stand between this unit and the next rung* — and a cube per point answers that at a glance.
It is the readout the ruleset actually earns.

The rulings, all dev calls, all made in a grill session before building:

- **A cube is 5 texels INCLUDING a 1-texel black cage, ten to a row.** Ten is what makes it a glance
  rather than a count — one full row plus four reads as 14 without counting. Rows grow upward, the
  BOTTOM row fills first, so losses show along the top where a cube has clearance to leave.
- **The cage is where the 3D read comes from, not lighting.** Dev's words: *"each edge of the cube
  should be black, corner to corner. I'm thinking little green squares, with black outlines."* It is
  a generated texture — black frame, white centre — on all six faces, tinted per role through
  `albedo_color`, which is #325's ring-outline trick reused: black survives the tint and white takes
  it, so one texture serves green, red and amber alike. **Lighting was ruled out rather than
  forgotten**: #229 already established this display must be fog- and light-immune, so a lit gauge
  would change with the time-of-day preset and wash exactly as its first pass did.
- **A lost cube is RECESSED and RED, not gone.** Every socket keeps a cube, so max HP stays readable
  from the grid's shape, and the dent is a second cue beside the colour — which is what makes the
  readout survive distance, peripheral vision, and the green-against-red pair. *(Rounds 3–4 moved the
  dent from depth to SHRINK — see below — and the "full rectangle" half was always the backing quad's
  doing rather than the grid's: a max HP that does not fill its last row is an L now.)*
- **#313's notch is DELETED.** Colouring the exact cubes the plan will take says where it lands more
  precisely than a mark beside them, so keeping both would state one fact twice (Law #4).
- **Losing HP pops the cubes out, tumbling, with ONE bounce off the board.** Scatter is derived from
  the cube's index, never `randf()` — Law #1 is about gameplay so a random sparkle would not break
  it, but a deterministic fan costs nothing, keeps RNG out of presentation entirely, and lets a test
  assert where a cube went.
- **A heal RAISES cubes out of their dents rather than flying them in.** The socket is a restored
  cube's natural origin; an arriving cube would need an invented one.
- **A death detonates the whole remaining grid**, harder than an ordinary hit. *Going DOWN needs no
  special case* — `_go_downed` parks the unit at exactly 1 HP, so the ordinary diff bursts everything
  above 1 for free.
- **No readout, no burst.** Cubes are pieces of a thing you can see. Damage taken with nothing on
  screen is #188's gap, and it wants a shake on the SPRITE, which is visible either way.
- **The HP digits survive.** The cubes are the glance read and the digits the exact one — different
  speeds of reading, not a duplicate. It also keeps #322's rescue clock anchored to the size
  reference it takes from them.

Four things that generalise past this ticket:

1. **A TICKET'S OWN PREMISES ARE STALE-ABLE, and three of #314's were.** It asked for a shared damage
   EVENT with #188 — `UnitInstance.hp_changed` already existed, and the readout is told HP every
   frame anyway, so the mirror diffs what it already reads and no seam was built. It claimed the flat
   view's answer was in scope — the flat view has no over-unit health readout at all, which this doc
   had already declared. And it implied the falling cubes might not be seen — measured false: the
   plan a readout rides is live for the whole resolution pass on player *and* AI passes, so a unit
   taking a hit already wears one at default settings.
2. **A BASELINE THAT ONLY ADVANCES WHILE A DISPLAY IS UP GOES STALE.** `UnitMirror` tracks every
   unit's HP every frame, *before* the visibility gate — because a baseline refreshed only while a
   readout was up would read the entire hidden loss as damage taken this frame the moment the readout
   reappeared. The general form: **when a diff drives an effect that is gated, the diff and the gate
   are two different questions and must be evaluated in that order.**
3. **A POLL CANNOT SEE A DEATH.** `die()` emits and `queue_free()`s in the same frame and `reconcile`
   skips a unit already queued for deletion, so the mirror never observes HP at 0; and noticing the
   unit VANISH instead would fire on `clear_board`, which frees without dying. `unit_died` is
   therefore the one signal this deliberately poll-based node listens to, and the exception is
   structural rather than a preference.
4. **A TEST'S PRECONDITION THAT IS NEVER ESTABLISHED IS NOT A PRECONDITION.** The baseline case
   (2 above) originally never let the readout be up *before* the damage, so `_last_hp` was never
   seeded and the `.get(id, current)` default silently stood in for it — the case passed against a
   mutant that froze the baseline behind the gate. Found by falsification, fixed by hovering first.
   The mutant that PASSES is the finding.

**3D only, inherited** — the flat view still has no health readout of any kind, which is #229's gap
under [#292](https://github.com/Phaazoid/Godoiosis/issues/292) and not a new one.

**Spun off:** per-attack burst character — a heavy blow scattering wide, a pierce punching through —
filed as [#469](https://github.com/Phaazoid/Godoiosis/issues/469), raised by the dev during the grill and deliberately out of scope here.

### Round 2 — the playtest (2026-08-22)

The dev played it and sent eight things. **Two were bugs I shipped, and both are worth keeping for
their shape rather than their fix.**

1. **The HP digits were invisible, and no knob could have rescued them.** The label was placed at the
   cube's CENTRE depth; a cube spans zero to a full block toward the camera, and the cubes are opaque
   and write depth — so the text sat *inside* a solid and was depth-rejected. **The general form: the
   moment a flat display gains DEPTH, every "just in front of it" offset in it becomes wrong, because
   the thing it was measured against stopped being a plane.** Pinned now as a relationship (the label
   clears the front face), not a value.
2. **The heal pop could not animate, because it borrowed the RECESS as its travel distance.** Two
   texels is a couple of screen pixels, and at a recess of 0 — a legal setting the dev was actively
   considering — the animation had exactly zero distance to cover, so it read as instant however long
   the time knob said. **An animation's amplitude must never be a knob that may legitimately be zero.**
   It has its own `hp_pop_lift_texels` now.

The six feel calls, each a dev ruling:

- **A killing hit throws the RED cubes too** — *"On a killing hit, even the red blocks should fly
  away."* So `burst` takes a colour per cube: one sweep, the standing ones leaving green and the lost
  ones red, rather than two bursts that would each restart the stagger.
- **A multi-cube burst MARCHES** — *"march through the bricks that blast out, from start to finish."*
  Each cube waits its turn, and a waiting cube **sits in its socket rather than hiding**, so the grid
  breaks apart in sequence with no gap running ahead of the cubes.
- ~~**Only the FRONT face wears the cage**~~ — **REVERSED BY ROUND 3, and the reversal is the more
  useful entry; see below.** The complaint was *"The top of the cubes blend in a little too easily,
  and look like another row. Tops should be all one solid color."* Taking the cage off five faces
  answered a bigger question than the one asked, and cost the cubes their read entirely.
- **The grid is HELD IN PLACE by default** — *"The health bars are 3D, they should not billboard
  towards the camera."* It sits on the board's own axes like the voxel props; a knob restores facing.
  The cost is declared rather than fixed: orbit past one and it goes edge-on to a line, which is what
  keeping it in place *means*.
- **The recess needed a second pass, and the reason generalises.** *"The recessed red doesn't
  actually look too great, it looks somewhat different than the image you built for me."* He was
  right and the diagram was the thing at fault: it drew a socket with a dark inner rim, which the
  geometry cannot produce — a cube pushed back is still a same-sized square head-on, because there is
  **no socket wall to see**. It now SHRINKS and DARKENS as well, so a lost cube pulls away from its
  neighbours' cages. **A mock-up can promise a read the geometry has no way to deliver; when the
  in-game version differs from the picture, suspect the picture.** *(Round 3 then took the depth out
  of the default entirely — it and holding the grid still are incompatible.)*
- **Spun off rather than chosen:** [#474](https://github.com/Phaazoid/Godoiosis/issues/474), three
  heal animations to try — the priest *shooting* the cubes in, cubes falling from the sky, cubes
  sprouting from the ground. The interim pop stays as the fallback. Its blocking design question is
  the same one #469 has: an arriving cube needs a SOURCE, and the readout deliberately knows only
  that HP moved.

### Round 3 — the cage comes back (2026-08-22)

*"We were only supposed to differentiate the tops of the cube from the rest of the bar — now they
don't look like cubes at all, just a green mass with black painted on."* He was describing round 2's
own fix, and the finding is about the SCOPE of a fix rather than about cubes:

**A fix scoped to ONE element is not made stronger by applying it to the whole class the element
belongs to — it becomes a different fix.** The ask was *tell the top apart from the front*; what
shipped was *take the cage off everything that is not the front*, which also removed the thing the
cage was for. The tell was available before the build: the complaint named the top and the fix named
five faces.

- **The cage is back on all six faces; the TOP is darkened instead** (his own suggestion). Per-face
  **vertex colours** carry it — with `vertex_color_use_as_albedo`, albedo is
  `albedo_color × texture × vertex colour`, so the black frame survives any shade (zero times
  anything is zero) and only the coloured core dims. One mesh and one material still; a second
  surface with its own material would double the draw calls on every cube of every grid. This also
  collapsed the grid and debris meshes back into one, which is what round 2's fork had split.
- **Not billboarding WINS over depth.** *"I think pushing them back and having the thing not
  billboard are incompatible, and having it not billboard is more important to me. I do like the
  slightly shrunken effect, though."* So the recess depth defaults to 0 and the shrink carries the
  empty socket alone. The knob stays — *"I'll have to play around with it"* — it just starts out of
  the way.
- **An accessor that collapses at a legal knob value is not one a test can lean on.** `block_is_proud`
  reads DEPTH, so at a recess of 0 it answers true for every socket. Anything asking *which sockets
  are full* reads the material now.
- **The march starts at the TOP RIGHT** — *"The top right is the start of the healthbar… when we hit
  the second row, right side again."* Since the grid fills bottom-up and left-to-right, that is the
  burst order simply REVERSED, with no second rule to keep in step.

### Round 4 — there is no background (2026-08-22)

*"This is a 3D display, we don't need one at all, and my option slider can't get rid of it. It's just
a weird black rectangle floating in space."*

**The backing quad was a VESTIGE of the 2D bar, and its knob had stopped meaning what it said.**
`bar_outline_texels` was the flat bar's black border — a quad drawn slightly larger than it — and
#314 kept the quad, renamed it the plate, and gave it a second job (something for a lost cube to sink
into). At an outline of 0 that leaves the grid's exact bounding box in black, which is why the slider
could not remove it: **zero was never *off*, it was *no margin*.** Both are deleted.

- **A knob that survives the thing it names will be read as still meaning it.** The dev spent a round
  dragging a slider whose whole range was margin, on a rectangle he wanted gone. The general form:
  when a feature absorbs an older one's node, its knob needs re-justifying or retiring — inheriting
  it silently is how a dial ends up unable to say the thing its name promises.
- **The L is the honest shape.** Max HP is base ± the CON band, so 18 and 22 are real, and at ten per
  row that leaves a partial top row. The backing painted black behind the sockets that do not exist,
  which read as *lost* HP rather than as *absent* — a small lie, since lost HP is red. The grid now
  shows exactly the sockets a unit has.
- **The state-icon row measures off the GRID now**, not the deleted quad's edge — at the shipped
  outline of 0 those were the same place, which is why nothing moved.
- **The law pins the ABSENCE as a relationship** — no quad the readout draws sits behind the cubes'
  front plane — rather than as *there is no node called the plate*, which the next backing under
  another name would pass. It also subsumes round 3's z-fight case, since the fight needed something
  coplanar with a cube's back face and nothing is drawn there any more.

### Round 5 — a heal FILLS IN (2026-08-22)

*"Currently, heals pop in all at once, I think they should fill in in reverse order that they are
knocked out from attacks."* The order was already decided by round 3: the burst leaves **descending**,
so the **lowest** socket of a run is the last one knocked out — and reversing that makes it the first
one back. Ascending is also the order the grid fills, so a heal grows it exactly the way adding max
HP would, with no second convention to keep in step. **A cube comes back the way it left, backwards.**

- **One clock, N delays — not N tweens.** The pop's driven property was a 0→1 phase every rising cube
  read, so they shared one clock *by construction*. It is elapsed **seconds** now, tweened to a span
  that outlives the last cube's delay, and each socket subtracts its own. The ownership rule is
  unchanged (a redraw writes the target, never the clock), and killing a half-finished march is still
  one `kill()` rather than a hunt.
- **`hp_pop_stagger` is its own knob, not the burst's.** Both answer *how long until the next one*,
  but the burst's races a cube's whole **flight** while this one races a single **rise**, so the same
  number does not mean the same thing on the two. Its default is deliberately larger than the burst's
  for that reason: a stagger much smaller than the pop time leaves every cube mid-rise at once, which
  is one blob however slow you make it — the shipped `block_pop_time` of 0.54 is what made the
  simultaneous version so visible.
- **A SCHEDULE can be read without racing the clock that plays it.** The burst's twin case asks which
  *slot* launched first, because a slot IS its launch order; a healed cube never leaves its socket, so
  there is no such handle. Chasing the depths instead would have let two idle frames decide how far a
  tween had got. `pop_delay_of(index)` is public for exactly that, and it is the SAME derivation the
  animation runs on, so what the test reads cannot drift from what plays.
- **Declared consequence, not designed away:** staggering creates a state that did not exist before —
  a cube *waiting its turn*. It is GREEN while it waits, because the material comes from the HP
  numbers and was left alone. Holding it red would couple the colour seam to the animation seam and
  soften `filled_block_count()`, round 3's non-collapsing answer to *which sockets are full*, in the
  middle of a pop.

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

**A standing squad wears its rings AND its leader's crown** — the dev's ruling, 2026-08-21, taken on
[#449](https://github.com/Phaazoid/Godoiosis/issues/449). `draw_squad_unit_icons` is one answer to
*draw this squad's membership markup*, so the standing sweep raises the crown with the rings and it
does not come back down on the way out of a hover; the setting's own description names the crown for
that reason. **This is not the #325 law being broken.** That law is about a marker going MISSING —
the crown badge died because the health bar's preference could hide leadership entirely — and here
the OFF branch is exactly the pre-#435 behaviour, so no leader is ever left with no persistent
marker. What needed ruling was a branch nobody had decided, and which a test had quietly assumed the
other way: `test_overlay_mirror` asserted *"the crown clears on the way out"* as an unconditional
truth after #435 had made it conditional. **A setting that forks a marker's lifecycle forks the
tests that pin it**, and the branch left unpinned is the one that goes wrong silently.

**A CHANNEL THAT IS CLEARED WHOLE HAS TO BE REDRAWN WHOLE, and the per-squad redraw is where that
bit.** `OverlayManager.redraw_squad_unit_icons` clears every `CROWN`/`SQUADMEMBER` marker and then
draws the ONE squad it was handed — fine for a decade of selection-scoped markers, since the only
markers that should exist belong to the thing being selected. Standing rings are the first tenant of
that channel that has to survive somebody *else's* redraw, and `HoverPresenter` calls it on every
hover-move preview: so hovering one squad stripped every other squad's rings, which is the state the
board would have sat in for most of a feel-test. `standing_squads_source` (a Callable injected by
game, the `SquadManager.board_source` idiom) is what lets the redraw put the standing set back
without `OverlayManager` learning what a player setting is. The general form: **adding a persistent
tenant to a channel means auditing every writer that clears the channel, not just the ones that
draw the new thing.**

**It bit a SECOND time, at a different clear, and that one reached the dev.** `clear_selection_icons`
is called by `HoverPresenter._hover_idle` on **every hover change while nothing is selected** — bare
ground included — so the rings drew at load and the first mouse movement wiped them: *"I toggle them
on, go back into the level, and they are not on. I still have to hover to show them."* Every headless
case passed because none of them ever **moved the cursor**, which is the one thing a player does
constantly. The fix is the method's own name taken literally — it drops the SELECTION's markers, and
standing rings are not the selection's, so they go straight back up. `game.draw_standing_rings` is
now the single implementation of *what is on this channel with nothing selected*, called by that
clear and, through `OverlayManager.standing_rings_drawer`, by the per-squad redraw; the injected
Callable DRAWS rather than returning a squad list precisely so there is not one answer here and
another in `game`.

**The sharpened form: find the clears by grepping for them, not by imagining which ones matter.**
Both misses were writers that clear the channel for a reason unrelated to the new feature, and the
second was reachable by a mouse movement on a board with nothing selected — the most ordinary state

**A SENTINEL MUST NOT BE REACHABLE AS A DISPLAY VALUE ([#441](https://github.com/Phaazoid/Godoiosis/issues/441), 2026-08-21).**
The dev found solo units flashing a **white** ring between AI turns in Prolog. `Color.WHITE` is
`Squad.ring_hue`'s *undealt* sentinel — dealt only at a squad's first squadmate — so the instant it
rendered it was being read as a colour. Cause: `redraw_squad_unit_icons` drew a ring for every member
of whatever squad it was handed, and **two of its three callers had no membership gate**
(`_on_squad_has_no_actions`, `_on_unit_action_cancelled`; only `_repaint_squad_plan` checked). The
timing was the tell — `_end_squad_turn` drains the queue with `remove_action`, each firing
`action_cancelled` into the ungated redraw, which is exactly *"after one ends their move and another
starts theirs"*. **It predated the rings' standing lifecycle entirely** (verified byte-identical on
`main`), so #435 neither caused nor could have caught it.

The gate now lives in `draw_squad_unit_icons`, where the *meaning* is — a ring says "this unit is in
a squad with somebody", so a solo squad has nothing to say on the channel and every caller inherits
the answer. The crown rides the same gate: a solo unit leads nobody, which is the rule
`_on_squad_became_active` already applied to its own crown, so the two now agree.

**The question had three spellings and was one gate away from a fourth** — `Unit.has_squad()`,
`_repaint_squad_plan`'s `has_squadmates`, and #435's standing sweep each re-derived
`get_members().size() > 1`. It is now `Squad.has_squadmates()`, and all three route through it;
Law #4 says extend the existing answer rather than add another, and the *fourth* spelling is exactly
what a bug fix is tempted to write.
the game has.

**JOIN SQUAD PICKS WITH THE RINGS THEMSELVES ([#442](https://github.com/Phaazoid/Godoiosis/issues/442), 2026-08-21).**
Dev, on seeing the standing rings in play: *"when joining a squad, a target icon appears the units
that are joinable. However, with the squad rings, now we have two icons kinda representing the same
thing."* Entering the mode now draws each joinable squad's own rings and **pulses** them, and the
generic target-pick ground marker is suppressed **for this flow only**.

**This refines #346 rather than excepting it.** Ground markup still carries the interaction; what
changes is the *form* inside that channel when the thing being picked is a **squad**, because then
the squad's own ring already says what the pick marker repeats. The other three pick flows keep the
marker and are untouched — rescue and intimidate target a unit with no ring to collide with, and
Squad Up's candidates are solo units who by definition have none. Squad Up had already been through
this reduction: `draw_create_squad`'s comment records #346 deleting its TARGET icon as *"two markings
of one fact"*, and join-squad was the half left behind.

**Three things the build settled, each worth keeping.** The **hue is never the undealt sentinel
here** — `can_join_squad` ends in `squad.leader.has_squad()`, so a joinable squad always has
squadmates and therefore a dealt colour, which is why #441's `Color.WHITE` trap cannot reach this
flow. **The ring pulses and the crown does not**: principle 2's motif rule, and #346's channel split
in miniature — the ring is what the interaction is about, the crown is what the unit is. And
**suppressing a marker must never suppress the CLICK**: `target_pick_cells` is still filled, since
`_click_picking_target` validates against it, and the two are set two lines apart — a case pins the
pair, falsified by moving the cell list inside the same guard, which reads in play as *"Join Squad
does nothing"* rather than as a missing marker.

**One answer replaced two that disagreed.** `draw_joinable_squads` marked **leaders** while the
candidate query made **every member** clickable — the marking and the clickable set were separate
enumerations of one question. `game.joinable_squads` is now that question, read by both.

The pulse is `Classes/core/Pulse.gd`, the shared "look at this" cadence, and the tween is hosted on
the ICON so it dies with it rather than depending on a call site to stop it — `Pulse`'s own contract
is that one left running keeps writing its property underneath everything else. `_style_icon` yields
to a live pulse, the same way `UnitVisuals.set_highlighted` does. Peak brightness is a `GameKnobs`
row (`SQUAD_RING_PULSE_GAIN`) — a **gain on the ring's own hue**, so a pulsing ring still reads as
its squad's colour: the pulse says LOOK HERE, the hue still says WHICH SQUAD.

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

**A DOWNED BODY WEARS THE GLYPH AND ITS RESCUE CLOCK ([#322](https://github.com/Phaazoid/Godoiosis/issues/322), 2026-08-21) — the section's line above about downed/maimed belonging here, made real.**
The complaint was the readout, not the marker: `_go_downed` parks a downed unit at **exactly 1 HP**,
so a body and a living unit clinging on both render `1/20`, and those are two completely different
board states — one is a rescue, the other can still act, still counter, and still be finished off.
Three things about the answer generalise.

**It is a ROW ENTRY, not a fourth reason to be up.** The glyph is appended to `set_state_icons`'
array by `UnitMirror`, in the hover card's own order (element states first, lifecycle after), so it
inherits every property #357 bought — one gate, one layout, no second visibility expression. Riding
the bar's gate is legitimate *here specifically* and the reason is worth stating, because #325's law
says a marker answering "what is this unit" must not ride another marker's visibility: **the downed
fact is already carried unconditionally by the unit's downed ART**, so the glyph disambiguates a
readout rather than being the only thing that marks the body. A status with no art of its own could
not make that argument.

**The FORM was already decided, one shelf along.** `hover_info_grid_container` has always drawn
downed as *icon then turns-remaining*, and `info_panel` as a `DOWN 3` badge tipped "Dies in N turns
without rescue" — so the ticket's three candidate forms (grey the bar / a state icon / show the
clock) were not really open: the game had picked icon-**and**-clock, and a board band inventing a
fourth spelling would have been a second answer to a question already answered. The clock is also
the number that drives the decision, which is what made it the interesting candidate.

**The glyph got a home on the way through.** `Down.png` was preloaded independently by the hover
card and by `AttackAction`; a third surface is where that stops being tolerable, so `StateIcons`
gained a `DOWNED` const — deliberately **not** an `ICONS` entry, since that dictionary is keyed by
`Elemental.State` and a lifecycle is not one. `AttackAction`'s DOWN/KILL/MAIM triple stays put: a
predicted lethality **rung** is a different question, and it needs kill and maim art no status row
has any use for.

**THE HP DIGITS ARE THE FLOOR FOR ANY NUMBER IN THIS VOLUME (dev, in play, 2026-08-21):** *"any
number needs to be at least as big as the numbers in the healthbar to be readable. Smaller than
that is just impossible."* The clock shipped smaller and had to be raised — and the ruling that
came with it is the more useful half: **that is a legibility floor, not a taste value, so it is not
a knob.** The count reads `number_height_cells` directly, joining the colour and outline it already
inherited, and its own size dial was deleted rather than re-defaulted — a dial whose entire lower
range is unreadable is worse than none, and every value removed is one fewer way for two texts on
one display to disagree. Wanting a number *bigger* than the HP digits would be a knob to add
deliberately. Pinned as a RELATIONSHIP (`downed_count_glyph_height >= number_glyph_height`), so
retuning the HP number moves both sides and can never red the suite — the tuning razor's own shape,
applied to a rule rather than a value.

**No 2D half, and that is not a new gap.** The flat view has no over-unit health readout of any
kind, so there is no `1/20` there to disambiguate — the ticket's own "the 2D has the same gap" line
was measured false. The 2D already says downed twice (the swapped sprite, the hover card's icon and
count). #229's absent flat-view readout remains the declared
[#292](https://github.com/Phaazoid/Godoiosis/issues/292) asymmetry it always was.

The doctrine governing everything that enters these channels (dev, 2026-08-18): *"Having access to
fancy effects doesn't necessitate using them. Using them in the correct places rather than
everywhere makes them have more effect."* Unit status (#358) is a sanctioned place; a fancy effect
everywhere is a fancy effect nowhere.

## The action menu is a RING ([#467](https://github.com/Phaazoid/Godoiosis/issues/467), BUILT 2026-08-21)

The floating dropdown became a radial with the unit's own map sprite in the middle. The dev's two
complaints were separable and only one of them was a widget problem: the look, and the bloat —
`ACTION_DATA` declares nineteen verbs and a leader with a rune on a capture point beside a downed
ally is offered fifteen at once. **A ring does not fix that by being a ring.** It fixes it by
nesting, which is arithmetic: at the same arc length per slice, a ring at twice the radius holds
twice the slices, so no single ring has to hold nineteen.

Five rulings, all the dev's, none of them re-derivable from the code:

1. **The ring COMPACTS** — only live verbs are drawn. *"There are far too many unit dependent
   actions. Group move only shows for squad leader, etc."* A fixed ring of greyed slices would be
   mostly empty wedges on most units. The price is positional constancy: a verb's angle moves with
   the unit. `ACTION_DATA` order is still the clockwise order, so the *sequence* holds still even
   when the angles do not — which is the half of the muscle memory that was recoverable for free.
   **This leaves #166's deferred decision deferred**: top-level rows stay omit-when-unavailable, so
   the reason-first ladder is not owed at this level. **Compaction is the MAIN ring's membership
   policy and nothing else's** — a rune's un-channelable carvings are still listed and greyed with
   a reason one ring out, which is where #166's catalogue law now lives.
2. **CATEGORIES all the way down** — five slices (Move / Attack / Act / Squad / Turn), verbs one
   ring out. Chosen over a flat ring of live verbs having seen both laid out: *"better in every
   scenario."* It also **overturned #88's separation of Weapon Action and Transmutation**, which
   `MainActionMenu`'s header had recorded as settled law — *"I was going to get around to grouping
   attack and transmutation option in the old menu anyways, I just was waiting for a full rework."*
   Worth carrying: that was a **holding position pending this rework**, which is a different thing
   from a ruling being wrong, and the file asserted it as law either way.
3. **CONCENTRIC expansion, and the ring PERSISTS** — a category grows a full ring around the one it
   came from, and the inner rings stay drawn. The reason given is stronger than "more room" and is
   the actual requirement: *"the whole menu sticks around until we've made a final choice, making
   it easy to choose again if we click wrong without having to start over."* A deeper ring is
   **rotated to begin at its parent's angle**, so a group blooms out of where you pointed.
4. **Selection is ANGULAR and the hit area is UNBOUNDED** — *"we don't even need the clicks to be
   on the menu; as long as the mouse is in the radial area of where an option would open up to on
   the map, they are hovering it."* Hover previews the next ring in a not-open-yet state, so every
   category's contents are readable without spending a click; right-click goes back one ring, so
   *"we never need to even see the mouse."* **Radius means nothing**: the deepest open ring owns
   every angle, and shallower rings are drawn as the path taken rather than pointed at. The
   rejected alternative (radius picks the level) gives the unbounded area to *one* level and a thin
   annulus to every other, and cannot port — a stick holds an angle indefinitely but not a radius.
5. **A deeper ring PAINTS less than the one inside it** — *"if we try to fill in a full radial
   circle for every secondary or tertiary menu, it will look ugly."*

### What the build had to declare, because two of those rulings only work together

**The drawn shape and the hit sector are two different things.** Sectors always tile the full 360°
— that is what "the deepest ring owns every angle" means — and a wedge merely *paints* part of the
sector it owns. `selection_at` therefore does not take a paint fraction and `slice_polygon` is the
only function that knows about one. The falsifiable form is a 360° sweep asserting every degree
resolves to exactly one slice; teach the hit test about the paint and it reds immediately.

The consequence is that **pointing into the air between two painted wedges still selects the
neighbour**, which would be a lie if nothing showed it — and ruling 4 already requires the current
selection to be drawn at all times. The two rulings are consistent only *together*, which is worth
knowing before anyone simplifies either one alone.

**Two behaviour losses, both deliberate.** With an unbounded hit area there is no "miss", so
clicking the board no longer dismisses the menu (a click anywhere commits the direction you were
pointing) — the replacements are right-click and a dead zone at the centre. And right-click no
longer means dismiss first; it means collapse one ring, dismissing only at the top.

**The tree is snapshotted at open.** A ghosted category shows its contents before it is opened, and
those contents come from real board walks (`guard_candidates`, `adjacent_downed_allies`). Querying
per hover would be wasteful and, more importantly, *wrong*: a preview that re-queries can disagree
with what commits. Safe by construction, since the menu is modal.

**The portability is a seam, not a side effect.** `(level, index)` is the one authority and the
mouse is one adapter feeding it — `aim_at` / `commit` / `back` is the whole vocabulary. This ticket
ships no gamepad bindings (there are none in `project.godot` at all); what it ships is the shape
that keeps them from being a rewrite.

**The look is knobs, not guesses** (#253's rule): centre gap, ring thickness, gap, dead zone, wedge
fill and its per-level falloff, preview opacity, and three slice colours, all on the Game tab.
They are `CLASS_KNOBS` statics rather than `KNOBS` rows because **the menu is transient** — there is
no standing node for a knob to name and nothing to re-apply a change to, which is
`MovementComponent.SHOVE_SLIDE_SPEED`'s shape exactly.

### Round 2: what the first play-through changed (dev, same day)

Six items, and three of them had something underneath worth recording.

**A category whose ONE child is its own verb collapses to a terminal slice.** *"There is no reason
to put Move under Move."* Deliberately **not** "collapse whenever there is one child" — a lone Squad
Up names something the word Squad does not, and single-option submenus are explicitly meant to
survive (they just draw small, below). The same rule is the entire implementation of **"Inspect is
top level"**: a group of one holding the verb of its own name. No special case, no new key.

**The generic Attack row is gone and the ring lists every attack by its own name** — *"the whole
point of that was to save time, but if we already have to navigate through a menu to get to it,
it's pointless."* The trap under it: `WeaponInstance.secondary_attacks()` **excludes** the main
attack, so the Attack verb was the only way to reach it, and deleting the row as literally asked
would have left a plain sword unable to attack at all. What the ask actually requires is the MAIN
attack listing by name alongside the alternatives. Two consequences: a rune's default attack *is*
one of its carvings, so a group is filled with a name-dedupe; and a weapon family whose main attack
was never given a `display_name` now says so on screen, which the dev noted as the point (*"maybe
it'll give us a reason to actually name the basic attack names for each weapon family"*).

**Three verbs left the ring entirely** — Execute Orders, Cancel Actions, End Turn — because each
already had a richer HUD door. The principle worth keeping: **the unit's menu is what the UNIT does;
the turn is the HUD's business.** The one capability genuinely lost is *"wipe everything this unit
has queued in one press"*, which is now N presses of the queue row's X.

**So the End Turn button is permanent.** What its old visibility rule became is the FLASH, and the
same predicate (`faction_all_squads_acted`) now also decides whether pressing it **asks first** —
so a flashing button never interrupts and a still one always does, and the cue and the confirmation
cannot disagree. Two notes measured rather than assumed while making it permanent: `MissionStatusPanel`
already reserved its corner slot *even while it was hidden*, so nothing reflows; and the queue dock
occupies y 25..490 against the button's y 676..712, so the old "these two are never on screen
together" argument was retired without its conclusion changing.

**A wedge is capped at how much it PAINTS** (`MAX_WEDGE_DEGREES`) — *"the massive balloon arcs just
don't look great."* A compacting ring produces rings of one and two constantly, and without a cap
those are a full donut and two hemispheres. It moves no hit boundary, which is the drawn/hit split
paying for itself a second time: the sectors still tile the circle, the leftover angle belongs to
the nearest wedge, and the always-drawn highlight says which.

**Labels ride the curve of their own wedge**, flipped on the bottom half so they are never upside
down, and shrink to a floor rather than overrun. Note the dev's wording was *"ones on the bottom
should face outwards, on the top, inwards"* — which is the unreadable half; his own purpose clause
(*"to be readable"*) is what settled it the other way, and he asked for it built and shown rather
than argued.


### Round 3: naming, and making the readout readable

**A slice is named after WHAT IT HOLDS, not after the most exciting thing in it.** Reload and Burrow
are not attacks and most carvings are not either, so a slice called *Attack* was lying about half
its contents at any given moment — and "Weapon Action" was both long and only half the story. The
kit slice is now labelled **Weapon** or **Rune**, after whatever is equipped: it says whose verbs
these are and claims nothing about what they do. `Act` became `Action` in the same pass. The dev
floated *Channel* for the rune side and then answered himself — *"or maybe we could keep it simple,
Rune and Weapon"* — which is the version that solves both complaints with one rule instead of
mixing a verb with an object.

**`MainActionMenu.category_display(group, unit)` is the ONE answer to what a slice is called**, and
it is public for that reason: three test suites had spelled `"Attack"` themselves, and all three
went red the moment the label moved. A label typed twice is a label that goes stale.

**The readout is solid, backed, and waits.** Transparent text over a live board was the complaint
(*"the transparency + lack of background hurts the eyes"*), so both colours are fully opaque and the
hierarchy between a name and its explanation is **brightness** — alpha is what made it unreadable in
the first place. It sits on a panel, and it appears only after the hover is held for
`gui/timers/tooltip_delay_sec`: **the project setting the inspect panel's own tooltips already
read**, so *"same amount as in the inspect menu"* stays one number rather than a copied constant.

**A preview has to be legible or it is not a preview.** `GHOST_ALPHA` went from 0.32 to 0.8, and a
ghosted ring's LABELS stopped being dimmed at all — the label is the entire point of previewing.
What still says *not open yet* is position and the absence of a highlight, not faintness.

### Round 4: the camera comes back ([#471](https://github.com/Phaazoid/Godoiosis/issues/471), 2026-08-22)

The ring deliberately does not lock the board — that is what lets the player pan around while
deciding. It also means the unit they are deciding *for* can be off screen by the time they commit,
and the order plays out around that unit. **So a terminal pick snaps the view back to it, and
backing out with no order does not.** One line, drawn where the dev drew it: action versus no
action. Every terminal pick returns for now, Inspect included; narrowing it to *verbs that need the
board* is a play call, not a design one, and would cost `ACTION_DATA` a new fact.

The mechanism belongs to the camera contract, not to the menu — see
[`presentation-effects.md`](presentation-effects.md) → *The camera comes BACK when an order is
committed*, which holds why the `ai_locked` mirror was the wrong place to reach for, why it snaps
rather than glides, and the pointer-poll fix that rode along.

What the ring owes it is exactly one call, and **where** that call sits is the whole of the menu's
share: on `action_selected`, which only a TERMINAL pick emits. `cancelled` fires on commits too —
that ordering is #467's own preserved quirk — so the cancel handler structurally cannot tell a pick
from a back-out, and hanging the return there would return the camera on a dismiss as well. Pinned
by a case that dismisses and asserts the camera did not move; a mutant that moves the call into the
cancel handler reds exactly that one and nothing else.

## A move's markup ends with the MOVE ([#558](https://github.com/Phaazoid/Godoiosis/issues/558), FIXED 2026-08-26)

Reported in play, on the branch that had just put the camera on the action: *"during AI turns, the
AI ghost unit stays around for a bit after the unit already reaches its move destination, rather
than disappearing on unit arrival."*

**Nothing pulled a ghost until `_end_squad_turn`.** `execute_orders` opens a pass by calling
`set_projected(false)` on every actor — the real sprite comes back so it can walk — but never
cleared the ghost that had been standing in for it. From arrival onward that ghost was a translucent
copy of a unit standing on the same cell, and it stayed through every other member's walk, every
attack and every side-channel hold. Only the camera work made it visible; the lifetime predates it.

**The arrow was a DIFFERENT bug, and the dev ruled on it rather than inheriting the assumption**
(2026-08-26: *"let's have the arrow match the ghost's lifecycle"*). `MoveAction.execute` freed its
own preview sprites at the FIRST STEP, so the trail vanished exactly when it was most useful. That
clear was also only durable by luck: `redraw_planned_paths` rebuilds every arrow from
`planned_move_by_unit`, which still named the walking unit, so any redraw during a pass put it back
— and #520's choreography is one such redraw away.

**One lifetime, two doors in.** `OverlayManager.clear_move_markup(unit)` is the single call, reached
from `game._on_unit_action_cancelled` (the move was CANCELLED) and from `OrderExecutor` as each unit
arrives (it was CARRIED OUT). Leaving `planned_move_by_unit` is the durable half — both `redraw_*`
rebuild from it, so a clear that only frees sprites is undone by the next redraw, and one that only
erases the store leaks a trail nothing can free again.

**Per unit, not per phase.** The move phase ends with the SLOWEST walker, so a phase-level clear
would leave a short hop standing under its own ghost while a long one finished.
`_execute_action_phase_parallel` already polled `execution_complete` every frame; it now visits every
action instead of breaking on the first unfinished one, and fires an optional per-action hook. The
phase runner still does not know what a move is — the hook is generic and the executor supplies the
meaning.

**The test lesson, which generalizes past this ticket.** The first version of the walking-arrow case
waited for the other unit to arrive, and PASSED against the mutant that restores the first-step
clear: `clear_move_markup`'s own `redraw_planned_paths` rebuilds every OTHER unit's arrow from the
store, so the arrival republished the very sprites the mutant had freed. **A publisher standing
between the bug and the assertion hides the bug** — the case now asserts with no frame awaited, the
one moment in the pass with nothing in between. Its sibling: asserting `planned_move_by_unit`
directly in the arrival case made the redraw case *unfalsifiable*, since every store-shaped mutant
reddened earlier and truncated the file. The store claim moved to the redraw case, where a mutant
can reach it.


Five inbox ideas that this doc owns. Each is recorded with what already answers part of it, because in
every case something does. (*A third health-bar state: damaged only* was the sixth — **BUILT as
[#418](https://github.com/Phaazoid/Godoiosis/issues/418)**, recorded in its own section above.)

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

**A queued move still offers "Move" — BUILT ([#417](https://github.com/Phaazoid/Godoiosis/issues/417),
2026-08-21).** Picking it **cancels** the queued order and re-enters move planning, so backing out of
the pick leaves the unit with **no move** rather than the one it was replacing — the old order is
spent on entry, not held in reserve (dev's spec). The cancel is `SquadManager.cancel_move_for_unit`,
which already existed and already fires the `action_cancelled` the arrow and the ghost clear off;
`revert_if_only_hold` goes with it, because that cancel leaves a hold-position filler and a solo unit
that backs out would otherwise strand its squad **active** behind a queue panel with no X on a hold
row and nothing for right-click to undo. Both of its existing callers already pair the two.

Three things worth keeping, because they are why this was small. **The replacement was already
built**: `Squad._queue_action` removes whatever the incoming order `displaces()` — same actor, same
type — and `SquadManager._hypothetical_actions` previews with the same predicate, so a second move
could never have stacked beside the first. **The invalidation was already exercised**: by the
2026-08-02 fork a re-planned move is never refused for breaking a queued aim — the aim falls to
invalid-in-red instead. **And a re-planned move goes to the BACK of the queue**, since displacement
is remove-then-append; that is pre-existing and invisible today, and is written down here because
[#412](https://github.com/Phaazoid/Godoiosis/issues/412) makes move order tactical, at which point
drag-reorder is the escape hatch rather than a surprise. **#412 shipped 2026-08-26 and that is now
live on both counts**: re-planning a move still sends it to the back of the queue, and the MOVE
section is draggable, so the escape hatch exists exactly where this note said it would need to.

Two things deliberately did NOT change. **Move-before-main stands**: a unit holding a main action
still loses the row, because `MoveAction.actor_can_perform` refuses the order at the chokepoint, so
relaxing that would be a rules change and not a menu one. Greying it with a reason instead of hiding
it stays a live idea, and stays governed by the top-level ruling above — a permanently full main menu
is a UX change, not a readout fix. **Group Move was one-shot for one day**: both rows read
`_can_move` since #443, so the queued-move clause moved down to the Group Move row rather than being
deleted, and [#461](https://github.com/Phaazoid/Godoiosis/issues/461) then removed it — see below.
Pinned by `tests/ui/test_move_replan.gd`, which drives select → press the real button → click a
tile, and asserts on the queue.

**Round 2 (same day, dev call): right-click CYCLES through it.** A queued move is not deleted by the
press — it re-opens its planning, exactly as if you had hit Move again — so the button now walks
`move queued → planning → nothing`. The third rung is free: planning already spent the order on
entry, so leaving the mode is the outright cancel. Scoped to a **lone** move, so a formation still
pops whole (see [squad-system.md](squad-system.md) → *Right-click is a LIFO undo*).

Two seams carry it, and both exist to avoid a second answer. `game.begin_move_planning` is the Move
*gesture* — cancel the queued order, then enter the mode — called by the menu row and by the
right-click branch alike; `game.enter_move_mode` stays the bare mode entry, because thirteen
presentation call sites use it purely to paint the overlay and would start deleting orders otherwise.
`game.select_unit` is the extracted select write point (#107), since re-entry has to select before
`_click_choosing_move` can read anything. Pinned in `tests/ui/test_right_click_cancel.gd` — where
**two existing cases had to be rewritten**: both ended on an order count of zero, which stays true
under re-entry, so neither could have told undo from re-planning until they started asserting
`game_state`.

**[#461](https://github.com/Phaazoid/Godoiosis/issues/461) finished it one row along — and the half
worth remembering is the bug re-derivation found, not the relaxation.** A queued FORMATION is now
re-plannable on the same rule (`game.begin_group_move_planning` spends the formation it replaces, so
backing out leaves the squad with no moves), and that part is two lines — `queue_group_move` batches
through `queue_action`, so `Squad._queue_action` displaces each member's move for free.

What made it worth doing in that diff: **Group Move was being offered when a SQUADMATE held a main
action.** `_can_move` only ever sees the unit whose menu is open, `GroupMoveSolver.plan` authors a
move for that member anyway, `queue_action` refuses it (move-before-main), and the all-or-nothing
rollback cancels *every* member's moves. #443 closed precisely this for the leader and stopped there,
because the gate had no way to ask about anyone else. As a dead click it cost nothing; the moment the
row became re-enterable it would have eaten a committed formation, and a squadmate with an attack
queued is common. `_can_group_move` now asks `_can_move` of every member — **at the Group Move
caller, because Move is a per-unit question and must not start reading squadmates.**

The rollback itself is untouched: the AI and the Play API reach `queue_group_move` without the menu,
so it stays their backstop, and `tests/squad/test_group_move_batching.gd` pins the member case at
that layer too. Its loop is now `SquadManager.cancel_squad_moves`, which the new gesture also calls —
two questions (*give up the advance*, *spend the formation*), one act.

**Still destructive, declared:** with the gate closed, the only rollback cause a player can still
reach is the rare cell-contention case cohesion already records (`followable_destinations` cannot see
two members competing for one bubble cell). Re-planning into that clears the squad's moves. Fixing it
means snapshot/restore around the batch, which would have to be justified at the AI's
give-up-the-advance caller too — not free, and not this ticket.

**Right-click still pops a formation whole** (dev call) — `game._lone_queued_move` scopes the
re-plan rung to a single move, and a formation is one decision (#228).

**Streamline move -> main action.** After a move commits, open the unit's main-action menu
automatically; or a double-click shortcut. Pure flow-feel, no model question. Open: which gesture,
and whether auto-open irritates on the turns a player only wanted to move. **One caution from this
codebase specifically** — `game.clear_selection()` runs on every *terminal* menu pick, not just
cancel (`ActionMenuController` emits `cancelled` before `action_selected`), and that ordering has
already produced two bugs; anything that chains one menu into the next lands directly on it.
*(#467 narrowed it: a CATEGORY pick no longer emits `cancelled` at all, which is the same fix one
level down — but a terminal pick still does, so this caution stands for whatever auto-open ends up
chaining into.)*

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

## The camera takes an ANGLE ([#520](https://github.com/Phaazoid/Godoiosis/issues/520) diff 2a, BUILT 2026-08-26)

Diff 1 made the camera *go to* the action and made the action wait for it. This is the first of
#520's choreography: the camera also turns, so a blast is seen **side-on** — attacker and target
across the frame instead of one behind the other — and the turn between beats reads as a spin.

**Yaw is the only axis of this camera that was already authorable, which is why it went first.**
`battle3d._mirror_camera` writes `_rig.position` from the 2D camera every frame, so the rig's
position is a mirror and moving the node stages nothing — the `UnitMirror` reconcile trap one layer
up. Yaw and distance are the rig's own and already eased in `_process`, and free orbit and Q/E
already write `_target_yaw_degrees` directly with no bounds re-solve, so a director doing the same
is doing exactly what the player does.

**`pose()` is not the door.** It snaps the yaw, adopts the result as the OPENING SHOT, and calls
`drop_stashed_view()` — which is what the camera return is holding. `CameraRig3D.aim_along()` is
the director's own entry point and writes one thing: a yaw target.

**Three yaws now live on the rig, named apart** (Law #4). `_home_*` is where the BOARD starts and
is what R restores; `_borrowed_*` is where the PLAYER was standing, restored when playback gives
the camera back; `_squared_up_yaw` is where THIS PASS started — the detent `align_to_detent()`
snapped to. A directed shot is measured from the third. Captured on the edge rather than read live,
because a live read compounds: beat two would lerp from where beat one landed, so a partial
strength would give the fifth beat more angle than the first.

**Strength is a per-profile multiplier, not a switch** — `Pacing.direction_of`, sitting beside
`drama_of` and shaped the same way. `BOARD_DIRECTION` ships at **0.0**, which is bit-for-bit the
square-on enemy phase the game has always played, so wanting some angle on the plain board later is
one number rather than a restructure. Both are `GameKnobs` Playback rows.

**Two of the three questions cross the seam as data, not as an angle.** `OrderExecutor` cannot see
the rig — it talks to the 2D `CameraController`, which is what the 3D mirrors. So a beat publishes
its **aim line** (`origin_cell → target_cell`, the resolver's own aim) and the rig turns that into a
yaw, because only the rig knows what to measure from. The line comes off the ATTACK rather than off
the two units, so #47's swing at open ground still has a direction and a victim freed mid-pass
cannot take the angle down with it. `BoardSpace.side_on_yaw` is the arithmetic, and it returns the
NEARER of the two perpendiculars — which is what makes the shot a spin instead of a lurch.

`_beat_lines` is a third schedule beside `_beat_holds` and `_beat_subjects`, keyed identically by
the beat's opening action, and inherits their rule: **a beat left out means the camera keeps the
angle it has.** A MOVES beat, punctuation and the side-channel tail have no pair and so no line.

**The consequence to know before touching this: every sprite on the board re-faces as the camera
turns.** `UnitMirror._refresh_facing_on_camera_turn` re-judges `flip_h` against the live camera
basis and the health cube grids `face()` it too, so a spin re-faces the whole board continuously.
That is the effect, not a side effect — it is what makes 2D-in-3D read as dimensional.

**The testing trap, and it is the claimed-camera one again.** A pass on the player's own turn
releases at the end, and the release fires the view return — so the yaw an assertion reads after
`execute_orders` is the camera coming home, not the shot. Claim the lock first (the AI-turn shape)
so the pass's own save/restore lands on `true`. The other half is non-vacuity: **an aim along a
board axis is already seen side-on from a detent**, so an axial fixture gives a case that passes
whether the camera turns or not — the first draft of `test_a_pass_turns_the_camera_to_see_each_blast_side_on`
did exactly that and survived every mutant. It aims diagonally now, and asserts the gap is real
before asserting the camera closed it.

## The camera MOVES AS ONE THING ([#520](https://github.com/Phaazoid/Godoiosis/issues/520) diff 2b slice 1, BUILT 2026-08-27)

Yaw and distance were eased from the start; **position never was.** `CameraRig3D._process` lerped
`rotation_degrees.y` and `_camera.position.z` and nothing else, so every writer that moved the rig
across the board cut. That is what the dev's scratchpad note is about — *"the camera still has a few
cases where it teleports - this should never happen, it should always be a pan"* — and it is the
same movement the tear-out needs, which is why the two are one slice.

**The rule has a SCOPE, and it is his** (2026-08-27): *"that only applies while we're on the map.
One exception we can make is the transition from the map view to the battle view — what we're
creating now. We can start with a pan, but I reserve the right to change the call on that."* So it
is not a global invariant: three writers still cut on purpose, and the transition is a declared
exception rather than an instance of the rule.

**`position` became DERIVED from two channels** in this slice, `_aim + _lift`, written in exactly one
place. (Diff 2b adds a third, the flourish -- see *The camera JOLTS, SWAYS and STOOPS* below.)
- `_aim` is the point on the board. `hold_at()` snaps it, `glide_to()` pans it. A raw
  `rig.position = …` is *overwritten* on the next frame rather than half-honoured — which is a
  loud failure, and it invalidated five test fixtures that had been shoving the rig that way.
- `_lift` is how far the torn-out diorama has risen (#521). Its own channel because the two ease on
  different clocks: **board tracking under playback is HELD** — the 2D camera it mirrors already
  tweens its own travel, and easing on top of an ease is lag between the action and the frame it is
  in — while the lift is the map→battle transition and is the one thing that pans.

**Which writers glide, and which still cut.** The four the dev named are the whole glide list:
the pass-end view return (`restore_view`), both recentres (SPACE and #471's return to the acting
unit), and R. The snaps are `frame()`/`pose()` — a rig still lerping unprojects at one distance and
picks at another, desyncing every screen-space read taken on the way in — WASD, because a held key
is already continuous and easing it only adds lag, and the playback mirror, for the compounding
reason above. All of them go through `hold_at`, so none leaves a stale target for the ease to fight.

**THE GAP THIS CLOSED, and it was flagged at PR #568 and missed in its own build:** `_aim_over`
answers the *board's* surface, so before this the fight lifted into the diorama and the camera
stayed down watching the hole. The lift poll deliberately sits **above** `_mirror_camera`'s
playback gate: `execute_orders` clears the staging and puts the lock back in one synchronous
stretch, so a poll below the gate would never see a frame with the tiles home and the rig would
stay in the sky for ever.

**`_center_rig_on` must never be reached while the board is staged** — `BoardSpace.surface_point`
carries the staged offset and `_aim_over` does not, so a call there would lift twice. Structural
rather than guarded: both its callers are refused while playback owns the board, and playback is
the only thing that stages anything.

**An AI move is framed across BOTH ENDS** (dev: *"instead of just centering on the unit, it should
try to show both their start and end position in the initial shot (should be doable unless super
zoomed in)"*). Two already-eased channels, no new machinery: the 2D camera travels to the
**midpoint** via `pan_to_position` — `pan_to`'s position-taking half, which the unit-taking one now
delegates to — and the rig **widens its distance** through `widen_to_fit`.

- **The follow is gone, and that is the point.** `pan_to` ended with `follow(unit)`; framing both
  ends only means anything if the camera *holds* while the walk crosses it, because following would
  drag the far end straight back out of frame. `test_the_move_phase_takes_the_camera_to_whoever_is_walking`
  was rewritten rather than patched — its name pinned the rule that changed.
- **`widen_to_fit` widens only, never narrows.** A short hop already has both ends in frame at the
  playback distance; pulling *in* to fit one answers a question nobody asked. `set_zoom` is the
  door, so the board's own ceiling still clamps it — which is the ticket's own *"unless super
  zoomed in"*, expressed as a clamp rather than a special case.
- **It is an EDGE, never a per-frame apply**, the same rule the playback-distance reset follows: the
  shot is set up once and the wheel is the player's again for the rest of the pass. Gated on
  `framed_span` itself — the store the answer is drawn from — not on a copy of what it resolves to.
- **`framed_span` is a THIRD published field beside `directed_line`,** and folding them together
  would be wrong: that one is an ANGLE and this is a FIT, so one field answering both would spin the
  camera side-on to every walk.

**The testing shape, and the limitation stated rather than hidden: the ease is invisible headless.**
`_process` lands both position channels in one frame — the fourth escape of its kind in the repo,
beside `Pacing.beat`, `pan_to` and `CameraController._process` — because a suite sampling an
asymptotic lerp reads frame timing rather than the rig. So the cases pin the **decision**: a pan
moves where the camera is *heading* and leaves the camera alone, a snap moves both. That difference
is exactly what separates the four calls from the three, and it is what every mutant here attacks.

One live interaction the change surfaced: **the pointer re-picks on camera movement** (#471), so
the cell under a motionless cursor legitimately changes while the rig is in the air — a SPACE case
must read the cell it acted on *before* the flight, not after.

## The camera STAYS ([#520](https://github.com/Phaazoid/Godoiosis/issues/520) diff 2b slice 2, BUILT 2026-08-27)

Three findings from one play-check, two of them the same bug.

**Every pause in the game landed BEFORE its action** — `_execute_action_sequence`'s own comment said
so, and it was right when it was written. Then health readouts gained debris. `AttackAction.execute`
does await its lunge, its block, the knockback slide and the plummet — but the cube burst is thrown
by `UnitMirror`'s own per-frame HP poll (and by `unit_died` for a death, because `die()` emits and
`queue_free`s in one frame), flies on `HealthBlockDebris`'s own clock, and **nothing anywhere holds a
reference to it.** So the last counter killed someone and the pass cut away mid-explosion — the dev's
report, widened by his own ruling to *"every action action kind... even basic attacks knock away
health cubes and we want that focused too."*

**`linger_for` mirrors `hold_for` clause for clause**, with two deliberate differences.

- **It is FLAT** — no profile, no `is_ai`, not multiplied by `drama_of`. A hold is *anticipation* and
  scales with how dramatic you want the pass; a linger is matched to an ANIMATION that runs in real
  time whichever profile is live. Drama-scaling it would give the plain board none at all
  (`BOARD_DRAMA` ships at 0.0), which is the instant cut it exists to close. `linger_for` is the one
  line that would fork if the board ever wants its own pace.
- **Its volley branch has ONE rung** where the hold's has five: what makes a beat longer to *watch*
  is how much debris it threw, and only a death empties the grid. A shove's slide and a plummet are
  already awaited inside `execute`, so they are not waiting this needs to invent.

**`_beat_lingers` keys on the beat's LAST surviving member** where its three sibling schedules key on
the first. That is the whole of *one blast is one moment however many it hits*: a volley pans and
holds at its opening action, plays every member, and lingers once after the final one. Keying both
ends on `[0]` puts the pause between the first hit and the second.

**The await is REASONED, NOT PINNED, and says so at the call site.** `Pacing.beat` returns without
awaiting in a headless run — the escape that keeps every resolve-pass test off the wall clock — so
deleting the `await` leaves the whole suite green. **Measured, not assumed: 86 cases across four
suites passed with the linger computed and never awaited.** That is a property of the suite rather
than of the line, and `clear_guard_preview` three phases up already carries the same declaration for
the same reason. What *is* pinned is the table and the schedule.

### The ladder gained a floor

`HOLD_ATTACK`, and `hold_for`'s volley branch seeds from it instead of `0.0`. The dev found it as a
missing control — *"I don't see controls for holding the most common thing, a regular attack"* — and
it was worse than missing: a hit that only did damage earned `hold = 0` and took the bare base beat,
which also left every other rung a number with no zero point to be read against.

**It is not in `coda_hold`.** That answers for side-channel *verbs*, and `ActionType.ATTACK` is
deliberately its "undeclared" example (`test_an_undeclared_verb_never_shortens_the_beat`). Attack is
an entry of the panel's Actions list; in the code its numbers live in the volley branch. Different
lookups, same page.

### The Playback page, in six sections (seven since diff 2b added Camera flourish, which diff 2c then filled out)

Thirty flat rows, of which fifteen said `Hold:` and were really two different questions — six
*outcomes* of an attack, nine per-*verb* numbers — and half of which did nothing depending on a
setting the panel never mentioned. His fix, and it is the right one: *"an actions section, where
there's a dropdown with each action in it, so if we ever add more tuners per action it doesn't bloat
the page."*

**The sections cost no machinery.** `GROUP_TABS` already maps several groups onto one tab (Water does
it) and `_add_heading` already fires per group, so a section is a group name — The profile / Actions
/ Outcomes / Camera travel / The tear-out / Motion — and the only requirement is that a group's rows
stay contiguous in the table, since that order *is* the section order.

**A battle-zoom picker sits at the top and writes the real `PlayerSettings` value.** The first dev
tool to write one. It is not a knob row and cannot be: a `PlayerSettings` value has none of
`KnobSource`'s three save shapes and needs no Save, the store being its own persistence. Writing the
real setting is what stops the panel drifting from what the player gets — and it doubles as the
page's profile filter, which is what kills the born-dead slider: **you always tune the mode you are
watching**, and a row that would move nothing is not in front of you.

**A THREE-WAY PICKER since [#647](https://github.com/Phaazoid/Godoiosis/issues/647), and its labels
are the store's own** (`PlayerSettings.options_of`), never a copy typed into the panel — the settings
page projects the same list, so the two surfaces cannot disagree about what the modes are called any
more than about which one is picked. The filter asks the MODE rather than a beat: `COMBAT_ONLY` runs
the cinematic over blows and counters, so its rows are the ones worth tuning and only `OFF` puts the
plain board's numbers in front of you.

**...and the picker FOLLOWS the store, it does not merely write to it** (dev ruling, 2026-08-28:
*"if there is a setting in both dev and player controls, I don't want them to ever disagree. If one
knob is changed and the option exists elsewhere, I want that knob changed too."*). This was a live
bug, not a precaution: `_build_playback_header` ran once at build time and nothing refreshed it, so
changing the setting from the pause menu — a **second OS window**, on screen at the same time — left
the panel showing the old mode **and the wrong column of knobs**, i.e. tuning `CINEMATIC_*` rows
while the game ran `BOARD`. A poll, not a changed signal, which is the store's own doctrine
(*"callers poll it"*) and needs no new seam; `SettingsScreen` reconciles its own controls the same
way, with `set_pressed_no_signal` so the page never becomes a second writer. The general rule is
under *Where a presentation value is authored* in `presentation-effects.md`: **one value, one store,
however many surfaces show it.**

**The `zoom off` / `zoom on` pairs were never a binary.** They are one dial measured under each of
two live play modes, and showing both branches of a fork at once is what made them unreadable. The
page shows one column. The base beat is the ragged cell — zoom-off forks again on whose pass it is,
zoom-on does not — and it stays in The profile rather than Actions, per his ruling that *"a base
value all these sliders execute against shouldn't be tied to one of the actions."*

**EVERY ROW IS STILL BUILT; the filter only sets `visible`.** Load-bearing rather than lazy: the
panel laws walk the whole tree for a row per knob and never ask about visibility, so building on
demand fails them for every row not currently showing — confirmed by mutation, which reds with
*"has no row in the panel at all — the filter is not building it"*. `TileBrushTool._set_paint_mode`
is the same idiom one panel over; `GameTool` and `MoodsTool` had only ever torn down and rebuilt, so
`DevWidgets.add_knob_row` now returns the span it appended.

**A completeness law covers the surface, which neither existing law could see.** `coda_hold`'s law
proves a verb has a *number*; it cannot prove the dev can *reach* it, and ATTACK fell through exactly
that gap. So every `MAIN_ACTION_TYPES` member must now have a hold row, a linger row, and a place in
the Action picker.

Still open on #520 at the time of that slice: the impact layer (pitch driver, shake, micro-sway) and
the follows — the rest of diff 2b, landed in the next section — plus lethality-aware direction (2c).

## The camera JOLTS, SWAYS and STOOPS ([#520](https://github.com/Phaazoid/Godoiosis/issues/520) diff 2b, the impact layer, BUILT 2026-08-27)

The camera had learned where to go, which way to face, and how long to stay. This is what it does
*while it is there*: it is knocked when a blow lands, it breathes while it holds a shot, and it comes
down toward eye level for a directed blast so the fight looms instead of being read from overhead.

**The FLOURISH is a third position addend, and its separateness is the design.** `position` was
`_aim + _lift`; it is now `_aim + _lift + flourish()`. The first two are *where the camera looks*.
The third is not — it is a displacement laid over that, and two consequences fall straight out of
saying so. It is summed **after** `pan_limit`'s clamp, so a blow at the board's edge jolts exactly as
hard as one in the middle; and it is **never stashed**, so the view handed back at the end of a pass
is the one the player left rather than one caught mid-shake.

**One gate, and it already existed.** All three effects live only while `_view_borrowed` is true —
the flag `stash_view` sets on the claim edge and `restore_view`/`drop_stashed_view` clear. That flag
already answers exactly this question for all three claimants (a player pass, an AI turn, the burn
phase), and the look-dev scene never stashes so it never flourishes. A sway under the player's own
hand is motion sickness rather than mood; no second flag was needed to say so.

**The impact is read ABOVE the health bar's visibility gate, and that placement is the whole point.**
The instant a blow lands is `take_damage` inside `AttackAction.execute`, which `OrderExecutor` cannot
see — it awaits the whole action. The only thing that observes it is `UnitMirror`'s HP poll, which
computes its diff and then returns early on `previous == current or not bar.visible`. The cubes are a
*readout* and rightly go when the readout is hidden; a camera jolt is not a readout, and
`HEALTH_BARS` ships **HOVERED** — so reporting below that line would leave the default settings
with no impact in them anywhere, which is [#534](https://github.com/Phaazoid/Godoiosis/issues/534)'s
bug verbatim. Sharing one observation with the burst is also what keeps them in step: the jolt and
the cubes cannot disagree about when the hit landed.

**A death fires the down rung ALONE.** `die()` emits and `queue_free`s in one frame and the reconcile
skips a unit already queued for deletion, so the poll **never** observes a unit at 0 HP. Without a
second report on `_on_unit_died` the loudest moment in a pass would be the one with no jolt at all —
and because the poll structurally cannot see it, the two can never double-fire.

**Strongest wins, measured against what is LEFT of a jolt in flight** rather than against what it
started at — the holds' own rule (*the loudest single one wins, by value*) applied to an impulse.
Summing would make a three-victim volley hit three times as hard as a duel, the opposite of *one
blast is one moment*. The comparison reads the decaying **envelope**, not the instantaneous offset,
which crosses zero twice a cycle and would let any scratch win at a crossing.

**Both curves are pure and deterministic** — a damped `amp·e^(−t·decay)·sin(t·freq)` for the jolt,
two sines at an irrational ratio for the sway so the bob never settles into a metronome. Law #1 at
the smallest scale it can be asked: the same blow reads the same on every replay. World-Y only, no
camera basis — a vertical jolt is the GBA-era hit being mocked against, it cannot fight the XZ pan
clamp, and it needs no re-derivation when the yaw turns.

**The two split on the profile question, and NOT the same way.** A jolt is matched to the health
cubes bursting on their own real-time clock, so it is **flat** and applies with the battle zoom off
too — the linger's reasoning, not the hold's, since drama-scaling would give the plain board none at
all. A sway is anticipation, so it forks like drama and direction do, and `BOARD_SWAY` ships at 0.

**The pitch driver is `aim_along`'s twin and cost no new seam.** #586 had already made pitch a third
eased channel and `restore_view` already stashed and restored `_target_pitch_degrees` exactly as it
does yaw — so a directed shot writes one target through the door that exists, and the view return
undoes it. The stoop is **derived inside `aim_along` from the line already published**: one fact, two
channels, nothing to keep in step. It is measured from `board_pitch_degrees`, the board's authored
angle, which nothing in a pass moves — measuring from the *live* pitch creeps to full over a few
frames because the mirror re-solves every frame, and the strength knob then stops meaning anything.
That is diff 2a's mutant one axis over, and only a **partial** strength can separate the two.

**The claim edge deliberately does NOT square the tilt up.** It was in this slice for one run, on the
theory that a player parked at the shallow end leaves the stoop nowhere to go. Both halves are wrong:
the stoop is absolute off the authored angle, so where the hand left the camera cannot reach it — and
#586's rule is that a tilt survives everything but R, which `test_a_realign_keeps_the_tilt` pins over
`align_to_detent` itself. A beat with no aim line keeps whatever tilt it found, which is already
`aim_along`'s stated idiom for the yaw.

**The knockback follow was already built and had no law.** `pan_to(unit)` has closed with
`follow(unit)` since [#118](https://github.com/Phaazoid/Godoiosis/issues/118), `_process` re-reads
`follow_unit.global_position` every frame, and an attack beat's subject *is* its victim — so the
camera has ridden shoved bodies all along without anyone claiming it. Three correct pieces and no
case over the join is [#103](https://github.com/Phaazoid/Godoiosis/issues/103)'s shape exactly; it is
pinned now, at the decision (who is being followed when the pan lands) rather than by watching a body
fly, since the slide is headless-escaped like everything around it.

**The headless escape is on the CLOCK, not on the offsets.** Both curves are naturally zero at t = 0,
so a headless run leaves `position` bit-identical to one without this channel — which matters because
the rig suites assert coordinates, and #520 slice 1 already paid once for making a value easable
under tests whose names claim it lands. Headless refuses to *spend* time, exactly as `Pacing.beat`
does; a case that wants to watch a curve supplies the elapsed time itself.

Nine knob rows under a new **Camera flourish** section on the Playback page — its own group rather
than more rows under Camera travel, because that section is how long the camera takes to *get*
somewhere and this is what it does once it is there.

Spun out of #520 here: the **cliff follow**, [#602](https://github.com/Phaazoid/Godoiosis/issues/602),
because it is the one piece that is a build rather than a composition — both fall animations are
mirror-side Y offsets, so a unit's board position never descends and following one down needs a
vertical authority of its own. **BUILT 2026-08-29**; its own section at the end of this doc. Then
lethality-aware direction, which is the next section.

## The director knows the ENDING ([#520](https://github.com/Phaazoid/Godoiosis/issues/520) diff 2c, BUILT 2026-08-27)

Every `ResolvedOutcome` carries its lethality rung *before* playback starts, so the camera is not
discovering a kill as it happens — it can shoot the beat knowing how it ends. The ticket names three
gestures: *wind up, freeze mid-swing, dolly in*.

**The wind-up was already built and needed nothing.** `Pacing.hold_for` seeds at `HOLD_ATTACK` 0.25
and takes `HOLD_DOWN` 0.9 for a downed/killed/maimed beat, drama-scaled per profile — a killing blow
has held roughly three times as long as a scratch since #519. Worth stating because reading the
ticket's list literally would have built it twice.

**`Pacing.emphasis_for` is `hold_for`'s TWIN, not a rescaling of it.** That one collapses a beat's
facts to *seconds*; this collapses the same facts to a 0–1 *weight* for the camera. One number
meaning two things is the duplicate seam Law #4 refuses, and the two rankings may legitimately
disagree — a held breath earns a long pause and not much of a push-in. Same structure either way:
seeded from nothing, **loudest single rung wins by value**, so which rung outranks which is a knob
rather than a line of code. An ordinary blast earns 0 and is the baseline the rest are read against.

**Published per beat on `CameraController` beside `directed_line` and `framed_span` — a third
question, so a third field.** That one is an ANGLE, that one a FIT, this is a WEIGHT; the rig turns
it into a distance, since only the rig knows distances. Cleared on both lock edges for the reason
its neighbours are.

**Every subject-carrying beat publishes its own emphasis INCLUDING ZERO.** Absence-means-hold is
`directed_line`'s idiom and would be exactly wrong here: the camera would stay pushed in from a kill
through every quiet beat after it, and the pass would never breathe.

**The push-in is an ADDEND over the player's distance, never a `set_zoom`.** The wheel stays theirs
through a pass (#520's own ruling — reset once on the claim edge, then *"leave the wheel alone"*), so
a per-beat assign is precisely the leash that ruling refuses. It re-solves from the published weight
every frame rather than accumulating, so the mirror's poll is idempotent and a beat ending needs
nothing unwound — the same shape `aim_along` has, one axis across.

**THE FLOOR IS ON THE DOLLY'S OWN CONTRIBUTION, NEVER ON THE TOTAL, and that distinction is the
whole care in this slice.** This rig has **no zoom-in floor** by dev ruling (asked twice, *"please
remove it entirely"*) — scrolling in past the aim point takes the camera through its target to look
back, which is his call for *his hand*. A director subtracting from an already-close player inherits
that hole and flies the camera through a unit on the exact beat it most wants to be looking at one.
So the effective floor is the lower of `DOLLY_FLOOR` and where the player already is: closer than the
floor, and the push-in contributes **nothing** rather than the floor yanking them back out — which
would be the wheel floor, restored, under another name. Two cases pin the two halves separately, and
the naive version (floor the total) passes one and fails the other.

**`Pacing.hitstop` sits beside `beat()`** because it is a playback pause like any other — it just
spends its time by stopping the world. Three things are load-bearing: the unfreeze timer is created
with `ignore_time_scale`, or it would be frozen by the freeze it exists to end and hang the game;
re-entry is **counted**, so a volley killing two cannot have the first restore end the second freeze
and race; and the restore writes `1.0` literally, which is correct only while nothing else writes
`time_scale` — true today, and the comment says where to look when it stops being.

**It fires from the death path and needed no new plumbing.** A killing blow already reaches
`UnitMirror._on_unit_died` alone — the HP poll structurally never observes 0 HP — and that is already
where the death jolt fires. The freeze and the jolt are the same instant.

**It is GATED on playback owning the camera**, which the jolt did not need: the rig's flourish channel
is already dead unless the view is borrowed, but a time freeze is *global*, so ungated a `die()` from
any source — a dev-tool kill, a teardown — would stop the whole game with nobody watching a pass.

**The freeze and the death linger are additive, and that is the design.** `die()` runs synchronously
inside `take_damage`, so the freeze starts and the executor's `LINGER_DOWN` timer then begins while
frozen — and `Pacing.beat`'s timer respects time scale. It is correct because `HealthBlockDebris`
runs on `_process(delta)`: the cubes freeze with the timer and resume with it, so the linger still
covers the burst exactly. Deliberately **not** "fixed" with an ignore-time-scale linger, which would
desync the two.

**`report_impact` carries a KIND now, not an amplitude.** What the mirror observes is that a blow
landed and how final it was; what that is *worth* — a jolt, a freeze, both — belongs to the consumer.
Handing over `Pacing`'s shake numbers had the mirror knowing the camera's tuning table, and it is
what lets one observation drive two consequences.

**Declared cut: "freeze mid-swing" cannot literally exist yet.** `play_attack_lunge` completes both
halves of its tween and is *awaited* before `take_damage` runs, so the sprite is back at rest by the
instant the death signal fires — there is no swing to freeze mid-. What 2c ships is the **impact
freeze**; the anticipation freeze needs frames to freeze between, which is
[#603](https://github.com/Phaazoid/Godoiosis/issues/603).

**Superseded, not forgotten:** #520's original scope named a *keyframe/segment layer over `pose()`*.
It was never built and is not owed — the published-fact channels (`directed_line` / `framed_span` /
emphasis) are what a director turned out to need, each one fact the rig derives its own answer from,
and `pose()` stayed the authored-shot door it was.

Eight knob rows joining the Camera flourish section.

## The profile is a fact about a BEAT ([#647](https://github.com/Phaazoid/Godoiosis/issues/647), BUILT 2026-08-28)

The battle zoom gained a third setting — **off / combat only / every action** — and the third one is
what forced the shape. *"Combat only"* is the dev's own wording: *"actions where a unit is actively
dealing or taking damage."*

**Which beats count is a ruling, not a derivation** (dev, 2026-08-28). `VOLLEY` and `TURNOVER` are
combat; `MOVES`, `CODA` and `CELL_EFFECTS` are not. The turnover is the case his wording did not
settle and it lands on the combat side, because the act break where the defending line raises weapons
is punctuation *inside* a fight — dropping to plain for it cuts the exchange in half between an attack
and its counter. `CELL_EFFECTS` is the edge that could have gone the other way (a unit standing in
fire *is* taking damage) and stays plain rather than reversing a standing call: the environment pass
forks on neither profile nor faction, because the board acts there.

**`Pacing.active_profile()` is DELETED, and that is the load-bearing half.** It answered for a whole
pass, and once `COMBAT_ONLY` exists there is no such answer — a move and the volley after it run
under different profiles. Left in place it would have been a seam that quietly *mis-answers* rather
than one that fails, which is Law #4's late failure. `Pacing.profile_for(beat)` replaces it: the one
collapse from (mode, beat) to a profile, `duration_for`'s shape one question over.

**The gate lives in the SCHEDULE BUILDERS, not the executor.** `OrderExecutor` already built per-beat
dictionaries keyed on each beat's opening action, so the profile is computed there and published as
**`CameraController.beat_profile`** — the fourth field of the trio #520 established (an angle, a fit,
a weight… and now the cause). `_execute_action_sequence` needed no change at all.

**The rig has no beat in hand, which is what the published field is for.** `CameraRig3D` mirrors it
and every flourish channel scales through it. **The sway is why the field exists**: the angle and the
weight are published per beat and could in principle have been filtered at source, but a sway is a
*resting* behaviour polled every frame while the view is borrowed — nothing else about a quiet beat
would ever tell the camera to stop drifting.

**A FIFTH field joined it for the health readout (2026-08-28), and the split is the point.**
`playback_cinematic` answers *does the pass now running show a fight* — the PASS level, where the
four above are per BEAT — and it exists because **`beat_profile` structurally cannot answer "is a
zoom happening right now"**: it is held between passes on purpose, so it reads CINEMATIC for ever
after the first clash, and it drops to `BOARD` for any unframed action inside a pass. Held is right
for a value the rig SPENDS every frame and wrong for one a reader GATES on, which is why the fifth
field is a field rather than a second read of the fourth. It is cleared on both edges of
`set_playback_locked` beside the line, the span and the weight, so its lifetime is the pass's.

**The lines and weights beside it are deliberately NOT filtered.** All four `BOARD_*` values ship at
`0.0`, so a plain beat publishes its angle and its weight and they land at zero strength. That keeps
the fork in one place *and* keeps the BOARD knobs reachable — dial `BOARD_SWAY` up and a plain beat
sways, which is the *"the shape exists but is dialled out rather than absent"* rule `Pacing` already
states. Filtering the schedules instead would have made those four sliders move nothing, i.e.
manufactured the born-dead slider the Playback page's own filter exists to prevent.

**The conversion had a silent failure mode, and the fix was a rename.** `is_on` is
`bool(value_of(...))`, so a caller left behind by the boolean-to-choice change would compile and read
`COMBAT_ONLY` as full cinematic; `set_on` would write a *bool* into a choice row, which `choice_of`
reads back as `int(true)` = 1 and `load_state` re-reads the same way, so the wrong value survives a
relaunch consistently wrong. `BATTLE_ZOOM` → **`BATTLE_ZOOM_MODE`** makes every stale caller a parse
error instead — #418's own trick, which was doing that conversion's safety work without saying so.
The general guard landed with it: **the typed façades now refuse the other kind's row**, so the next
conversion does not depend on remembering the trick, and the writers refuse outright rather than
degrade (a bad read is one wrong frame; a bad write is a cfg the player carries between sessions).

## The fight TEARS OUT of the board ([#521](https://github.com/Phaazoid/Godoiosis/issues/521) slice A, BUILT 2026-08-26)

The ground a fight happens on lifts off the board into a diorama and thuds back when the pass ends.
This slice is the **seam and a static tear-out** — no rise off the top of frame, no white-out, no
one-by-one slam. What it buys is the question every later slice depends on: does the reconstruction
read right?

**One question, one answer: `BoardSpace.staged_offset(cell)`.** The dev's ruling on #410 puts it
here — *answered where `BoardSpace` is already consulted*, never in a separate diorama scene, which
would be a second answer to where a thing renders. `Vector3.ZERO` is the board, so every reader is
inert on a board that has never staged.

**It makes `BoardSpace` stateful for the first time**, and that is declared in its own header: the
file was pure arithmetic. A `Staging` class it delegated to would be two names for one fact.
`Pacing` and `PlayerSettings` are the precedent, and #449's hazard comes with it — a static outlives
a suite, hence `reset_for_test()`.

**Two mechanisms honour that one answer, and the split is forced by the engine.** A **GridMap cell
cannot be offset individually** — it is a lattice — so:

- **The ground routes to a second `GridMap`** (`$StagedBoard`), same mesh library, same `cell_size`,
  same cell coordinates, with the displacement as its **node transform**. A staged cell's column is
  written there and cleared from `$Board`, leaving the socket the exit thuds back into. Because both
  share one lattice, **the reconstruction is exact by construction** — board-relative geometry,
  horizontal and vertical, with no arithmetic to get wrong.
- **Everything else adds the offset at its own placement site** — and there are far fewer than there
  look to be. `BoardMirror.surface_point` is the one seam every prop, flame, cover cluster and state
  marker in that file is placed by; `OverlayMirror._anchor` is the one seam every marker gets its
  transform from. Units are the exception that proves why the offset is its own question:
  **`UnitMirror` places horizontally from PIXELS, not from `BoardSpace`**, so an offset hidden
  inside `surface_point` would have lifted a unit vertically and left it behind horizontally.

**A sprite's CELL is still a board fact.** `UnitMirror` reads it *before* adding the offset —
reading it off the displaced point would name a cell in the sky.

**A MAIN ACTION is what tears the board open — movement never does** (dev, on playing it:
*"there have to be main actions at play. Movement by itself doesn't do it."*). `BeatSheet.cells` is
therefore what main actions touch: an attack's origin, aim, knockback flight and terrain deposits,
plus the actor and target of every side-channel verb. Asked of `BaseAction.is_main_action()` rather
than of `SIDE_CHANNEL_ORDER` membership — the two lists agree today and nothing pins that they must.

**The GATE falls out of the SET rather than sitting beside it**: no main actions means no cells
means nothing lifts. That is one rule, not two, and it is why `_stage_the_fight` asks whether the
fight's cells are empty **before** the bystanders flag adds anything — asking after would let the
feels-test put move-only passes back in the sky, which is the exact thing it exists to be judged
against.

What this replaced was a sweep over every cast member's standing cell, and the symptom was a hole
in the board at the end of every move. It was also a Law #4 duplicate: whether a *non-fighter's*
ground comes along is the feels-test flag's question, and the cast sweep was a second answer to it.

**The tear-out waits for the walk.** An attacker's `origin_cell` is its *post-move* cell, so staging
before the move phase makes it walk toward a hole and pop into the sky on arrival. The board is
where you move; the diorama is where you fight.

**Staged on the profile too, so #521's law is a property rather than a promise** — nothing stages
under `BOARD`, and `tests/presentation/test_staging.gd` asserts zero displacement for **every
painted cell** after a plain-board pass, read off the seam directly. Since
[#647](https://github.com/Phaazoid/Godoiosis/issues/647) `_stage_the_fight` asks the **sheet** rather
than taking a profile: the tear-out is once per pass, so the question is whether this pass has a fight
in it at all — which under *combat only* is the same question as "does any beat run cinematic", and a
pass of nothing but walking stays on the board.

**The feels-test fork is one bool**, `Experiments.Flag.DIORAMA_BYSTANDERS`: off stages the cells the
fight touches, on adds the ground every other unit stands on so the diorama keeps its spatial
context. A session-scoped dev toggle — one of the two gets deleted once it has been played.

**The camera goes up with it** — built in #520 diff 2b slice 1 above, not here. Slice A shipped
without it, and the section above says why that gap was invisible from inside this one.

### ...and it TRAVELS there ([#521](https://github.com/Phaazoid/Godoiosis/issues/521) slice B, BUILT 2026-08-28)

Slice A moved the tiles instantly. Slice B gives them the journey: they leave their sockets, a
white-out covers the swap, and they slam into the diorama **one at a time in the order their owners
act** — which cost nothing to get, because `BeatSheet._gather_cells` already appends in playback
order. The ticket's "quietly foreshadowing who acts first" was a property of the set all along.

**`StagingFlight` is the schedule, and the schedule is the contract.** Pure and static — cells and
knobs in, times out. `OrderExecutor` awaits its total while the 3D host renders its progress, so the
two sides read *one artifact* rather than each deriving its own from the same knobs; that is the
difference between agreeing and agreeing until one is edited. It is also the only part a headless
test can watch, so the cases pin the schedule and the decisions and the travel is a play-check.

**Flight is an OVERLAY, never the stored state.** `stage()` still writes the landed board and the
flight is a transient delta on top of it, so a run with no driver — headless, the plain board, a bare
fixture — never populates it and reads exactly what it read before slice B existed. Every slice-A
assertion passes untouched, which is the property that had to hold. The executor ends the flight the
moment its await returns, because headless nothing ever advanced it and the fight would otherwise
play out over a board still sitting in its sockets.

**The stagger is DERIVED, not authored.** A fixed per-tile gap reads well on a four-cell skirmish and
costs seconds on a twenty-cell brawl, and this plays on *every* Execute — so the arrival is given a
window it must fit inside and the gap is whatever fits, capped so a small fight still gets a punchy
one-two-three.

**A tile in the air gets its own GridMap.** A cell is a *column*, and a node transform is the only
thing that carries a whole stack; one map is one offset, so tiles arriving at different moments
cannot share the landed lattice the way the settled ones do. `_other_map` became `_maps_besides` in
the same breath — a name that quietly stopped being true the moment a column could be in three
places, where the failure would have been a tile drawn twice.

**The version bumps on LANDINGS only.** `OverlayMirror` rebuilds every standing prop when
`staging_version` moves, so bumping per frame would rebuild the board on every frame of the
transition. Landings are discrete and travel is not — so a tile flies **bare** and is dressed the
instant it is home. Units ride, because they are per-frame reconciles and read the offset already,
and fighters arriving standing on their own ground is the shot.

**The camera's height became its own published fact.** `camera_lift()` equals the diorama at rest and
differs during exactly one window — the one that needs them apart, since the cut treatment puts the
camera over empty sky *before a single tile is there*. A third field beside the angle, the fit and
the weight; one field answering two questions is what spins a camera side-on to a walk.

**The white-out reads [#217](https://github.com/Phaazoid/Godoiosis/issues/217).** The timing is
identical either way — deliberately, since the schedule is shared with the executor — and what
changes is the **curve and the peak**: eased and muted instead of linear and white. That cap is a
`const` and not a knob, alone among this slice's feel values: a slider that could return it to full
would repeal the accessibility promise it exists to keep.

**One Experiments flag, and it gates the SHOT alone.** The travel is identical in both arms — a tile
always runs between its socket and the diorama — so `DIORAMA_CAMERA_CUTS_AHEAD` decides only where
you watch from: cut ahead to the empty sky and watch the fight assemble, or travel up with the
tear-out and watch the board come apart. Everything else is knobs, which reach both arms and every
blend between them. The cut is sanctioned rather than a violation: #520's never-teleport rule is
about the map, and the dev carved this transition out of it by name (2026-08-27).

**FOUR HELD BEATS, because the travel alone still cut straight from one thing to the next** (dev,
2026-08-28, after playing it: *"the action starts the moment all the tiles slam up, I want a pause
there too"*, and *"we love drama"*). The board **braces** intact before it comes apart; the camera
holds on **empty sky** before the first tile rises into frame; the assembled diorama **settles**
before the first blow; and it holds once more on the **aftermath** before the tiles go home. Each
dials to 0 for the hard cut back.

The empty-sky beat is a **lead on the schedule, not a wait before it** — the white-out is drawn off
that same clock, so stopping the clock would stop the flash with it. The exit asks for no lead,
because the diorama is already there and its own beat is the aftermath.

**THE TIMINGS ARE THE DEV'S, MEASURED IN PLAY, AND THEY OVERRULED THE FIRST CUT BY ROUGHLY 5x.**
Slice B shipped with values an order of magnitude smaller and a comment saying they were "budgeted
small on purpose" because this plays on every Execute. He **maxed four of the seven sliders** and
said it was still short. The reasoning was not wrong about the cost — it was wrong about what the
cost buys: this is the moment a fight becomes a set piece. Ceilings were raised to leave headroom
*above* where he landed rather than to bracket it. Measured at his settings, the non-fight
transition runs **6.9s for a two-cell skirmish and saturates at 11.9s from eight cells up** — the
derived stagger is what stops it growing past that.

**A SLIDER CAN BE PERFECTLY WIRED AND STILL BE DEAD, and this arc found its own instance.** He moved
"Camera holds with the board" from 0.15 to 0.95 and nothing happened: that knob is only read when
the camera-cuts-ahead experiment is **off**, and it defaults **on** — which his `experiments.cfg`
confirmed he had never changed. The beat he was reaching for did not exist, so it was built as its
own row (empty sky) rather than by making one knob answer two questions. **When a dev moves a
slider and reports no change, check the gate before checking the wire.**

Still open on #521: the **dust shockwave** on the exit thud — which would be the project's first
particle system — and strata on the cut edges, which is art-pass work.

## The camera RIDES A BODY DOWN ([#602](https://github.com/Phaazoid/Godoiosis/issues/602), BUILT 2026-08-29)

A unit shoved off a ledge or into a void falls, and the camera used to watch it go from the lip. The
sibling item this was spun out beside — knockback follow — cost nothing, because a shove writes the
unit's own `position` and `CameraController._process` has re-read `follow_unit.global_position` every
frame since #118. **A fall is invisible to exactly that mechanism**: both fall animations are
mirror-side Y offsets (`MovementComponent.plummet_depth`, `landing_fall_depth`), folded into the
sprite's stand height by `UnitMirror`, so the unit's board position never descends and the camera
dutifully follows a body the board thinks has already arrived.

**Two premises in the ticket were stale by the time it was built, and the shape reads differently
against the code.** The aim is *not* Y-zeroed — `battle3d._aim_over` has re-derived it from
`BoardSpace.surface_height_at` since 2026-08-23, so the aim already tracks board height; it tracks
the **surface**, which is exactly why a fall escapes it. And vertical authority no longer has to be
invented: `camera_lift()` is a driven channel since #521 slice B. The ticket's refusal to *reuse*
that lift stands and is still right — it is per-**cell** staging, a GridMap's node transform, and a
falling unit is not a cell — so this is a fourth addend beside it rather than a second tenant.

### One arithmetic, two readers

`UnitMirror.stand_height` / `fall_depth` / `cell_under` are lifted verbatim out of `_sync`. The
camera reads the same numbers the sprite is placed by, because **a second spelling of this exact
fall is what #472 was filed for** — that bug was the preview and the playback asking the same
question two ways. `fall_depth` is `stand_height` read from the other end (surface minus stand), a
subtraction rather than a fourth branch, so the two answers cannot drift.

There are **three** vertical animations, not two: beside the void plummet and the cliff drop, an
airborne shove holds a body *above* the ground it sails over. So the depth goes negative, and the
camera floors it at zero — **a declared cut**, not a guard. Riding that upward is a different effect
nobody asked for; it is one `maxf` away if anybody does.

### The channel is asymmetric, and that is the design

`CameraRig3D.recovered` is pure and static like the shake and the sway, but it is a curve over the
**gap** rather than over time. **Down lands at once** — the camera is chasing a body at nine cells a
second, and any easing at all is lag, which is the defect. **Up is eased**, on its own knob rather
than the rig's glide, because the climb back is nobody's animation but the camera's own; a slow one
is also what keeps the camera deep in the pit while the death jolt and the down-beat's linger play
out over it. Polled and re-solved every frame like the dolly, so a fall that ends — including by the
faller being freed — simply stops publishing and there is nothing to remember to undo.

**A beat at the bottom** (dev call): `plummet()` holds at full depth before the body is removed,
**inside** the flag rather than at the call site, because the depth is what the camera is riding —
clearing it first and then waiting would have the rig climbing out during the very pause the pause is
for. Void falls only; a cliff drop lands on ground and the shove carries on.

Four knobs under a new **The cliff follow** section on the Playback page. **Flat across profiles**,
on the linger's reasoning rather than the sway's: a fall is an animation running in real time
whichever profile is up, and the body leaves the frame just as thoroughly with the battle zoom off.
The dial-out is the strength row, not the profile.

### The bug the fixture found, and the law in it

**A board swap mid-fall left the rig under the new board for ever.** `frame()` calls
`drop_stashed_view()`, so `restore_view` early-returns and never runs; the drop is polled *below*
the playback gate, and a swap releases the lock — so nothing at all closed the channel. **A channel
polled below a gate needs a door on every path that ends that gate, and the ordinary release door can
early-return.** `drop_stashed_view` is that door, and it **cuts** where `restore_view` **climbs**:
two doors for two meanings — a view handed back to someone who was watching, versus a pit on a board
that no longer exists.

It was found by `SharedBoard`'s leak fingerprint, not by reasoning: every fall case leaked the same
three cells into the next one. That is the fixture doing the job it was built for — a diff the reset
door cannot reach is a channel with no reset door.

## #44 board-side items (cross-referenced, not in this doc's running order)

Flash-not-glow unit highlights; counter-hover -> show countering enemy's attack range;
enemy attack-range on hover during player turn; real Will bars on panels (HP over a unit's head
landed as #229 above; the PANEL half and Will are both still open); squad-target
cursor color-coding; simultaneous-movement legibility (needs design first — the umbrella's core
problem).

**Dropped 2026-08-21 (dev), not deferred — deleted from the umbrella rather than left to rot:**
*muted squad icons when another squad is active* (the mute motif above stands; this particular
application does not), *fade queued move arrows and restore on hover* (the move to 3D made it
unnecessary), and *downed units respond to no sprite effect* (since #222/#232/#321 the mirror
copies `modulate` and `animation_offset` off the hidden 2D node ungated by lifecycle, so highlight,
flash and pulse already reach a downed unit in the boot view).

**A unit IN CRISIS must read as unmistakable at board glance (dev, 2026-08-09 — filed with
[#158](https://github.com/Phaazoid/Godoiosis/issues/158)'s ability re-homing):** the skull in the
hover states-row is the only marker today, and a battle-long no-safety-net state deserves more —
**the map sprite itself should reflect Crisis** (art-gated; needs a sprite/tint/overlay treatment
per unit or a generic one). "It should be very obvious a unit is in crisis mode." Scoped as the
third consumer of [#358](https://github.com/Phaazoid/Godoiosis/issues/358)'s effect stack.

*Authored by Claude (Opus 4.8) at @Phaazoid's direction, 2026-06-26.*
