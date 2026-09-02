# Camera language — the words, and what owns them

**Status: canon reference, [#671](https://github.com/Phaazoid/Godoiosis/issues/671).** This page
NAMES things and POINTS at the code that owns them. It deliberately does not re-tell how any of it
came to be — [`visual-clarity.md`](visual-clarity.md) holds the round-by-round history in eleven
camera sections, and a second telling here would drift from the first.

**Canon checked through #699 (2026-09-02).**

## Why this page exists

Vocabulary drift cost real rounds in the [#602](https://github.com/Phaazoid/Godoiosis/issues/602)
arc, and every instance looked harmless in the moment:

- **"Zoom"** meant the player's wheel in one dev ruling and the director's dolly in the code that
  read it. Scoping *"no zoom-in floor"* to the right one took a round.
- **"The camera looks at it"** turned out to mean the frame's bottom EDGE descending onto a
  stationary object — not the aim travelling toward it.
- **"In picture"** was not answerable at all until LIVE vs SETTLED existed.

Shared words make a bug report and a plan land on the same referent the first time, and give a dev
ruling a cheap way to carry its scope.

**Links here name a section by TITLE rather than by anchor**, on purpose: a renamed heading breaks an
anchor silently, where a named section degrades to something you can still search for.

---

## The channels

The 3D frame is a **SUM of independent channels**, and that sentence is the whole of the #602
diagnosis — every bug in that arc was a composition bug, each channel correct and the sum wrong.
`CameraRig3D._apply_position()` is the one place the sum is written:

```gdscript
position = _aim + _lift + Vector3(0.0, -_drop, 0.0) + flourish()
```

| Channel | What it means | Owned by | Written through |
|---|---|---|---|
| **aim** | the point on the board the rig sits over | `CameraRig3D._aim` / `_target_aim` | `hold_at` (snap) · `glide_to` (pan) |
| **lift** | how far the torn-out diorama has risen under it | `_lift` / `_target_lift` | `lift_to` (eased) · `cut_lift` (lands now) |
| **drop** | how far below the board the shot has ridden a falling body | `_drop` / `_target_drop` | `drop_to` |
| **distance** | how far the camera sits back from the aim | `_camera.position.z` / `_target_distance` | `set_zoom` — the ONE distance door |
| **dolly** | the director's push-in for the beat now playing, an ADDEND on distance | `_dolly` | `dolly_to` |
| **yaw** | which way the rig faces | `rotation_degrees.y` / `_target_yaw_degrees` | `aim_along` · `align_to_detent` · orbit |
| **pitch** | the tilt | `_pitch_degrees` / `_target_pitch_degrees` | drag · `board_pitch_degrees` |
| **flourish** | the impact shake plus resting sway, a DISPLACEMENT over where the camera looks | `_shake_amplitude`, `_sway_elapsed` | `shake` |

**The live enumeration is `CameraRig3D._trace_channels()`**, not this table. It exists for
[#669](https://github.com/Phaazoid/Godoiosis/issues/669)'s camera trace, which has to name every
channel at once, so a channel added without updating this page still shows up in every filed bug
report — the staleness is visible rather than silent.

**One declared exception: the flourish is not in that snapshot, and that is correct.** The trace
carries every channel that HAS A TARGET; the flourish is the one addend without one, because a shake
is a displacement laid over where the camera looks rather than a place it is going. It is also
summed AFTER `pan_limit`'s clamp and is zero unless the view is borrowed.

> **`flourish` means two unrelated things in this codebase.** `CameraRig3D.flourish()` is the camera
> addend above. `class_name Flourish` (`Classes/alchemy/Flourish.gd`) is a shaping mark carved around
> a transmutation's sigil core. Nothing connects them; say "the camera flourish" when it could be
> either.

---

## LIVE vs SETTLED

`CameraRig3D.When { LIVE, SETTLED }` — a real enum since
[#670](https://github.com/Phaazoid/Godoiosis/issues/670), not just a distinction in prose.

- **LIVE** — the channels as they are this instant.
- **SETTLED** — the channels as they will be once every ease ARRIVES, i.e. off the targets. This is
  the **deepest the frame can get**: the eases only approach their targets and the dolly only moves
  the camera closer, which is shallower.

The consequence, and the reason the axis exists: **an anchor measured off LIVE can be descended onto
by a channel still settling** — a body can die mid-ease. `frame_floor(when)` is the query.

*The full argument is in `visual-clarity.md` → "Where the frame's edge is — one answer with a WHEN"
and "The camera RIDES A BODY DOWN".*

---

## The shot words

**These describe what the code does TODAY.**
[#672](https://github.com/Phaazoid/Godoiosis/issues/672) will make *shot*, *hold* and *cut* into real
constructs with a priority table; until it lands, they are descriptive words for shapes that already
exist implicitly. Nothing here should be read as committing #672 to a design.

### How a channel moves

- **ease** — the channel closes on its target over time, in `_process`. The default for aim, lift,
  drop, distance, yaw and pitch.
- **cut** — the channel lands on its target NOW. Only one exists: `cut_lift()`, used while a
  transition declares its drive a cut, because the flash is at full white for exactly that frame.
- **snap** — set live and target together at once, without easing: `hold_at()`. Distinct from a cut
  in that nothing was mid-ease to interrupt.
- **hold** — a channel deliberately kept where it is while something else finishes. The one shipped
  hold POLICY is the death show outranking the trained release (see below).

### The implicit shots

Each is a named framing the code already produces, with no `Shot` object behind it:

| Shot | What sets it |
|---|---|
| the **opening pose** | `battle3d.fit_camera()` — an authored `CameraPose`, else a solved fit |
| the **playback wide** | `CameraRig3D.playback_distance` (an `@export`, tunable on the Game tab) |
| the **trained follow** | `Pacing.TRAINED_DISTANCE`, while the 2D camera is following one unit |
| the **staging transition** | `BoardSpace.camera_lift()`, the diorama tearing out |
| the **death show** | `UnitMirror.death_show_live()` holding the trained frame until the last cube lands |
| the **board-home teardown** | `restore_view()` — the climb out and the pan back |

Note the two distances live in **different homes on purpose**: `playback_distance` is a rig `@export`
the dev tunes, `TRAINED_DISTANCE` is a `Pacing` constant. Both are content, neither is a magic number.

### Frame words

- **frame edge** — where the frustum's boundary lands in the world. Only the BOTTOM edge is
  implemented (`frame_floor`), because it is the only one anything has needed.
- **anchor** — a world point deliberately placed relative to a frame edge, so it is on or off camera
  by construction. The one anchor is `battle3d._shot_floor()`, which puts a void death's burst
  `PLUMMET_BURST_UNDER` below the SETTLED floor so the cubes assemble off-screen and erupt upward.
- **on / off picture** — whether a point is inside the frustum. See *Don't re-derive these*.

### Two words that caused rounds

- **zoom** is the PLAYER'S WHEEL, never the director's push-in. The push-in is the **dolly**. The
  ruling *"this rig has no zoom-in floor"* is about the wheel and keeps that scope; the dolly has a
  floor on its own contribution.
- **"looks at"** — when the dev says the camera must never look at where the death bar forms, that is
  about the frame's bottom EDGE descending onto it, not about the aim travelling toward it. The aim
  can be nowhere near a thing that is nonetheless in shot.

---

## The grain: five doors

The [#176](https://github.com/Phaazoid/Godoiosis/issues/176) authority split is *the 2D game
publishes CAUSES, the 3D rig owns the SHOT*. The useful form of that is the list of who may move the
camera, and on what occasion — because an ungated mover is the bug class the whole #602 arc was:

| Door | Occasion | Writes |
|---|---|---|
| `battle3d._mirror_camera()` | every frame under playback, polling `cam.*` causes | `hold_at`, `drop_to`, `lift_to`, `set_zoom`, `aim_along`, `dolly_to` |
| `battle3d._on_impact()` | a blow lands — an EVENT | `shake` |
| `battle3d._center_rig_on()` | recentre / the return pan — an EVENT | `glide_to` |
| `battle3d.fit_camera()` | a board loads | `frame` / `pose` |
| `CameraRig3D._unhandled_input` / `_process` | the player's own hand | orbit, tilt, wheel, WASD |

The **causes** the 2D `CameraController` publishes: `shot_cells`, `follow_unit`, `directed_line`,
`beat_emphasis`, `beat_profile`, plus its own position. **One fact travels the other way** —
`CameraController.fall_depth`, the rig telling playback how far under the board it has got, so the
teardown can wait for the climb.

#672's priority table is the formalization of this table. Until then, adding a sixth door is a
decision worth stating out loud.

---

## Don't re-derive these

Both found by measuring during #670, and both are things a camera feature is tempted to rebuild:

- **"Is this point on camera?" already has an exact answer for the LIVE pose** —
  `Camera3D.is_position_in_frustum()` (verified present in 4.7.1). What the engine structurally
  CANNOT answer is the SETTLED question, since it only sees where the camera is, not where its
  channels are heading. So only the settled half was ever missing, and that is the half round 8
  needed.
- **`widen_to_fit` / `_fit_distance` is a DIFFERENT question, not a frame-edge read.** It calls
  `_aim_at(box)` and **re-aims**, answering *how far back must I sit to contain this box if I look at
  it*, in camera space, across all four edges. `frame_drop` answers *how far below the aim does the
  bottom edge fall*, in world-vertical. Shared trigonometry, different questions — folding them would
  force two questions into one seam.

---

## Related

- [`visual-clarity.md`](visual-clarity.md) — the camera's build history, eleven sections from #520
  through #670. Every "why is it like that" lives there.
- [`presentation-effects.md`](presentation-effects.md) — the HD-2D idea wall, and *Where a
  presentation value is authored* (which table a camera knob belongs in).
- [`verticality.md`](verticality.md) — heights, the sight line, and what a fall costs.
