# ThreatField (#710, the hover tier): every cell an enemy could attack NEXT turn, as an upper bound
# per archetype -- Hold from where it stands, Sentry only inside its zone, Rushdown across its whole
# move range -- under the same fireable + vertical filters the AI's own candidate builder applies.
# Each case discriminates one rule; the last is the WIRE: every attack the real AI queues lands
# inside the field it was built against. Real managers + TestTiles via board_builder.
#
# #1197 added two mechanisms the field used to paint safe -- the lanes a watcher could arm, and where a
# SHOCK hit's current runs -- and a second wire over every VICTIM the AI's resolved plan hits.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const ZONE := "post"
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


# Water is AUTHORED per cell (the content razor, test_conduction.gd's idiom) on top of the real grid,
# so heights, zones and walkability stay the board's own.
class _WaterContext extends BoardContext:
	var water := {}
	func _init(grid_layer: TileMapLayer, unit_list: Array[Unit], manager: SquadManager,
			board_heights: BoardHeights) -> void:
		super(grid_layer, unit_list, manager, null, null, board_heights)
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.WATER if water.has(cell) else super.terrain_kind_at(cell)


func _build_board() -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 8, 3))
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i, armed := true) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data({}, faction), cell)
	if armed:
		unit.equipped_weapon = H.make_weapon()
	return unit


# Zone = the 4x3 room x:0..3 / y:0..2 (inside the painted 8x3 board).
func _make_zone_manager() -> ZoneManager:
	var zones: ZoneManager = auto_free(ZoneManager.new())
	for x in range(0, 4):
		for y in range(0, 3):
			zones.paint_cell(ZONE, ZoneManager.Kind.PATROL, Vector2i(x, y))
	return zones


func _context(board: Dictionary, zones: ZoneManager = null) -> BoardContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	return BoardContext.new(board.grid, units, board.squad_manager, null, zones, board.board_heights)


func _bind(unit: Unit, archetype: AIArchetype.Type, zone_name := "") -> Squad:
	var squad: Squad = unit.squad
	squad.archetype = archetype
	squad.zone_name = zone_name
	squad.home_cell = unit.movement.cell
	return squad


func _neighbours(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN]
	out.sort()
	return out


func _keys(store: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(store.keys())
	return out


func _sorted(cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = cells.duplicate()
	out.sort()
	return out


func test_a_hold_unit_marks_only_the_reach_from_where_it_stands() -> void:
	var board: Dictionary = _build_board()
	var guard: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))
	_bind(guard, AIArchetype.Type.HOLD)
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	# A pattern-less weapon reaches the four neighbours and nothing else -- Hold never walks.
	assert_that(_sorted(field.reach_of(guard))).is_equal(_neighbours(Vector2i(3, 1)))
	assert_array(field.attackers_of(Vector2i(2, 1))).contains_exactly([guard])
	assert_array(field.attackers_of(Vector2i(5, 1))).is_empty()


func test_a_rushdown_marks_a_cell_it_must_walk_to_first() -> void:
	var board: Dictionary = _build_board()
	var rusher: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))
	_bind(rusher, AIArchetype.Type.RUSHDOWN)
	var mov: int = rusher.get_mov()
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	# One step past its move range is a swing from the far edge of it; two steps past is not.
	assert_bool(field.cells.has(Vector2i(mov + 1, 1))).override_failure_message(
			"a cell one past the move range is reachable by walking then swinging").is_true()
	assert_bool(field.cells.has(Vector2i(mov + 2, 1))).override_failure_message(
			"a cell two past the move range is out of reach next turn").is_false()


# SLICE 4 REVERSED THIS CASE'S VERDICT, and the rule it used to pin is still true one layer up:
# a sentry will not OPEN outside its leash (SentryArchetype's own lure-proofing, pinned there and by
# the wire case at the bottom of this file), but it ANSWERS a blow from anywhere it can stand. The
# field is what a player must not walk into, so it carries both.
func test_a_sentry_answers_one_counter_range_outside_its_leash() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var sentry: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))   # zone edge, at its post
	_bind(sentry, AIArchetype.Type.SENTRY, ZONE)
	var field := ThreatField.build(_context(board, zones), Team.Faction.PLAYER)
	# (4, 1) is adjacent and OUTSIDE the zone: poke it from there and it swings back.
	assert_bool(field.cells.has(Vector2i(4, 1))).override_failure_message(
			"a patrol's counter rim never reached past its leash").is_true()
	assert_bool(field.cells.has(Vector2i(2, 1))).is_true()
	# ...and the rim is the COUNTER's reach, not the whole board: two cells out is still clear.
	assert_bool(field.cells.has(Vector2i(5, 1))).override_failure_message(
			"the rim ran past the counter's own range").is_false()


