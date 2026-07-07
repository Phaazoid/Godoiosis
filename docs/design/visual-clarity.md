# Visual Clarity — working guidelines

Home for the board-legibility & action-queue readability pass. Umbrella issues:
[#44 Visual Clarity Overhaul](https://github.com/Phaazoid/Godoiosis/issues/44) (board side) and
its child [#49 Action Queue UX](https://github.com/Phaazoid/Godoiosis/issues/49) (the queue widget).

This is a *guidelines* doc, not a spec — it captures the principles we're holding the work to,
plus the running order of the queue-UX checklist. Update it as items land.

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

## #49 Action Queue UX — checklist & order

Running order (cheapest / highest-clarity-per-effort first):

1. **More info per row — damage + target HP before -> after.** *(starting here)*
   `ResolvedOutcome.target_hp_after` is already threaded; `before = after + damage` (attacks only
   change HP, so the identity holds). Lives in `AttackAction.get_outcome_summary()`.
2. **Counters render after all attacks.** **DONE** — `SquadManager.get_display_entries_for_squad`
   builds COUNTER as its own section, last, with skipped counters hidden.
3. **Group a volley into one expandable row.** Members share the `volley` array, so the set is
   identifiable. Collapse N derived rows to one summary row that expands on click.
4. **Outer scrollbox for the whole queue.** Each section already scrolls internally
   (`SECTION_MAX_HEIGHT`); the *list of sections* now needs its own scroll too.
5. **Click-drag to reorder attacks.** Combo order matters (elemental). Stays a deterministic,
   planned reorder — Law #2 intact.

## #44 board-side items (cross-referenced, not in this doc's running order)

Flash-not-glow unit highlights; counter-hover -> show countering enemy's attack range;
enemy attack-range on hover during player turn; real HP/Will bars on panels; squad-target
cursor color-coding; muted squad icons when another squad is active; simultaneous-movement
legibility (needs design first — the umbrella's core problem).

*Authored by Claude (Opus 4.8) at @Phaazoid's direction, 2026-06-26.*
