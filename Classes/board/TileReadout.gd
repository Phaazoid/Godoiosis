extends RefCounted
class_name TileReadout

# THE tile-facts builder (#1105): what a cell carries, one Section per layer. Two readers -- the
# hover card, which draws the GROUND lines, and the Inspect dock's tile mode, which draws every
# section whole. Composed fresh per ask and never cached, so it is always about now.
#
# Every fact comes off the store that already answers it, never a re-derivation: watches off
# OverlayManager's marked set (so a watch whose reticle is gone is never named), zones off
# ZoneManager filtered by MissionController.hidden_zone_names (so a zone whose tint is gone is never
# named), meanings off Glossary. The GROUND section is HoverPresenter._tile_readout_lines, moved
# here unchanged.
#
# Explicit types throughout: `game` is untyped (game.gd has no class_name).

enum Layer { WATCH, ZONE, GROUND }

# PLACEHOLDER headings and side words, the dev's to rewrite.
const HEADING_ZONES := "Zones"
const HEADING_GROUND := "Ground"
const SIDE_WORDS: Dictionary[Team.Faction, String] = {
	Team.Faction.PLAYER: "yours",
	Team.Faction.ENEMY: "enemy",
	Team.Faction.ALLY: "allied",
	Team.Faction.NEUTRAL: "neutral",
}


class Row:
	var text: String
	var note: bool   # an explanation rather than a fact -- drawn quieter

	static func make(row_text: String, is_note := false) -> Row:
		var row := Row.new()
		row.text = row_text
		row.note = is_note
		return row


class Section:
	var layer: TileReadout.Layer
	var heading: String
	var marking: Texture2D = null   # the board mark this layer wears, tinted by marking_color
	var marking_color := Color.WHITE
	var rows: Array[Row] = []


# Every section this cell has, in the dock's order: the threat, then objectives, then the ground.
# A layer with nothing to say is absent.
static func compose(game, cell: Vector2i) -> Array[Section]:
	var sections: Array[Section] = []
	var watch := _watch_section(game, cell)
	if watch != null:
		sections.append(watch)
	var zones := _zone_section(game, cell)
	if zones != null:
		sections.append(zones)
	var ground := Section.new()
	ground.layer = Layer.GROUND
	ground.heading = HEADING_GROUND
	for line in ground_lines(game, cell):
		ground.rows.append(Row.make(line))
	if not ground.rows.is_empty():
		sections.append(ground)
	return sections


# A flat signature of what compose() said, for a live reader to diff against.
static func signature(sections: Array[Section]) -> String:
	var parts: Array[String] = []
	for section in sections:
		parts.append(section.heading)
		for row in section.rows:
			parts.append(row.text)
	return "\n".join(parts)


# The card's name for this tile (2026-08-12): authored terrain_name first, kind name as the
# fallback -- the same policy the brush palette rows read (GridUtils.authored_tile_display_name), so
# hover, dock and palette cannot disagree. A bare unnamed NONE-kind tile stays nameless on purpose.
static func title_of(game, cell: Vector2i) -> String:
	var board: BoardContext = game._board()
	var kind: Terrain.Kind = board.terrain_kind_at(cell)
	var data: TileData = game.grid.get_cell_tile_data(cell)
	var authored: String = GridUtils.authored_tile_display_name(data)
	if authored != "":
		return authored
	return Terrain.kind_display_name(kind) if kind != Terrain.Kind.NONE else ""


# The tile's own sprite, the picture both cards wear.
static func icon_of(game, cell: Vector2i) -> Texture2D:
	var source: TileSetAtlasSource = game.grid.tile_set.get_source(game.grid.get_cell_source_id(cell)) as TileSetAtlasSource
	return GridUtils.tile_sprite(source, game.grid.get_cell_atlas_coords(cell))


static func _watch_section(game, cell: Vector2i) -> Section:
	var om: OverlayManager = game.overlay_manager
	var covering: Array[Watch] = om.watches_covering(cell)
	if covering.is_empty():
		return null
	var section := Section.new()
	section.layer = Layer.WATCH
	section.heading = Glossary.title(Glossary.Term.OVERWATCH)
	section.marking = OverlayManager.WATCH_MARK_TEXTURE
	section.marking_color = OverlayManager.WATCH_MARK_COLOR
	section.rows.append(Row.make(Glossary.short(Glossary.Term.OVERWATCH), true))
	for watch in covering:
		section.rows.append(Row.make(_watch_line(watch)))
	return section