func test_an_unarmed_patrol_gets_no_counter_rim() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	# No weapon: attack_source_can_counter() is false, which is the gate the rim borrows rather than
	# restating -- so a dry or unarmed enemy adds nothing, exactly as it counters with nothing. And
	# since #1215 it fires nothing either, so the WHOLE reach is empty, not just the rim.
	var sentry: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1), false)
	_bind(sentry, AIArchetype.Type.SENTRY, ZONE)
	var field := ThreatField.build(_context(board, zones), Team.Faction.PLAYER)
	assert_bool(field.cells.has(Vector2i(4, 1))).override_failure_message(
			"a unit that cannot counter still painted a counter rim").is_false()
	assert_array(field.reach_of(sentry)).override_failure_message(
			"a patrol with nothing to fire still painted reach").is_empty()


# NOTHING TO FIRE, NOTHING THREATENED (#1215): the player's ring offers an empty hand no attack, so
# the field may not draw the bare-fist reach the resolver would give a null pick.
func test_an_enemy_with_nothing_to_fire_marks_no_reach() -> void:
	var board: Dictionary = _build_board()
	var bare: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1), false)
	_bind(bare, AIArchetype.Type.RUSHDOWN)
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	assert_array(field.reach_of(bare)).override_failure_message(
			"an enemy with nothing to fire was drawn threatening its neighbours").is_empty()
	assert_bool(field.cells.is_empty()).override_failure_message(
			"the field marked cells nobody on the board can hit").is_true()


# Your own red goes through the same walk, so an unarmed unit of yours is shown no reach either.
func test_reach_from_an_unarmed_unit_is_empty() -> void:
	var board: Dictionary = _build_board()
	var mine: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(3, 1), false)
	var context := _context(board)
	var here: Array[Vector2i] = [mine.movement.cell]
	assert_array(ThreatField.reach_from(mine, context, here)).override_failure_message(
			"an empty hand was shown red it cannot attack into").is_empty()
	mine.equipped_weapon = H.make_weapon()
	assert_array(ThreatField.reach_from(mine, context, here)).override_failure_message(
			"fixture: armed, the same cell should reach its neighbours -- the empty read proves nothing"
			).is_not_empty()


func test_the_counter_rim_adds_nothing_to_a_rushdown() -> void:
	var board: Dictionary = _build_board()
	var rusher: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(4, 1))
	_bind(rusher, AIArchetype.Type.RUSHDOWN)
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	# The rim is a PATROL fix and must not widen anybody else's red -- the reason being structural
	# rather than incidental: a leashless archetype clips nothing, and its counter attack is already
	# one of the attacks the first pass walks. Assert the reason, then the consequence.
	assert_array(rusher.get_selectable_attacks()).contains([rusher.get_counter_attack()])
	var opens := {}
	for origin: Vector2i in field.move_of(rusher):
		for attack: AttackData in rusher.get_selectable_attacks():
			for cell: Vector2i in Reach.get_all_attack_cells_from(rusher, origin, attack):
				opens[cell] = true
	assert_array(_sorted(field.reach_of(rusher))).override_failure_message(
			"the counter rim widened an archetype that has no leash to widen past"
			).is_equal(_sorted(_keys(opens)))


# A FOLLOWER IS NOT LEASHED TO WHERE ITS LEADER STANDS NOW (slice 4). compute_move_range files every
# cell outside the cohesion bubble under `squad_unreachable`, measured against the leader's CURRENT
# cell -- but the enemy's own turn moves the leader FIRST and GroupMoveSolver then measures members
# against its DESTINATION, so those cells are exactly the ground a follower walks. This field is an
# upper bound; applying the clamp made it a lower one.
func test_a_followers_envelope_holds_the_cells_its_leash_files_as_unreachable() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))
	var member: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(4, 1))   # out at the leash's edge
	board.squad_manager.join_squad(member, leader.squad)
	_bind(leader, AIArchetype.Type.RUSHDOWN)

	var context := _context(board)
	var walk: Dictionary = RulesService.compute_move_range(member, context)
	var clamped: Dictionary = walk["squad_unreachable"]
	assert_int(clamped.size()).override_failure_message(
			"fixture is vacuous: this member's range never spills past its leader's bubble"
			).is_greater(0)

	var field := ThreatField.build(context, Team.Faction.PLAYER)
	var envelope := {}
	for cell: Vector2i in field.move_of(member):
		envelope[cell] = true
	for cell: Vector2i in clamped:
		assert_bool(envelope.has(cell)).override_failure_message(
				"%s is walkable next turn once the leader moves, and the envelope omitted it" % cell
				).is_true()


