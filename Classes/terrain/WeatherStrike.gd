extends Object
class_name WeatherStrike

# The sky striking the ground (#1660): at each round's end the weather's element (WeatherRules.ground)
# hits every tile's ground through the terrain reactions, the GROUND half of a hit
# (PlanResolver._resolve_cell_effect_at), so rain douses fire and slakes quicklime and snow freezes
# water by the rules a water or ice hit already follows. No unit is struck and nothing in the air.
# Gas a reaction releases lies where GasSpread.released_onto says, as every release's does.
#
# Static and pure. GasField.next_round folds it, so the round and every forecast of it read one
# answer; the round lands its tile half through TurnBoundary.end_round, after the gas round read it.


# The round the next round's end closes: 1 throughout the first. A board with no mission is in round 1.
static func ending_round(board: BoardContext) -> int:
	return (board.mission.rounds_elapsed if board.mission != null else 0) + 1


# The element the sky strikes with at this round's end, NONE when it strikes nothing yet.
static func element(board: BoardContext) -> Elemental.Element:
	var rules := WeatherRules.for_kind(board.weather)
	if rules == null or ending_round(board) < rules.ground_from:
		return Elemental.Element.NONE
	return rules.ground


# The ground reactions a strike of `hit` fires somewhere: the one list the strike, the tile card and
# the pre-mission box all read.
static func reactions(hit: Elemental.Element) -> Array[TerrainReaction]:
	var out: Array[TerrainReaction] = []
	if hit == Elemental.Element.NONE:
		return out
	var elements: Array[Elemental.Element] = [hit]
	for reaction in TerrainReactionCatalog.get_all():
		if not reaction.in_the_air and reaction.fires_for(elements):
			out.append(reaction)
	return out


# What this round's end does to the tiles, one effect per cell it changes. Gas released where it
# cannot lie spills to the cell's open sides (#1537), landing in that side's own effect.
static func effects(board: BoardContext) -> Array[ResolvedCellEffect]:
	var out: Array[ResolvedCellEffect] = []
	if board == null or board.grid == null:
		return out
	var hit := element(board)
	var fired := reactions(hit)
	if fired.is_empty():
		return out
	var elements: Array[Elemental.Element] = [hit]
	var at: Dictionary[Vector2i, ResolvedCellEffect] = {}
	var spilled: Array[Dictionary] = []
	for cell in _candidates(board, fired):
		var effect := PlanResolver._resolve_cell_effect_at(cell, elements, board, fired)
		if effect == null or not _changes(effect, board.tile_states_at(cell)):
			continue
		if not effect.gas_added.is_empty() and not GasSpread.holds_gas(cell, board):
			spilled.append({"from": cell, "gas": effect.gas_added.duplicate()})
			effect.gas_added.clear()
			if effect.states_added.is_empty() and effect.states_removed.is_empty():
				continue
		out.append(effect)
		at[cell] = effect
	for spill: Dictionary in spilled:
		var gas: Dictionary = spill["gas"]
		for to in GasSpread.released_onto(spill["from"], board):
			var landing: ResolvedCellEffect = at.get(to, null)
			if landing == null:
				landing = ResolvedCellEffect.new()
				landing.cell = to
				out.append(landing)
				at[to] = landing
			for kind: Gas.Kind in gas:
				landing.add_gas(kind, gas[kind])
	return out


# The cells a strike of `fired` could change: a superset, so effects() asks the full gate
# (_resolve_cell_effect_at) only where one could pass. A reaction needing a state looks only where that
# state lies, live or planned; one needing a kind or a substance only on the tiles that are it, found
# through the TileSet (get_used_cells_by_id); one needing neither, everywhere. Alt's outline runs the
# round every frame it is held, and asking every tile cost ~3.5 ms there on The Drowned Orchard.
static func _candidates(board: BoardContext, fired: Array[TerrainReaction]) -> Array[Vector2i]:
	var grid := board.grid
	var by_tile: Array[TerrainReaction] = []
	var seen: Dictionary[Vector2i, bool] = {}
	for reaction in fired:
		if reaction.required_tile_state != Terrain.TileState.NONE:
			if board.terrain_states != null:
				for cell in board.terrain_states.cells_with(reaction.required_tile_state):
					seen[cell] = true
			if board.tiles != null:
				for cell in board.tiles.cells():
					seen[cell] = true
		elif reaction.required_kind != Terrain.Kind.NONE or reaction.required_made_of != "":
			by_tile.append(reaction)
		else:
			return grid.get_used_cells()
	if not by_tile.is_empty():
		if grid.tile_set == null:
			return grid.get_used_cells()
		var tiles := grid.tile_set
		for s in tiles.get_source_count():
			var source_id := tiles.get_source_id(s)
			var source := tiles.get_source(source_id) as TileSetAtlasSource
			if source == null:
				continue
			for i in source.get_tiles_count():
				var coords := source.get_tile_id(i)
				for a in source.get_alternative_tiles_count(coords):
					var alternative := source.get_alternative_tile_id(coords, a)
					if _tile_answers(source.get_tile_data(coords, alternative), by_tile):
						for cell in grid.get_used_cells_by_id(source_id, coords, alternative):
							seen[cell] = true
	var out: Array[Vector2i] = []
	out.assign(seen.keys())
	return out


# Is a tile of this data one a kind- or substance-gated reaction could fire on.
static func _tile_answers(data: TileData, reactions: Array[TerrainReaction]) -> bool:
	if data == null:
		return false
	var kind := GridUtils.terrain_kind_of(data)
	var made_of := GridUtils.made_of(data)
	for reaction in reactions:
		if (reaction.required_kind == Terrain.Kind.NONE or reaction.required_kind == kind) \
				and (reaction.required_made_of == "" or made_of.has(reaction.required_made_of)):
			return true
	return false


# Does this effect change the cell: a state it lacks, one it holds removed, or gas. Water already
# frozen is struck by Snow every round and changes nothing.
static func _changes(effect: ResolvedCellEffect, held: Array[Terrain.TileState]) -> bool:
	if not effect.gas_added.is_empty():
		return true
	for state in effect.states_added:
		if not held.has(state):
			return true
	for state in effect.states_removed:
		if held.has(state):
			return true
	return false


# The board as this round's end leaves its tiles, written nowhere: what the gas round reads.
static func at_round_end(board: BoardContext) -> BoardContext:
	return PlannedTiles.after(board, effects(board))


# "at the round's end", or "from the end of round 3" while that round is still to come.
static func when_text(rules: WeatherRules, round_ending: int) -> String:
	if round_ending >= rules.ground_from:
		return "at the round's end"
	return "from the end of round %d" % rules.ground_from


# The tile card's row for this cell (#1660): what the weather does to it, "" when nothing.
static func card_line(board: BoardContext, cell: Vector2i) -> String:
	var rules := WeatherRules.for_kind(board.weather)
	if rules == null:
		return ""
	var effects_here := Glossary.strike_effects(reactions(rules.ground), board.terrain_kind_at(cell),
			board.tile_states_at(cell), board.made_of_at(cell))
	if effects_here.is_empty():
		return ""
	return "%s, %s → %s" % [Weather.display_name(board.weather), when_text(rules, ending_round(board)),
			", ".join(effects_here)]
