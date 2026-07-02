# Transmutation Model — Proposal for Co-Dev Review

> **Status: PROVISIONAL.** Worked out in a design grill on 2026-06-30. **Nothing here is locked** — it's a coherent direction to react to before we commit anything. Feeds the #30 alchemy design session and the future **#51 (in-editor transmutation creation)**.

## The pitch, in one paragraph

A **transmutation** is an inscribed alchemy circle — the thing a rune actually fires. We want players to **build and customize their own** (that's #51). This model treats a transmutation like a real alchemy/spell circle (à la *Full Metal Alchemist*'s arrays or *Witch Hat Atelier*'s spell circles): an **elemental core** that sets the raw power, surrounded by **shaping marks** that direct it. The big idea: it reduces the *entire* elemental system — including exotic stuff like ice, lightning, and acid — down to **5 base elements + a small lexicon of modifiers**. That's what makes player-creation both authorable and self-balancing.

## Anatomy of a transmutation (three parts)

1. **Sigils — the elemental core.** The element symbols you inscribe, and how many of each (e.g. "two Air, one Fire"). Only **5 elements** exist as Sigils: **Fire, Water, Air, Earth, Aether.** These are the "matter."
2. **Flourishes — the shaping marks.** Adjective/operation modifiers carved around the core that *direct and transform* the power: Push, Spread, Focus, Stillness, Quickening… "the lines in between." *(Name not final.)*

## What we're leaning toward (provisional decisions)

**1. A transmutation is a *weighted* handful of element Sigils — not just "which elements."**
- "2 Fire, 1 Earth" differs from "1 Fire, 2 Earth." Count = weight.
- Sigils do **four jobs at once**:
  - **Cost** — each Sigil takes up room on the rune (rune size = how many it holds).
  - **Power** — more Sigils = more raw power, scaled off your trained *aura* in those elements.
  - **Slots** — Sigil count sets how many Flourishes fit (rough idea: 1 Sigil → 1 Flourish, 2 → 3, 3 → 5).
  - **Identity** — the elements decide what the hit *does* (burns, freezes, roots…) and which combos it triggers.

**2. Two budgets, kept separate.**
- Sigils cost **rune capacity** (the physical size limit).
- Sigils grant **Flourish slots** (how many shaping marks you may add).
- Flourishes themselves cost **no** capacity — they're limited only by slots.

**3. Flourishes never add power — they only reshape it ("equivalent exchange").**
- A Flourish is always a give/take: more area for less punch; more range for less area; a knockback for less damage.
- Opposite Flourishes **cancel** (a "spread" and a "focus" on the same circle = no net change).
- This is the guardrail that stops player-made transmutations from breaking: you can *sculpt* the power, never *inflate* it.

**4. The exotic elements are DERIVED, not their own thing.**
- Only the 5 base elements have aura / are Sigils. **Ice, Lightning, Steam, Acid, etc. get no Sigil of their own** — they fall out of a base element + a Flourish:
  - **Water + Stillness → Ice**
  - **Fire + Quickening → Lightning / Shock**
  - **Earth + Water + Corrode → Vitriol (acid)**
  - **Fire + Earth → Magma**
- This is *literally* how historical alchemy is structured: the **classical elements are the matter**, the **Tria Prima (Sulfur, Mercury, Salt) and the alchemical operations are the modifiers**, and everything else is a *product*. Sulfur = ignite, Mercury = quicken/flow, Salt = still/fix. The "stillness vs excitement" polarity is the classic **Solve et Coagula** (dissolve vs fix).

**5. Flourishes are element-aware.**
- One Flourish, different result per element. A **Push** Flourish: strong with Air & Earth, weak with Water, does nothing with Fire. If a Flourish has no valid result on an element, you simply can't add it there — that's also the editor's validation rule.

**6. The element *ratio* matters in kind, not just in damage.**
- **2 Fire / 1 Earth** = "a fire attack with an earthen accent" (burns primarily; minor crush/root).
- **1 Fire / 2 Earth** = "an earth attack that singes" (roots/walls primarily; minor burn).
- The higher-weight element is the "primary" that sets the headline effect; the lesser ones are accents.

**7. Everything stays deterministic and fully previewable.**
- No randomness (our core law). The exotic space is a **fixed lookup table** — (element × Flourish) → a known result — not unpredictable chemistry. Big, but finite and authorable.

## Worked example — building a fire transmutation

- **Ember** — 1 Fire Sigil. Fits a Small rune. 1 Flourish slot. Modest fire damage; sets things alight.
- **Fireball** — 2 Fire Sigils (needs a bigger rune, scales harder off fire aura, now ~3 Flourish slots). Add a **Focus** Flourish → concentrated, punchy single hit.
- **Burning Field** — the *same* 2 Fire Sigils, but a **Spread** Flourish instead → trades punch for area; lights up a zone of tiles.
- **Storm bolt** — 2 Air, 1 Fire + a **Quickening** Flourish → resolves to a Shock/lightning effect (derived; no "lightning element" needed).

Same handful of building blocks, wildly different tools — and a player could assemble any of them.

## What this unlocks: #51 (player-made transmutations)

Because a transmutation is just *Sigils + Flourishes within a size budget*, the in-editor creation system becomes tractable and self-balancing: pick your elements, spend your slots on Flourishes, and rune size caps the whole thing. The scratchpad's balance axes (range, power, elements & weights, map/unit/both, effects) all resolve into either a Sigil or a Flourish.

## Open questions for you (the co-dev)

1. **Does "derive everything from 5 elements" feel right?** It's elegant and lore-perfect, but it's the biggest call here — it means ice/lightning/acid/etc. are *recipes*, not elements.
2. **The "Enclosure" (outer circle) — what should it actually do?** Completion gate? Sets single-target vs AoE vs self-buff? Pure flavor?
3. **Flourish lexicon scope** — strictly the classical axes (Solve/Coagula, the Tria Prima), or that *plus* looser utility Flourishes (Push/Pull, Spread/Focus)?
4. **Naming** — "Sigil" for the element core is liked. The shaping marks need a name: candidates **Inflection, Ligature, Trace, Stroke, Flourish, Filigree**.
5. **All numbers are placeholder** — capacity costs, the Sigil→slot formula, Flourish magnitudes.

## Where this sits with existing design

- The 5 base elements + the rune/aura/capacity stack are already **locked** in [alchemy-kit.md](alchemy-kit.md) — this proposal is the *transmutation-internals* layer that doc left open.
- The combinatrix (states + reactions) in [elemental-system.md](elemental-system.md) / [elemental-interactions.md](elemental-interactions.md) **doesn't change** — this just defines where an attack's element tags come from. The huge element/state/reaction idea-bank becomes the **result table** for (Sigil × Flourish).