# ...and the PUBLIC door over the same walk answers about the origins it is HANDED (#1066). That
# is the whole reason it exists: the player's own red range rides this walk, and the envelope above
# is a prediction about an enemy where the player's blue is a PERMISSION -- so the caller names the
# ground rather than the walk choosing it. A door that quietly re-derived origins would be the
# duplicate this one was built to avoid.
func test_reach_from_answers_about_the_origins_it_is_given() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))
	var member: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(4, 1))
	board.squad_manager.join_squad(member, leader.squad)
	_bind(leader, AIArchetype.Type.RUSHDOWN)
	var context := _context(board)

	# One cell in, so the answer is the neighbourhood of that cell and nothing else.
	var here: Array[Vector2i] = [member.movement.cell]
	assert_that(_sorted(ThreatField.reach_from(member, context, here))).override_failure_message(
			"the door widened past the one origin it was given").is_equal(_neighbours(member.movement.cell))

	# ...and the whole envelope in, so it is strictly more. Both sets are derived, so a retuned
	# archetype or a re-authored weapon moves them together.
	var whole: Array[Vector2i] = field_origins(context, member)
	assert_int(ThreatField.reach_from(member, context, whole).size()).override_failure_message(
			"a whole move envelope reaches no further than one cell -- the case proves nothing"
			).is_greater(4)

	var none: Array[Vector2i] = []
	assert_array(ThreatField.reach_from(member, context, none)).override_failure_message(
			"nowhere to stand still threatened something").is_empty()


# The envelope ThreatField itself would use, read back off a built field rather than re-derived.
func field_origins(context: BoardContext, unit: Unit) -> Array[Vector2i]:
	return ThreatField.build(context, Team.Faction.PLAYER).move_of(unit)


func test_a_sentry_with_no_zone_holds_its_ground() -> void:
	var board: Dictionary = _build_board()
	var sentry: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))
	_bind(sentry, AIArchetype.Type.SENTRY)   # zone_name "" -- the archetype falls through to Hold
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	assert_that(_sorted(field.reach_of(sentry))).is_equal(_neighbours(Vector2i(0, 1)))


func test_a_ledge_above_the_melee_rule_is_unmarked() -> void:
	var board: Dictionary = _build_board()
	var brawler: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1), false)
	var club: WeaponInstance = H.make_weapon()   # a bare WeaponAttackData is RANGED by default
	club.template.main_attack.vertical_rule = AttackData.VerticalRule.MELEE
	brawler.equipped_weapon = club
	_bind(brawler, AIArchetype.Type.HOLD)
	board.board_heights.set_cell(Vector2i(4, 1), 2 * Terrain.UNITS_PER_LEVEL)   # a sheer two-level rise
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	assert_bool(field.cells.has(Vector2i(2, 1))).is_true()
	assert_bool(field.cells.has(Vector2i(4, 1))).override_failure_message(
			"a cell above the melee rule's tolerance was marked as threatened").is_false()


func test_a_downed_enemy_threatens_nothing() -> void:
	var board: Dictionary = _build_board()
	var body: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))
	_bind(body, AIArchetype.Type.HOLD)
	body.force_down()
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	assert_bool(field.cells.is_empty()).is_true()
	assert_bool(field.by_unit.has(body)).is_false()


func test_a_player_unit_is_never_part_of_the_field() -> void:
	var board: Dictionary = _build_board()
	var ally: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(3, 1))
	_bind(ally, AIArchetype.Type.HOLD)
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	assert_bool(field.cells.is_empty()).is_true()


func test_the_leash_is_a_sentry_squads_zone_and_nobody_elses() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var sentry: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 1))
	var rusher: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(6, 1))
	_bind(sentry, AIArchetype.Type.SENTRY, ZONE)
	_bind(rusher, AIArchetype.Type.RUSHDOWN, ZONE)   # names the zone, is not leashed to it
	var ctx := _context(board, zones)
	assert_int(ThreatField.leash_of(sentry.squad, ctx).size()).is_equal(12)
	assert_array(ThreatField.leash_of(rusher.squad, ctx)).is_empty()


# THE WIRE. The field is built against the board BEFORE the AI plans, then the real archetypes plan
# through the real SquadManager: every attack they queue must aim inside the field, or the preview
# promised safety the AI did not honour. Both walking archetypes, so a field blind to movement
# (Hold's envelope for everyone) reds here.
func test_every_attack_the_ai_queues_lands_inside_the_field() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var sentry: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 0))
	var rusher: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(7, 2))
	_bind(sentry, AIArchetype.Type.SENTRY, ZONE)
	_bind(rusher, AIArchetype.Type.RUSHDOWN)
	var _intruder: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(3, 1))   # in the zone, 4 steps from either
	var ctx := _context(board, zones)
	var field := ThreatField.build(ctx, Team.Faction.PLAYER)
	var aimed := 0
	for squad: Squad in [sentry.squad, rusher.squad]:
		AIController.plan_squad(squad, ctx, board.squad_manager)
		for action in squad.action_queue:
			if not (action is AttackAction):
				continue
			var aim := action as AttackAction
			aimed += 1
			assert_bool(field.by_unit.get(aim.actor, {}).has(aim.target_cell)).override_failure_message(
					"%s aimed at %s, which the field never marked" % [aim.actor.get_unit_name(), aim.target_cell]).is_true()
	assert_int(aimed).override_failure_message("no attack was queued -- the wire was never exercised").is_greater(0)


