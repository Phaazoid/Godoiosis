# Camera language — the words, and what owns them

**Status: canon reference, [#671](https://github.com/Phaazoid/Godoiosis/issues/671).** This page
NAMES things and POINTS at the code that owns them. It deliberately does not re-tell how any of it
came to be — [`visual-clarity.md`](visual-clarity.md) holds the round-by-round history in eleven
camera sections, and a second telling here would drift from the first.

**Canon checked through #699 (2026-09-02); #1132 (the clearance words, then the approach and arrival, then the held angle and the settle, then readouts and bystanders) folded in 2026-10-07; #705 (the dev pause and key poses, then the Camera page) folded in 2026-10-08; #1280 (the pivot on the ground, the hand rates per screen) folded in 2026-10-09.**

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
| **aim** | the point on the board the rig sits over: the PIVOT the camera turns around and zooms toward | `CameraRig3D._aim` / `_target_aim` | `hold_at` (snap) · `glide_to` (pan) · `_reseat_pivot` (the hand's; camera unmoved) |
| **lift** | how far the torn-out diorama has risen under it | `_lift` / `_target_lift` | `lift_to` (eased) · `cut_lift` (lands now) |
| **drop** | how far below the board the shot has ridden a falling body | `_drop` / `_target_drop` | `drop_to` |
| **distance** | how far the camera sits back from the aim; after any hand gesture, the distance to the ground at the centre of the screen | `_camera.position.z` / `_target_distance` | `set_zoom` — the ONE distance door (`_reseat_pivot` relabels it, moving nothing) |
| **dolly** | the director's push-in for the beat now playing, an ADDEND on distance | `_dolly` | `dolly_to` |
| **yaw** | which way the rig faces | `rotation_degrees.y` / `_target_yaw_degrees` | `aim_along` (carrying the clearance **turn**) · `align_to_detent` · orbit |
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

**A shot is a real construct as of [#672](https://github.com/Phaazoid/Godoiosis/issues/672)** —
`ShotDirector.Shot`, a named row in a priority table, and the highest-ranked live one owns the
camera. What follows is the table plus the words for how a channel gets where the shot wants it.

### How a channel moves

- **ease** — the channel closes on its target over time, in `_process`. The default for aim, lift,
  drop, distance, yaw and pitch.
- **cut** — the channel lands on its target NOW. Only one exists: `cut_lift()`, used while a
  transition declares its drive a cut, because the flash is at full white for exactly that frame.
- **snap** — set live and target together at once, without easing: `hold_at()`. Distinct from a cut
  in that nothing was mid-ease to interrupt.
- **hold** — a framing that writes nothing, keeping the camera where the last shot left it while
  something finishes. One row has it: `DEATH_SHOW`.

### The priority table

`ShotDirector.Shot`, ascending — a higher row outranks a lower one, and the highest LIVE row owns
the camera. **The enum's order is the mechanism**, not a comment: `solve()` is a rank compare, so
moving a row changes the answer.

| Rank | Shot | Live when | Framing |
|---|---|---|---|
| 5 | `DEATH_SHOW` | a show is playing and nobody is followed | **hold** — writes no distance |
| 4 | `TRAINED` | `cam.follow_unit` is valid | `Pacing.TRAINED_DISTANCE` |
| 3 | `STAGE` | `cam.shot_cells` is non-empty | `playback_distance`, widened to hold the staged volume |
| 2 | `SPAN` | `cam.framed_span` has two cells | `playback_distance`, widened to hold the walk |
| 1 | `WIDE` | playback owns the camera | `playback_distance` |
| 0 | `NONE` | — | the gate's answer: the view is the player's, and a release restores it |

**The playback lock is the table's GATE, not a row in it.** A `LOCKED` row would be outranked from
above, so a death show still playing as the lock let go would hold the camera past the pass's end.

**What `DEATH_SHOW` outranks is the FALLBACK, not the close-up.** Its condition and TRAINED's are
mutually exclusive, so those two never compete — it stands in TRAINED's place once the body is gone,
and outranking STAGE/SPAN/WIDE is what makes the release a **deferral** rather than a skip.

Two things sit OUTSIDE the table and are not shots: the **opening pose** (`battle3d.fit_camera()`,
an authored `CameraPose` or a solved fit — a board loading, not a shot inside a pass) and the
**staging transition** (`BoardSpace.camera_lift()`, which drives the lift channel; the lift is
polled above the gate because how far the ground has been torn out is a fact about the BOARD).

Note the two distances live in **different homes on purpose**: `playback_distance` is a rig `@export`
the dev tunes, `TRAINED_DISTANCE` is a `Pacing` constant. Both are content, neither is a magic number.

### Frame words

- **frame edge** — where the frustum's boundary lands in the world. Only the BOTTOM edge is
  implemented (`frame_floor`), because it is the only one anything has needed.
- **anchor** — a world point deliberately placed relative to a frame edge, so it is on or off camera
  by construction. The one anchor is `battle3d._shot_floor()`, which puts a void death's burst
  `PLUMMET_BURST_UNDER` below the SETTLED floor so the cubes assemble off-screen and erupt upward.
- **on / off picture** — whether a point is inside the frustum. See *Don't re-derive these*.

### Clearance words ([#1132](https://github.com/Phaazoid/Godoiosis/issues/1132))

- **sight line** — a segment from the SETTLED lens (`CameraRig3D.lens_at`) to a point on the action.
  While a pan is running it is the lens over where the pan LANDS (`lens_at`'s `aim`, fed by
  `CameraController.pan_destination`), so the angle is chosen on the approach's first frame rather
  than after the camera arrives.
- **the approach** — a battle-zoom beat's pan, which IS that beat's shot: `pan_to` publishes
  `pan_subject`, and `battle3d._shot_subject` lets it stand in for the follow while the glide runs, so
  the close-up, its zoom and the clearance's angle start with the travel. Never while a death show is
  live, and never off the battle zoom.
- **arrived** — every eased channel within `CameraRig3D.ARRIVED_*` (0.1° / 0.01 units) of its
  target (`CameraRig3D.is_arriving`). At 1° the camera was still turning about 8° a second, so
  "arrived" has to mean invisible drift, not nearly there. The resting sway and the impact shake are
  addends, not channels, so they never hold an arrival open.
- **settle** — `OrderExecutor._settle_then`: after EVERY playback pan, wait for arrival and then at
  least `Pacing.CAMERA_SETTLE` (0.5s, a Game-tab knob) before anything plays. That covers each beat in
  both profiles, the walk framing, the tear-out's brace, the way home and each burn hit. The beat's
  own hold still applies when it is longer, because the settle is a floor and not an addition (dev,
  2026-10-07: *"playback should always give at least a half second for the camera to settle in a new
  position"*).
- **held angle** — the turn is chosen on the approach and NOWHERE else. Once a pan has landed,
  nothing turns the camera until the next pan; whatever then comes into the way (a lunge's peak, a
  tumble) is HIDDEN. `battle3d._clear_the_shot` passes `can_turn = cam.is_panning()`, and the
  per-frame step in `ShotClearance.step` can only hide.
- **blocker** — a terrain column, a prop or a unit a sight line passes through. A column is a box
  from the board's underside to its drawn top, never "everything below the top". A unit is its art
  AND its health readout, as two boxes (`ShotClearance.Body.blocks`), because from the battle zoom's
  pitch the readout over a head is what buries the fighter behind it (round 4).
- **the action** — never hidden, and the ground under it never hidden either. Depends on the shot:
  - On a close-up, the trained subject and both ends of the aim line. Both ends are also what the
    close-up looks AT, so an angle that parks one behind the other counts as blocked.
  - On the stage's wide shot, everyone on stage.
  - On a walk, everyone walking.

  A bystander on stage may be hidden during a close-up. The ground under it stays protected, so a
  hidden column never leaves a visible unit on air.
- **turn** — degrees added to the beat's directed yaw (`CameraRig3D.directed_yaw`) to reach a clear
  side; zero is the shot exactly as it always was.
- **hidden** — what no turn could clear, taken out of the frame outright: a column moved to the
  invisible lattice, a prop or a unit made invisible. Not a camera mover and not a sixth door --
  it moves nothing -- so its writers are `BoardMirror.set_camera_hidden` and
  `UnitMirror.camera_hidden`, both fed by `battle3d._push_hidden`.

`ShotClearance` owns the rule and the latch; the history is in `visual-clarity.md` -> *The battle
zoom sees past what stands in the way*.

### Two words that caused rounds

- **zoom** is the PLAYER'S WHEEL, never the director's push-in. The push-in is the **dolly**. The
  ruling *"this rig has no zoom-in floor"* is about the wheel and keeps that scope; the dolly has a
  floor on its own contribution. Since [#1280](https://github.com/Phaazoid/Godoiosis/issues/1280) a notch
  SCALES the distance (`zoom_step_share`), so the wheel gets as close as you like and never passes
  through the ground; `set_zoom` itself is still floorless.
- **re-seat** — the player's hand moving the aim along the view line onto the ground at the centre
  of the screen ([#1280](https://github.com/Phaazoid/Godoiosis/issues/1280)), so orbit, tilt, Q/E
  and the wheel act around what is on screen and every hand rate scales by a distance that means
  something. It fires on a gesture's START (orbit or pan press, a notch, Q/E, a WASD hold), never
  per frame, needs a host `ground_probe` (battle3d's, off `BoardPicker`), and never moves the camera:
  it is skipped past the zoom ceiling or off the pan limit. Every hand rate is per SCREEN —
  `pan_speed_screens` — #879's screens-not-cells law.
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
| `battle3d._center_rig_on()` | recentre / the return pan / an objective row's click — an EVENT | `glide_to` |
| `battle3d.fit_camera()` | a board loads | `frame` / `pose` |
| `CameraRig3D._unhandled_input` / `_process` | the player's own hand | orbit, tilt, wheel, WASD, the middle-drag pan (`hold_at`, #1037) |

The **causes** the 2D `CameraController` publishes: `shot_cells`, `follow_unit`, `directed_line`,
`beat_emphasis`, `beat_profile`, `pan_subject` and `pan_destination`, plus its own position. **Two
facts travel the other way** — `CameraController.fall_depth`, the rig telling playback how far under
the board it has got, so the teardown can wait for the climb; and `view_arriving`, the rig telling
playback it is still easing onto the shot, so every playback pan's settle waits for it (#1132 follow-up,
widened to every pan in round 3).

Adding a sixth door is a decision worth stating out loud.

**The dev pause ([#705](https://github.com/Phaazoid/Godoiosis/issues/705)) adds no door. It swaps
which of two is open.**
- **P freezes a pass.** `Pacing.set_dev_paused` is one more reason in the one time-scale writer.
- **While paused, the player's-hand door opens under playback.** `battle3d._process` enables manual and
  zoom input, and the rig eases on a capped wall clock, since game time is at zero.
- **The director's per-frame writes stand down.** `_mirror_camera` returns before them.
- **Resume is the director's own door handing back its own frame.**
  - `battle3d._sync_dev_pause` snapshots the rig at the pause (`CameraRig3D.snapshot_view`) and CUTS
    back to it at resume (`return_to_snapshot`). A cut, because nothing may move while anything plays.
  - It does this only while playback still owns the camera. A pause ended by a board swap has no
    director to return to.
  - Deliberately not `stash_view`: that slot is the PLAYER's view, which the pass's release flies back
    to.

**Key pose words (#705 slice 2):**
- **key pose / keyframe** — N while paused. The camera as the dev framed it ("yours"), beside the
  director's held frame ("director"), plus:
  - the **pass time**: scaled seconds since playback claimed the camera, so it stands still across
    the pause;
  - the shot, who it is trained on, and the aim line.

  `CameraRecording` holds them, capped at 12. Shift+N clears, and so does a board swap.
- **The recording in a report** — a `## Camera recording` section (a table, then the same numbers as
  JSON to replay) and `camera.png`, a contact sheet of the screenshots, K1 first, three across. Both
  come only when there are key poses.

**The Camera page (#705 slice 3)** — Session → Camera in the dev window, the words above made live.
- **The shot table** lights each row by `ShotDirector.liveness`, the per-row clauses `solve()` ranks
  over, and marks the active shot. One set of clauses, so the page cannot disagree with the camera.
- **The View line and the trace** are read through the sources BugReporter reads, so the page says
  what a report filed that moment would say.
- **The recording** lists the key poses. **Jump to** is not a sixth door: it works only while paused,
  when the camera is already the dev's, and it cuts through the same `return_to_snapshot` resume uses.
  **Delete** renumbers the rest, so a K number stays its slot on the contact sheet.

**The recentre door has no lock of its own**, and that is why a new caller is not a new door. SPACE
and an order's return pan cannot fire while playback owns the board, so the door never needed one.
Clicking a zone row in the objectives panel ([#955](https://github.com/Phaazoid/Godoiosis/issues/955)
part 3, `game.look_at_next_zone` → `focus_view_on_cell`) CAN fire then, since that panel stays up
through enemy turns, the pass and the mission's end, so it asks `_board_locked_for_player()` itself
before it glides. A caller that can fire while the board is locked asks first.

**#672 narrowed the FIRST door rather than adding one.** `_mirror_camera` still polls every frame,
but every distance and framing it writes now goes through `battle3d._apply_shot`, one `match` with
one arm per row of the priority table above — so a new framing rule has nowhere to go except that
table, because there is no second line to add code to. That is the same guarantee `_apply_position`
gives `position`, and it is what the ungated-mover bug class of the #602 arc was missing. The other
four doors are unchanged, and the flourish is still declared outside the shot entirely.

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
