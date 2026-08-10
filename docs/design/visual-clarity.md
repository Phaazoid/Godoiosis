# Visual Clarity — working guidelines

Home for the board-legibility & action-queue readability pass. Umbrella issues:
[#44 Visual Clarity Overhaul](https://github.com/Phaazoid/Godoiosis/issues/44) (board side) and
its child [#49 Action Queue UX](https://github.com/Phaazoid/Godoiosis/issues/49) (the queue widget).

This is a *guidelines* doc, not a spec — it captures the principles we're holding the work to,
plus the running order of the queue-UX checklist. Update it as items land.

**Canon checked through #172 (2026-08-10).**

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

## #44 board-side items (cross-referenced, not in this doc's running order)

Flash-not-glow unit highlights; counter-hover -> show countering enemy's attack range;
enemy attack-range on hover during player turn; real HP/Will bars on panels; squad-target
cursor color-coding; muted squad icons when another squad is active; simultaneous-movement
legibility (needs design first — the umbrella's core problem).

**A unit IN CRISIS must read as unmistakable at board glance (dev, 2026-08-09 — filed with
[#158](https://github.com/Phaazoid/Godoiosis/issues/158)'s ability re-homing):** the skull in the
hover states-row is the only marker today, and a battle-long no-safety-net state deserves more —
**the map sprite itself should reflect Crisis** (art-gated; needs a sprite/tint/overlay treatment
per unit or a generic one). "It should be very obvious a unit is in crisis mode."

*Authored by Claude (Opus 4.8) at @Phaazoid's direction, 2026-06-26.*