# --- #1197: the lanes a watcher could arm --------------------------------------------------------

# A weapon carrying a watchable extra -- what a Carbine is, without depending on that content (the
# builders suite's fixture). `shot_range` makes the main attack fire at exactly that distance, the
# Carbine's own shape; 0 leaves it the bare Manhattan-1.
func _watch_weapon(length: int, shot_range := 0) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CARBINE
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 3
	if shot_range > 0:
		P.point(template.main_attack, shot_range, shot_range)
	var watch := WeaponAttackData.new()
	watch.display_name = "Watch"
	watch.power = 3
	watch.can_overwatch = true
	P.line(watch, length)
	var extras: Array[WeaponAttackData] = [watch]
	template.extra_attacks = extras
	return WeaponInstance.make(template)


func _watcher(board: Dictionary, cell: Vector2i, archetype: AIArchetype.Type) -> Unit:
	var unit: Unit = _spawn(board, ENEMY, cell)
	unit.equipped_weapon = _watch_weapon(3)
	_bind(unit, archetype)
	return unit


# THE CARBINE'S SHAPE: a watch armed over somebody fires on the spot (#1003), so a lane it could arm is
# somewhere it can hit. The main attack here reaches the four neighbours only, so the far lane cells
# are the watch's alone.
func test_a_hold_watcher_marks_the_lane_its_attack_cannot_reach() -> void:
	var board: Dictionary = _build_board()
	var watcher := _watcher(board, Vector2i(3, 1), AIArchetype.Type.HOLD)
	var field := ThreatField.build(_context(board), PLAYER)
	for cell: Vector2i in [Vector2i(5, 1), Vector2i(6, 1), Vector2i(1, 1), Vector2i(0, 1)]:
		assert_bool(field.attackers_of(cell).has(watcher)).override_failure_message(
				"%s lies in a lane this watcher could arm, and the field called it safe" % cell).is_true()


# OVERWATCH is NEVER for Rushdown, read off the archetype's own declared list -- so the same weapon in
# a rusher's hands marks exactly what its attacks reach and not one lane cell more.
func test_a_rushdown_never_marks_a_watch_lane() -> void:
	var board: Dictionary = _build_board()
	var rusher := _watcher(board, Vector2i(0, 1), AIArchetype.Type.RUSHDOWN)
	var ctx := _context(board)
	var field := ThreatField.build(ctx, PLAYER)
	var origins: Array[Vector2i] = field.move_of(rusher)
	var attacks := {}
	for cell in ThreatField.reach_from(rusher, ctx, origins):
		attacks[cell] = true
	var lane_only := {}
	var watch := AITactics.watch_attack_for(rusher)
	for origin in origins:
		var lanes := AITactics.watch_lanes(rusher, origin, watch, ctx)
		for dir in lanes:
			for cell: Vector2i in lanes[dir]:
				if not attacks.has(cell):
					lane_only[cell] = true
	assert_int(lane_only.size()).override_failure_message(
			"fixture is vacuous: every lane cell is already in the rusher's attack reach").is_greater(0)
	assert_array(_sorted(field.reach_of(rusher))).override_failure_message(
			"a rusher's field gained the lanes of a watch it will never arm").is_equal(_sorted(_keys(attacks)))


# A dry watcher cannot arm (Overwatch needs readiness), so it marks no lane -- and refilled, the same
# watcher does, which is what stops the first half passing on an empty fixture.
func test_a_dry_watcher_marks_no_lane() -> void:
	var board: Dictionary = _build_board()
	var watcher := _watcher(board, Vector2i(3, 1), AIArchetype.Type.HOLD)
	var carbine := watcher.equipped_weapon as CarbineWeaponInstance
	(carbine.template.extra_attacks[0] as WeaponAttackData).requires_readiness = true
	carbine.shots_remaining = 0
	var ctx := _context(board)
	assert_bool(ThreatField.build(ctx, PLAYER).cells.has(Vector2i(5, 1))).override_failure_message(
			"a watcher with an empty magazine still painted its lane").is_false()
	carbine.shots_remaining = CarbineWeaponInstance.MAGAZINE_SIZE
	assert_bool(ThreatField.build(ctx, PLAYER).cells.has(Vector2i(5, 1))).override_failure_message(
			"fixture is vacuous: the loaded watcher marks no lane either").is_true()


