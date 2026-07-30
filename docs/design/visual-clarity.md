# Visual Clarity — working guidelines

Home for the board-legibility & action-queue readability pass. Umbrella issues:
[#44 Visual Clarity Overhaul](https://github.com/Phaazoid/Godoiosis/issues/44) (board side) and
its child [#49 Action Queue UX](https://github.com/Phaazoid/Godoiosis/issues/49) (the queue widget).

This is a *guidelines* doc, not a spec — it captures the principles we're holding the work to,
plus the running order of the queue-UX checklist. Update it as items land.

**Canon checked through #120 (2026-07-29).**

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
   - **BREAK banner** (full-screen flash, 2026-07-05) = "the plan diverged — the resolver re-entered"
     (resolution-pipeline R9). Fires on every BREAK, *both sides* — your trap shattering the enemy's
     turn earns the same moment. Reserved exclusively for R9 BREAKs; never reuse it for mere emphasis,
     or the signal dies.
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

1. **Popup line width — DONE 2026-07-29.** Long tooltips ran off the right edge of the screen and became unreadable (found by feel-test on a new ability description). Godot's built-in tooltip is a `Label` with autowrap **off**, and autowrap is a property rather than a theme item, so there is no global switch — every tooltip in `Classes/ui/` now routes through `UiText.wrap()` (`TOOLTIP_WIDTH`, playtest-tunable). Pinned by `tests/law/test_tooltip_wrapping.gd`, a **source-level** law: this layer has zero runtime coverage (#114), so a forgotten wrap is invisible to every other test. Known trade-off: a single word longer than the width overflows its line rather than breaking mid-word.
2. **A rune has no meaningful inventory tooltip.** `inventory_panel._tooltip_for` has a `WeaponInstance` branch and an `ArmorData` branch; a `RuneData` falls through to the generic case and shows only its name plus flavour text. None of what a decision actually turns on is visible: **temper element, inscribed carvings, used/remaining capacity**. `RuneData` already exposes all of it (`temper`, `inscriptions`, `capacity()`, `used_capacity()`, `remaining_capacity()`), so this is a readout, not new machinery.
3. **The Transmutation submenu should read as a catalogue, not just a picker** ([#88](https://github.com/Phaazoid/Godoiosis/issues/88)). Two parts, both dev-requested at build time:
   - **Hover descriptions per carving** — the menu lists carving names with no indication of what any of them does.
   - **Show un-channelable carvings, blotted out.** Today the category lists only what the wielder can currently afford, because `RuneData.choice_attacks` routes through the aura-filtered `channelable()`. A carving you own but can't pay for is therefore *absent* rather than greyed — the opposite of the law `_attack_entry` applies to weapons, where an unfireable pick stays **listed but disabled** (#73/#84). Closing it means the menu reading `inscriptions` (everything inscribed) and asking channelability per entry, rather than being handed a pre-filtered list.
   - This is also **why the category opens for a single carving** rather than requiring two: with descriptions and blotted-out entries it is informative even when it offers no alternative choice. Recorded because the ≥1 gate looks redundant against Attack until you know it's coming.

## Reading a turn: pacing and history (added 2026-07-29)

From the scratchpad, @Phaazoid's note about AI turns being unreadable. One observation, two issues,
because they solve different halves: **pacing** helps you read a turn *as it happens*, a **log** lets
you read it *afterwards*. Both are #44 children.

- **[#118](https://github.com/Phaazoid/Godoiosis/issues/118) — a beat between actions.**
  `OrderExecutor._execute_action_sequence` advances the instant an action reports
  `execution_complete`, so an AI squad's whole plan resolves at animation speed with nothing to
  separate one hit from the next. Cheap and needs no design; the one real constraint is that the
  suite awaits this same path, so the pause has to be a tunable a test can zero rather than a literal
  at the await site.
- **[#119](https://github.com/Phaazoid/Godoiosis/issues/119) — a reviewable battle log.** Nothing
  like it exists yet. The principle this doc contributes: **share the widget, never the data
  source.** The queue is a *live derived preview* rebuilt from the plan on every change
  (`ActionQueueDisplayEntry.build_for`), while a log is a *frozen record of what executed*, whose
  inputs are gone by the time it's read. Rendering log rows through `ActionQueueRow` is right and
  cheap; handing the log a squad and a plan and calling `build_for` is Law #4 with the sign flipped —
  one code path answering both "what will happen" and "what did happen".

  Two things a log must show that **no queue row ever did**: post-**BREAK** reality (R9 is the one
  place execution legitimately diverges from the preview — the banner tells you it happened, a log is
  where you'd learn what changed), and every event that isn't a player order at all — end-of-phase
  burn damage, Crisis outcomes, expiring downed clocks, squad ejections, terrain deposits. Those are
  precisely the events players miss, and they are invisible to the queue by construction.

## #44 board-side items (cross-referenced, not in this doc's running order)

Flash-not-glow unit highlights; counter-hover -> show countering enemy's attack range;
enemy attack-range on hover during player turn; real HP/Will bars on panels; squad-target
cursor color-coding; muted squad icons when another squad is active; simultaneous-movement
legibility (needs design first — the umbrella's core problem).

*Authored by Claude (Opus 4.8) at @Phaazoid's direction, 2026-06-26.*
