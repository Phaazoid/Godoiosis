extends Resource
class_name ScenarioData

@export var scenario_name := ""
@export var unit_entries: Array[ScenarioUnitEntry] = []
@export var tile_data: PackedByteArray
@export var terrain_states: Dictionary = {}   # Vector2i -> Array[Terrain.TileState] deposited at runtime
@export var active_faction: Team.Faction = Team.Faction.PLAYER # whose turn it was when saved
@export var zones: Dictionary = {}   # zone name -> {"kind": ZoneManager.Kind, "cells": Array[Vector2i]},
									 # painted via Tile Brush's Zone mode. Straight pass-through of
									 # ZoneManager.to_dict()/load_dict() — this is WHERE an objective
									 # happens; `objectives` below is WHAT the mission requires, and
									 # that one is authoritative (missions.md; MissionController
									 # reads an unpainted declared objective as PENDING, never NONE).
@export var objectives: Array[MissionRules.Objective] = []   # empty = plain rout map

# --- Mission-scoped battle state (#87), the board-wide half of a mid-battle snapshot. ---
@export var captured_zones: Array[String] = []   # CAPTURE zones already claimed
@export var contested := false   # "both sides were ever up at once" latch