# NOT ZONE-CLIPPED: the shot takes anyone in the lane, and a sentry at its post aims at the nearest
# enemy wherever that enemy stands. The counter rim reaches one cell past the zone; the lane, three.
func test_a_sentrys_lane_runs_past_its_zone() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var sentry: Unit = _spawn(board, ENEMY, Vector2i(3, 1))   # zone edge, at its post
	sentry.equipped_weapon = _watch_weapon(3)
	_bind(sentry, AIArchetype.Type.SENTRY, ZONE)
	var field := ThreatField.build(_context(board, zones), PLAYER)
	assert_bool(field.cells.has(Vector2i(6, 1))).override_failure_message(
			"a sentry's lane stopped at its leash, though the shot it fires does not").is_true()


# YOUR OWN red is a permission, not a prediction (#1066): reach_from walks fire and counter only, so a
# watch weapon in your hands shows what it can FIRE at, not the lanes it could arm.
func test_reach_from_draws_no_watch_lane() -> void:
	var board: Dictionary = _build_board()
	var unit := _watcher(board, Vector2i(3, 1), AIArchetype.Type.HOLD)
	var here: Array[Vector2i] = [unit.movement.cell]
	assert_that(_sorted(ThreatField.reach_from(unit, _context(board), here))).override_failure_message(
			"your own reach gained a prediction's watch lanes").is_equal(_neighbours(unit.movement.cell))


# --- #1197: where the current runs ---------------------------------------------------------------

func _water_board() -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 12, 3))
	return board


func _water_context(board: Dictionary, water: Array[Vector2i]) -> _WaterContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	var ctx := _WaterContext.new(board.grid, units, board.squad_manager, board.board_heights)
	for cell in water:
		ctx.water[cell] = true
	return ctx


func _shocker(board: Dictionary, cell: Vector2i) -> Unit:
	var unit: Unit = _spawn(board, ENEMY, cell)
	(unit.equipped_weapon as WeaponInstance).template.main_attack.elemental_damage_type = Elemental.Element.SHOCK
	_bind(unit, AIArchetype.Type.HOLD)
	return unit


