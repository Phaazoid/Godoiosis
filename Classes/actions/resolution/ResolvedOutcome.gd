extends RefCounted
class_name ResolvedOutcome

# One action's resolved consequences — the single source of truth for its damage (R8).
# Every stage annotates this same object: base damage -> elemental (-> Will, Phase 3).

var base_damage: int = 0
var damage: int = 0                              # final, post-elemental
var heal_amount: int = 0                          # final HP restored this hit (0 for a damage attack)
var states_added: Array[Elemental.State] = []
var states_removed: Array[Elemental.State] = []
# Authored duration overrides for states_added entries (max across fired reactions). Absent = the
# state's default clock (Elemental.STATE_DEFAULT_TURNS); only meaningful for paired states.
var state_turns: Dictionary[Elemental.State, int] = {}
var popups: Array[String] = []
var reaction_icons: Array[Texture2D] = []        # icons of reactions that FIRED this hit — drawn behind the target in the queue
var target_hp_after: int = 0                     # threaded hypothetical HP after this hit (R4)
var knockback_applied: bool = false               # #84: this hit shoved the target (Kinetic Mace Blowback)
var knockback_from: Vector2i = Vector2i.ZERO       # the cell it was standing on BEFORE this shove
var knockback_to: Vector2i = Vector2i.ZERO         # the cell it lands in — previewed and applied verbatim (Law #2)
# Every cell of the shove, start included — the flight plus any landing tumble (#259). The TRAIL's
# one source: a tumble down a sideways ramp bends the path once, so the endpoints above cannot
# describe it (from/to stay authoritative for the projection and execute's set_cell).
var knockback_path: Array[Vector2i] = []
# Where horizontal FLIGHT ends, as an index into knockback_path: the cell any vertical drop (or
# void removal) happens on; cells after it are the landing tumble. The resolver's own split — the
# shove animation and the 3D trail read it here rather than re-deriving (Law #2).
var knockback_landing_index: int = 0
var fall_damage: int = 0    # the drop's own component (#259), already folded into `damage` above
var fall_levels: int = 0    # how far the unit actually FELL (#259 follow-up): the flight drop plus
							# any tumble-then-plummet. The distance fall_damage is derived from and
							# the "Fell N!" popup names -- a rules fact, not a render one. The 3D
							# drop pointer deliberately does NOT read it (#431): it measures the
							# trail's own surfaces, which is the only form that can see the SECOND
							# drop a plummet adds.
# Shoved into a VOID (#259) — gone outright, the #116 kill doctrine. lethality reads KILLED so
# every reader (AI removal tiers, the KILL icon, lifecycle_for → DEAD) lights up; this flag exists
# because execution needs its own door — a 0-damage take_damage cannot kill an ACTIVE unit, so
# both executors call Unit.die() on it. Preview-side it also suppresses the landing ghost and the
# projected-knockback publish (nothing stands in a hole, and nothing there may be pickable).
var removed: bool = false
# Both ends are recorded because a unit can be shoved MORE THAN ONCE in a plan (#105): the second
# hit starts where the first one left it, not at its live board cell. The preview used to
# reconstruct the start from `target.movement.cell`, which is a second answer to a question this
# outcome already holds — and which produced a two-tile "direction" the arrow atlas can't name.

# Predicted lifecycle result for this hit's TARGET (R8's "lifecycle result"). Mirrors
# Unit.take_damage + _go_downed so the queue previews down/maim/kill (Law #2). MAIMED is a
# DOWN the target can't pay for in Will (will-and-death.md 2026-06-24) — same lifecycle as
# DOWNED, flagged separately so the preview can say so.
enum Lethality { NONE, DOWNED, KILLED, MAIMED, CRISIS }
var lethality: Lethality = Lethality.NONE

var skipped: bool = false                        # counter-er downed/killed earlier in the pass (R7) — no-op: don't play or preview

var hp_before: int = 0   # target's HP going into this hit; recorded by the resolver, not derived

# Target height minus attacker height at resolve time (#258) — the wire a future height-damage rule
# attaches to; no behaviour reads it in v1 beyond the queue row's uphill/downhill token. FROZEN like
# fired_attack: stamped from origin_cell + the threaded hypo position, never re-derived later, since
# a shove earlier in the pass can change the target's level (Law #2). 0 with no board.
var elevation_delta: int = 0