# "Brigand Archer (enemy), Longbow" -- who, whose side from the player's seat, and what fires.
static func _watch_line(watch: Watch) -> String:
	var line := "%s (%s)" % [watch.watcher.get_unit_name(), SIDE_WORDS[watch.watcher.get_faction()]]
	if watch.attack != null and watch.attack.display_name != "":
		line += ", " + watch.attack.display_name
	return line


static func _zone_section(game, cell: Vector2i) -> Section:
	var zones: ZoneManager = game.zone_manager
	var hidden: Array[String] = game.mission_controller.hidden_zone_names()
	var section := Section.new()
	section.layer = Layer.ZONE
	section.heading = HEADING_ZONES
	for zone_name in zones.zone_names():
		var kind: ZoneManager.Kind = zones.kind_of(zone_name)
		if ZoneManager.AUTHORING_KINDS.has(kind) or hidden.has(zone_name):
			continue
		if not zones.contains(zone_name, cell):
			continue
		var term: Glossary.Term = Glossary.term_for_zone_kind(kind)
		section.rows.append(Row.make("%s: %s" % [zone_name, Glossary.title(term)]))
		section.rows.append(Row.make(Glossary.short(term), true))
	return null if section.rows.is_empty() else section


# The tile card's body (#135): each dynamic state (with its live clock), the ground rules worth
# knowing (water's traversal gate, a move cost above the norm), then which elements can touch
# this tile — filtered through the SAME predicate the resolver's deposit filter runs
# (TerrainReaction.applies_to_tile, via Glossary.terrain_reactions_for). Meanings come from
# Glossary short texts, numbers from the reads the rules make — the card can't disagree with
# either. The kind itself is the card's header (title_of).
static func ground_lines(game, cell: Vector2i) -> Array[String]:
	var lines: Array[String] = []
	var board: BoardContext = game._board()
	var held: Array[Terrain.TileState] = []
	if board.terrain_states != null:
		held = board.terrain_states.states_at(cell)
	for state: Terrain.TileState in held:
		var line: String = "%s — %s" % [Terrain.tile_state_display_name(state),
			Glossary.short(Glossary.term_for_tile_state(state))]
		var turns: int = board.terrain_states.turns_remaining(cell, state)
		if turns > 0:
			line += " %d left." % turns
		lines.append(line)
	var kind: Terrain.Kind = board.terrain_kind_at(cell)
	if kind == Terrain.Kind.WATER:
		# One Kind, two tiles (#116) — so the card asks the same question the rules ask: water you
		# cannot stand on is the DEEP kind. Reading walkability rather than a second enum member is
		# what makes a FROZEN cell read as the shallow line for free, since is_walkable knows state.
		lines.append(Glossary.short(Glossary.Term.WATER_TILE if not board.is_walkable(cell)
			else Glossary.Term.SHALLOW_WATER))
	var data: TileData = game.grid.get_cell_tile_data(cell)
	if data != null and data.has_custom_data("move_cost"):
		var cost: int = data.get_custom_data("move_cost")
		if cost > 1:
			lines.append("Slow going — costs %d movement to enter." % cost)
	# Elevation (#257). Only spoken when it is non-default, so a flat board's card reads exactly as
	# it did before verticality existed — the same rule the move_cost line above follows.
	var elevation: int = board.elevation_at(cell)
	var corners: Vector4i = board.corners_at(cell)
	var rise: Terrain.RampRise = Terrain.rise_of_corners(corners)
	var climb: int = Terrain.climb_of_corners(corners)
	if rise != Terrain.RampRise.NONE:
		# BOTH ends, because a ramp's steepness is authored since #427 slice 2 — "rises east from 4"
		# no longer says where it arrives, and which heights it joins is the whole rule.
		#
		# The sideways clause went with #427 slice 3: a step is refused when the shared edge does not
		# meet, which still refuses this ramp's sides but no longer refuses a slope continuing
		# alongside it. Saying "only along that slope" would now be a card describing a rule the
		# board does not follow.
		lines.append("Ramp — rises %s from height %d to height %d."
			% [Terrain.ramp_rise_display_name(rise).to_lower(), elevation, elevation + climb])
	elif climb > 0:
		# A corner form: RampRise cannot name it, so the card says what it IS rather than reaching
		# for a direction that does not exist (#427 slice 3).
		lines.append("Corner slope — height %d rising to %d across part of the cell."
			% [elevation, elevation + climb])
	elif elevation != 0:
		lines.append("Height %d — reached only by a ramp that climbs to it." % elevation)
	lines.append_array(Glossary.terrain_reactions_for(kind, held))
	return lines