func _row(from: Vector2i, length: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for i in length:
		cells.append(from + Vector2i(i, 0))
	return cells


# A SHOCK hit runs on through the water it lands in. Measured RELATIVE to SHOCK_ARC_RANGE, never the
# number 3: the last cell the current reaches is marked and the one past it is not.
func test_a_shock_attack_marks_the_water_its_current_reaches() -> void:
	var board := _water_board()
	var reach := Conduction.SHOCK_ARC_RANGE
	assert_int(3 + reach).override_failure_message("the arc outgrew this fixture's board").is_less(12)
	_shocker(board, Vector2i(1, 1))   # its own reach ends on (2, 1), the first cell of the water
	var ctx := _water_context(board, _row(Vector2i(2, 1), reach + 2))
	var field := ThreatField.build(ctx, PLAYER)
	assert_bool(field.cells.has(Vector2i(2 + reach, 1))).override_failure_message(
			"the water the current runs through was painted safe").is_true()
	assert_bool(field.cells.has(Vector2i(3 + reach, 1))).override_failure_message(
			"the current ran past its own reach").is_false()


# A WET unit conducts wherever it stands, dry ground included -- so the current reaches it off the
# end of the water, while the same unit dry is left alone.
func test_a_wet_unit_beside_the_water_relays_the_current() -> void:
	var board := _water_board()
	_shocker(board, Vector2i(1, 1))
	var soaked: Unit = _spawn(board, PLAYER, Vector2i(4, 1))   # dry ground, one past the water
	var ctx := _water_context(board, _row(Vector2i(2, 1), 2))
	assert_bool(ThreatField.build(ctx, PLAYER).cells.has(Vector2i(4, 1))).override_failure_message(
			"a dry unit on dry ground was painted as in the current").is_false()
	soaked.add_element_state(Elemental.State.WET)
	assert_bool(ThreatField.build(ctx, PLAYER).cells.has(Vector2i(4, 1))).override_failure_message(
			"a wet unit beside the lit water was painted safe").is_true()


# THE CURRENT IS THE ATTACK'S OWN: only a shock attack's cells seed it, so a plain swing that reaches
# the lake lights nothing. The same swing turned SHOCK lights the water past it -- the twin that proves
# the fixture can.
func test_only_a_shock_attacks_own_cells_seed_the_current() -> void:
	var board := _water_board()
	var unit: Unit = _spawn(board, ENEMY, Vector2i(1, 1))
	_bind(unit, AIArchetype.Type.HOLD)
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 3
	template.main_attack.elemental_damage_type = Elemental.Element.SHOCK
	P.point(template.main_attack, 3, 3)   # its ring never lands on the water
	var swing := WeaponAttackData.new()
	swing.power = 3   # Manhattan-1, so it reaches (0, 1)
	var extras: Array[WeaponAttackData] = [swing]
	template.extra_attacks = extras
	unit.equipped_weapon = WeaponInstance.make(template)
	var water: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
	var ctx := _water_context(board, water)
	var field := ThreatField.build(ctx, PLAYER)
	assert_bool(field.cells.has(Vector2i(0, 1))).override_failure_message(
			"fixture is vacuous: the plain swing never reaches the water").is_true()
	assert_bool(field.cells.has(Vector2i(0, 0))).override_failure_message(
			"a plain swing lit the water it reached").is_false()
	swing.elemental_damage_type = Elemental.Element.SHOCK
	assert_bool(ThreatField.build(ctx, PLAYER).cells.has(Vector2i(0, 0))).override_failure_message(
			"fixture is vacuous: even a shock swing lights nothing here").is_true()


# THE PENDING SOAK (dev, 2026-10-03): a unit your own queued plan wades through the water conducts as
# if it already were wet, read through AIController's own door. The same board with no pending hypo
# paints the cell safe, because the unit is dry until the plan runs.
func test_a_soaking_still_pending_in_your_plan_is_seen() -> void:
	var board := _water_board()
	_shocker(board, Vector2i(1, 1))
	var wader: Unit = _spawn(board, PLAYER, Vector2i(3, 2))
	var ctx := _water_context(board, _row(Vector2i(2, 1), 2))
	board.squad_manager.board_source = func() -> BoardContext: return ctx
	var path: Array[Vector2i] = [Vector2i(3, 2), Vector2i(3, 1), Vector2i(4, 1)]   # through (3, 1)
	var move := MoveAction.new()
	move.init(wader, path, null)
	assert_bool(board.squad_manager.queue_action(wader.squad, move)).override_failure_message(
			"the fixture's own wade was refused -- the case would prove nothing").is_true()

	var pending := AIController.pending_hypo(AIController.viewer_plans(PLAYER, board.squad_manager))
	assert_bool(PlanResolver.projected_states(wader, pending).has(Elemental.State.WET)).override_failure_message(
			"fixture is vacuous: the resolver never soaked the wader").is_true()
	assert_bool(ThreatField.build(ctx, PLAYER, pending).cells.has(Vector2i(4, 1))).override_failure_message(
			"the cell your own wade leaves you on, beside the lit water, was painted safe").is_true()
	assert_bool(ThreatField.build(ctx, PLAYER).cells.has(Vector2i(4, 1))).override_failure_message(
			"fixture is vacuous: the cell is lit with nobody wet").is_false()


# THE VICTIM WIRE (#1197). The field promises safety; the real AI then plans and resolves through the
# real SquadManager, and every PLAYER unit the plan hits -- by an ordinary attack, by a watch armed
# over it, or by the current running through the water -- must stand on a cell the field marked. The
# aim wire above checks where attacks POINT; this one checks who they HIT, which is the promise.
func test_every_unit_the_ai_would_hit_stands_inside_the_field() -> void:
	var board := _water_board()
	# Carbine-shaped: its Shot fires at exactly 2, so the neighbour is the watch's to take.
	var watcher: Unit = _spawn(board, ENEMY, Vector2i(9, 1))
	watcher.equipped_weapon = _watch_weapon(3, 2)
	_bind(watcher, AIArchetype.Type.HOLD)
	var beside: Unit = _spawn(board, PLAYER, Vector2i(10, 1))
	# A shocker hitting a wader, with a second wader one cell further along the same water.
	var shocker := _shocker(board, Vector2i(0, 0))
	var _near: Unit = _spawn(board, PLAYER, Vector2i(1, 0))
	var far: Unit = _spawn(board, PLAYER, Vector2i(2, 0))
	var ctx := _water_context(board, _row(Vector2i(1, 0), 2))
	var field := ThreatField.build(ctx, PLAYER)

	var hit := {}
	for squad: Squad in [watcher.squad, shocker.squad]:
		AIController.plan_squad(squad, ctx, board.squad_manager)
		var plan: ResolvedPlan = board.squad_manager.resolve_plan(squad, ctx)
		var rows: Array[AttackAction] = []
		rows.append_array(plan.attacks)
		rows.append_array(plan.watch_shots)
		for row in rows:
			var victim: Unit = row.target
			if victim == null or not is_instance_valid(victim) or victim.get_faction() != PLAYER:
				continue
			hit[victim] = true
			assert_bool(field.cells.has(victim.movement.cell)).override_failure_message(
					"%s is hit at %s, which the field called safe" % [victim.get_unit_name(), victim.movement.cell]).is_true()
	for victim: Unit in [beside, far]:
		assert_bool(hit.has(victim)).override_failure_message(
				"fixture is vacuous: %s was never hit, so its mechanism went unexercised" % victim.get_unit_name()).is_true()


# --- #46: the one builder both hosts call --------------------------------------------------------
#
# ThreatField.for_viewer is what game.threat_field() and the Play API's `ranges` both call, so a fault
# inside it moves the two hosts together and no comparison between them can see it. These pin it
# directly.

func _queue_wade(board: Dictionary, unit: Unit, path: Array[Vector2i]) -> void:
	var move := MoveAction.new()
	move.init(unit, path, null)
	assert_bool(board.squad_manager.queue_action(unit.squad, move)).override_failure_message(
			"the fixture's own move was refused -- the case would prove nothing").is_true()


# A one-cell corridor, with a nook beside its second square. The player stands in the corridor,
# blocking a rusher behind it, and queues one step away. Judged where the plan leaves it, the rusher
# follows through the square it vacates; judged where it stands, the rusher is stuck.
func test_for_viewer_judges_a_unit_where_its_plan_leaves_it_and_puts_everyone_back() -> void:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 8, 1))
	BB.paint_cell(board.grid, Vector2i(1, 1), BB.GRASS_ATLAS)
	var rusher: Unit = _spawn(board, ENEMY, Vector2i(0, 0))
	_bind(rusher, AIArchetype.Type.RUSHDOWN)
	var holder: Unit = _spawn(board, ENEMY, Vector2i(1, 1))   # reaches the corridor square the mover leaves
	_bind(holder, AIArchetype.Type.HOLD)
	var live := Vector2i(1, 0)
	var dest := Vector2i(2, 0)
	var mover: Unit = _spawn(board, PLAYER, live)
	var step: Array[Vector2i] = [live, dest]
	_queue_wade(board, mover, step)
	var sm: SquadManager = board.squad_manager

	var standing := ThreatField.build(sm.board_source.call() as BoardContext, PLAYER)
	assert_bool(standing.attackers_of(dest).has(rusher)).override_failure_message(
			"fixture is vacuous: the rusher reaches the destination past a body in its road").is_false()

	var field := ThreatField.for_viewer(sm, PLAYER, true)
	assert_bool(field.attackers_of(dest).has(rusher)).override_failure_message(
			"the destination was judged with you still in the corridor -- the square you leave is the rusher's road"
			).is_true()
	assert_bool(field.attackers_of(live).has(holder)).override_failure_message(
			"fixture is vacuous: the holder never reached the square the mover leaves").is_true()
	assert_bool(field.attackers_of(dest).has(holder)).override_failure_message(
			"the holder was drawn reaching the destination, so the two cells cannot be told apart").is_false()

	assert_that(mover.movement.cell).override_failure_message(
			"the build left the mover standing on its planned cell").is_equal(live)
	assert_that(rusher.movement.cell).override_failure_message(
			"the build moved a unit with no plan").is_equal(Vector2i(0, 0))
	assert_that(mover.get_projected_destination()).override_failure_message(
			"the build disturbed the plan it read").is_equal(dest)


