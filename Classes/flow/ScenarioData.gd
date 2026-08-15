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
@export var elevations: Dictionary = {}   # Vector2i -> int surface height (#257). SPARSE: an absent
										  # cell is height 0, so a flat board saves as {}. BoardHeights
										  # owns that default and is the only reader — see verticality.md.
@export var ramp_rises: Dictionary = {}   # Vector2i -> Terrain.RampRise. Sparse the same way (absent =
										  # NONE = not a ramp). Separate from `elevations` because a ramp
										  # at height 0 is legal and must survive the round trip.
@export var active_faction: Team.Faction = Team.Faction.PLAYER # whose turn it was when saved
@export var zones: Dictionary = {}   # zone name -> {"kind": ZoneManager.Kind, "cells": Array[Vector2i]},
									 # painted via Tile Brush's Zone mode. Straight pass-through of
									 # ZoneManager.to_dict()/load_dict() — this is WHERE an objective
									 # happens; `objectives` below is WHAT the mission requires, and
									 # that one is authoritative (missions.md; MissionController
									 # reads an unpainted declared objective as PENDING, never NONE).
@export var objectives: Array[MissionRules.Objective] = []   # empty = plain rout map

# Which factions the computer plays on this board (#150). Empty = every faction is manual, which
# is the hotseat/dev-scratch default; an authored mission lists its ENEMY here or the player is
# handed both sides. Applied exhaustively on load via AIController.set_ai_factions, so a board
# that declares nothing actively turns the last board's flags OFF.
@export var ai_factions: Array[Team.Faction] = []

# --- Mission-scoped battle state (#87), the board-wide half of a mid-battle snapshot. ---
@export var captured_zones: Array[String] = []   # CAPTURE zones already claimed
@export var contested := false   # "both sides were ever up at once" latch
