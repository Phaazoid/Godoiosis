extends Resource
class_name ScenarioData

# The saved board: terrain, units, squads, whose turn it is, who the computer plays, and the
# mission layer (objectives + zones + progress). There is ONE board resource -- a "mission" is
# just one of these saved under Scenarios/missions/ (missions.md). ScenarioManager's
# capture_scenario/apply_scenario are its writer and reader; ScenarioUnitEntry is the per-unit half.

@export var scenario_name := ""
@export var unit_entries: Array[ScenarioUnitEntry] = []
@export var tile_data: PackedByteArray
@export var terrain_states: Dictionary = {}   # Vector2i -> Array[Terrain.TileState] deposited at runtime
@export var corner_heights: Dictionary = {}   # Vector2i -> Vector4i(NW,NE,SE,SW) in half-level units
											  # (#427). SPARSE: an absent cell is flat at 0, so a flat
											  # board saves as {}. BoardHeights owns that default and is
											  # the only reader — see verticality.md. One field, not two:
											  # a ramp at height 0 has non-zero corners, so it survives
											  # the round trip on its own.

# DEPRECATED (#427), and NEVER read as data: a board saved before corner heights carries these and no
# `corner_heights`. Godot ignores properties a resource no longer declares, so without them such a
# board would load perfectly FLAT with no error at all. They exist to make that detectable — see
# predates_corner_heights below. Delete once no stale user:// saves remain.
@export var elevations: Dictionary = {}
@export var ramp_rises: Dictionary = {}
@export var active_faction: Team.Faction = Team.Faction.PLAYER # whose turn it was when saved
@export var zones: Dictionary = {}   # zone name -> {"kind": ZoneManager.Kind, "cells": Array[Vector2i]},
									 # painted via Tile Brush's Zone mode. Straight pass-through of
									 # ZoneManager.to_dict()/load_dict() — this is WHERE an objective
									 # happens; `objectives` below is WHAT the mission requires, and
									 # that one is authoritative (missions.md; MissionController
									 # reads an unpainted declared objective as PENDING, never NONE).
@export var objectives: Array[MissionRules.Objective] = []   # empty = plain rout map

# What LOSES this mission, beyond the #96 floor of the last unit falling (#101). Its own list
# rather than negated objectives: the two are checked at different moments, and a failure has to
# name a reason for the banner. Empty = only the floor. Composes by ANY.
@export var lose_conditions: Array[MissionRules.LoseCondition] = []
# How many rounds ROUND_LIMIT allows. 0 = no limit, and that sentinel IS this field's own default,
# so a board that never authored a clock cannot read as one that authored a zero-round one.
@export var round_limit := 0

# Which LookPreset this board wears (#253 part 2). A NAME, never a LookPreset reference, for two
# load-bearing reasons: a dangling ext_resource can fail the WHOLE scenario load rather than
# degrade, so "the preset was deleted -> fall back to the default" is only implementable soft; and
# a Resource field risks EMBEDDING the preset into the scenario on save, the trap #177 hit with
# unit_data. Empty = the default look. Resolved by LookKnobs.resolve, applied by battle3d.
@export var look_preset := ""

# Which Roster this mission offers (#735) -- who the player may bring into it, and the loose gear
# they may bring. A NAME resolved against RosterCatalog.ROSTER_DIR, never a Roster reference, for
# the two reasons stated for look_preset directly above; the filename IS a roster's identity, so
# there is no display_name to disagree with it.
#
# EMPTY = this board has no pre-mission phase, which is what every scenario saved before #735 is:
# it keeps its authored cast and boots straight into turn 1. That fallback is why adding this
# breaks nothing -- the objectives: [] shape. A named roster that no longer resolves is a BLOCKS
# finding in BoardLint rather than a silent fallback: substituting a different pool would hand the
# player a different mission.
@export var roster := ""

# Where the camera OPENS on this board (#234). Null = derive it -- battle3d frames the player's own
# units, which is the right default and the wrong authored answer for a handcrafted level. Authored
# is AUTHORITATIVE; the derivation is the fallback for a board that says nothing (Law #4, same shape
# as objectives-vs-painted-zones above).
#
# A REFERENCE here, unlike look_preset's name-only rule right above, and the difference is the point:
# a LookPreset is a file with a life of its own, so a ref can dangle or silently embed (the #177
# unit_data trap). A CameraPose has no file and no existence outside this board -- embedding it as a
# sub-resource is exactly what should happen on save. Do not "fix" this to a name.
#
# The obvious worry -- load board A, Save As board B, and B holds an ext_resource pointing into A's
# sub-resources -- was MEASURED and does not happen (2026-08-15): a loaded pose carries the path
# "A.tres::Resource_xxx", and ResourceSaver still writes it into B as a fresh [sub_resource]. So no
# defensive duplicate() on the capture side, and no dangling reference between two boards.
@export var camera_start: CameraPose = null

# Which factions the computer plays on this board (#150). Empty = every faction is manual, which
# is the hotseat/dev-scratch default; an authored mission lists its ENEMY here or the player is
# handed both sides. Applied exhaustively on load via AIController.set_ai_factions, so a board
# that declares nothing actively turns the last board's flags OFF.
@export var ai_factions: Array[Team.Faction] = []

# --- Mission-scoped battle state (#87), the board-wide half of a mid-battle snapshot. ---
@export var dialog_beats: Array[DialogBeat] = []      # authored dialog moments (#182); ScenarioDirector fires them
@export var tutorial_steps: Array[TutorialStep] = []  # the sequential lesson (#182); same director runs it
@export var captured_zones: Array[String] = []   # CAPTURE zones already claimed
@export var contested := false   # "both sides were ever up at once" latch
@export var rounds_elapsed := 0  # rounds the clock has counted (#101); the LIMIT above is authored


# Was this board saved before #427's corner heights? The one reader is BoardSnapshot.from_scenario,
# which refuses loudly rather than letting a stale board load as a flat one. A silent flat load is
# the failure this guards: CLAUDE.md's retyping trap, arriving through an absent field instead of a
# mismatched one.
func predates_corner_heights() -> bool:
	return corner_heights.is_empty() and (not elevations.is_empty() or not ramp_rises.is_empty())