# with_pending is what game.threat_field() turns off mid-pass. The soak a queued wade will deal lights
# the cell beside the water only when the pending plan is read.
func test_for_viewer_reads_the_pending_soak_only_when_asked() -> void:
	var board := _water_board()
	_shocker(board, Vector2i(1, 1))
	var wader: Unit = _spawn(board, PLAYER, Vector2i(3, 2))
	var ctx := _water_context(board, _row(Vector2i(2, 1), 2))
	board.squad_manager.board_source = func() -> BoardContext: return ctx
	var path: Array[Vector2i] = [Vector2i(3, 2), Vector2i(3, 1), Vector2i(4, 1)]   # through (3, 1)
	_queue_wade(board, wader, path)
	var sm: SquadManager = board.squad_manager

	assert_bool(ThreatField.for_viewer(sm, PLAYER, true).cells.has(Vector2i(4, 1))).override_failure_message(
			"with the pending plan read, the cell your wade leaves you on beside the lit water was painted safe"
			).is_true()
	assert_bool(ThreatField.for_viewer(sm, PLAYER, false).cells.has(Vector2i(4, 1))).override_failure_message(
			"the pending soak was read with with_pending off").is_false()
	assert_that(wader.movement.cell).override_failure_message(
			"the build left the wader on its planned cell").is_equal(Vector2i(3, 2))


# The viewer names whose danger it is: asked for the enemy side, the field holds the player's units.
func test_for_viewer_builds_the_field_the_named_side_faces() -> void:
	var board: Dictionary = _build_board()
	var foe: Unit = _spawn(board, ENEMY, Vector2i(1, 1))
	_bind(foe, AIArchetype.Type.HOLD)
	var mine: Unit = _spawn(board, PLAYER, Vector2i(5, 1))
	_bind(mine, AIArchetype.Type.HOLD)
	var sm: SquadManager = board.squad_manager
	var theirs := ThreatField.for_viewer(sm, ENEMY, true)
	assert_bool(theirs.by_unit.has(mine) and not theirs.by_unit.has(foe)).override_failure_message(
			"asked for the enemy's view, the field was not the player's units").is_true()
	var ours := ThreatField.for_viewer(sm, PLAYER, true)
	assert_bool(ours.by_unit.has(foe) and not ours.by_unit.has(mine)).override_failure_message(
			"asked for the player's view, the field was not the enemy's units").is_true()


# --- #1207: a placed blast's splash and a payload's landing -------------------------------------
#
# The AI aims BESIDE a target since #1220 -- a blast dropped next to it, a carrier thrown for the
# payload it leaves -- so the field must mark what those aims strike, not only where they may point.

const PLUS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _blaster(board: Dictionary, cell: Vector2i) -> Unit:
	var unit: Unit = _spawn(board, ENEMY, cell)
	var blast: WeaponAttackData = (unit.equipped_weapon as WeaponInstance).template.main_attack
	blast.power = 30
	P.stamped(blast, 2, PLUS, 2)
	_bind(unit, AIArchetype.Type.HOLD)
	return unit


func _bomber(board: Dictionary, cell: Vector2i) -> Unit:
	var unit: Unit = _spawn(board, ENEMY, cell)
	var carrier: WeaponAttackData = (unit.equipped_weapon as WeaponInstance).template.main_attack
	carrier.targets = EquippableData.TargetMode.MAP
	P.point(carrier, 1)
	var bomb := WeaponAttackData.new()
	bomb.power = 30
	P.stamped(bomb, 1, PLUS)
	carrier.payload = bomb
	_bind(unit, AIArchetype.Type.HOLD)
	return unit


func test_a_placed_blast_marks_its_splash_past_the_ring() -> void:
	var board := _water_board()
	var blaster := _blaster(board, Vector2i(5, 1))
	var field := ThreatField.build(_context(board), PLAYER)
	assert_bool(field.by_unit.get(blaster, {}).has(Vector2i(8, 1))).override_failure_message(
			"a cell inside the splash of an aim on the ring's edge was painted safe").is_true()
	assert_bool(field.by_unit.get(blaster, {}).has(Vector2i(9, 1))).override_failure_message(
			"fixture is vacuous: the splash reaches further than the shape").is_false()


func test_a_payload_marks_where_it_lands() -> void:
	var board := _water_board()
	var bomber := _bomber(board, Vector2i(5, 1))
	var field := ThreatField.build(_context(board), PLAYER)
	assert_bool(field.by_unit.get(bomber, {}).has(Vector2i(7, 1))).override_failure_message(
			"a cell the payload lands on was painted safe").is_true()


# The victim wire, for both shapes: the real AI plans, and everybody its plan hits stands on a cell
# the field marked. Each target can only be reached the new way -- one too close to aim the blast
# at, one only the payload reaches.
func test_every_unit_a_splash_or_payload_hits_stands_inside_the_field() -> void:
	var board := _water_board()
	var blaster := _blaster(board, Vector2i(8, 1))
	var close: Unit = _spawn(board, PLAYER, Vector2i(9, 1))
	var bomber := _bomber(board, Vector2i(1, 1))
	var downrange: Unit = _spawn(board, PLAYER, Vector2i(3, 1))
	var ctx := _context(board)
	var field := ThreatField.build(ctx, PLAYER)

	var hit := {}
	for squad: Squad in [blaster.squad, bomber.squad]:
		AIController.plan_squad(squad, ctx, board.squad_manager)
		var plan: ResolvedPlan = board.squad_manager.resolve_plan(squad, ctx)
		for row in plan.attacks:
			var victim: Unit = row.target
			if victim == null or not is_instance_valid(victim) or victim.get_faction() != PLAYER:
				continue
			hit[victim] = true
			assert_bool(field.cells.has(victim.movement.cell)).override_failure_message(
					"%s is hit at %s, which the field called safe" % [victim.get_unit_name(), victim.movement.cell]).is_true()
	for victim: Unit in [close, downrange]:
		assert_bool(hit.has(victim)).override_failure_message(
				"fixture is vacuous: a target was never hit, so its shape went unexercised").is_true()
