# The SHOCK arc (#884): a shock that lands on water -- or on a soaked body -- travels through every
# conductor it touches, and everything standing in the current is caught.
#
# Water is AUTHORED per cell rather than painted, the test_ice.gd idiom: which atlas coordinate is
# water is content (the content razor), and the rule is what is under test.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

class _WaterBoard extends BoardContext:
	var water: Dictionary
	func _init(unit_list: Array[Unit], water_cells: Array[Vector2i], states: TerrainStateManager) -> void:
		super(null, unit_list, null, states)
		water = {}
		for cell in water_cells:
			water[cell] = true
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.WATER if water.has(cell) else Terrain.Kind.GRASS


func _states(frozen: Array[Vector2i]) -> TerrainStateManager:
	var store: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(store)
	for cell in frozen:
		var freeze := ResolvedCellEffect.new()
		freeze.cell = cell
		freeze.states_added.assign([Terrain.TileState.FROZEN])
		store.apply(freeze)
	return store

func _board(units: Array[Unit], water: Array[Vector2i], frozen: Array[Vector2i] = []) -> _WaterBoard:
	return _WaterBoard.new(units, water, _states(frozen))

# A west-east run of water starting at the origin.
func _row(length: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in length:
		cells.append(Vector2i(x, 0))
	return cells

func _shooter(element: Elemental.Element, cell := Vector2i(0, -4)) -> Unit:
	var unit: Unit = H.spawn_unit(self, PLAYER, cell)
	(unit.get_equipped_weapon() as WeaponInstance).template.main_attack.elemental_damage_type = element
	return unit

func _water_sets_wet() -> ElementalReaction:
	var reaction := ElementalReaction.new()
	reaction.incoming_element = Elemental.Element.WATER
	reaction.add_states.assign([Elemental.State.WET])
	return reaction


func test_the_current_runs_through_the_water_the_shot_lands_in() -> void:
	var shooter := _shooter(Elemental.Element.SHOCK)
	var swimmer: Unit = H.spawn_unit(self, ENEMY, Vector2i(2, 0))
	var units: Array[Unit] = [shooter, swimmer]
	var board := _board(units, _row(4))
	var struck: Array[Vector2i] = [Vector2i(0, 0)]

	var arc := Conduction.arc_cells(shooter, shooter.get_fired_attack(), struck, board)
	assert_bool(arc.has(Vector2i(2, 0))).is_true()
	var no_one: Array[Unit] = []
	assert_bool(Conduction.caught(arc, board, {}, no_one).has(swimmer)).is_true()

# Measured RELATIVE to the constant, never against the number 3 -- retuning the reach must not red
# this. Both units stand in water, so the only thing separating them is distance.
func test_a_conductor_past_the_currents_reach_is_left_alone() -> void:
	var reach := Conduction.SHOCK_ARC_RANGE
	var shooter := _shooter(Elemental.Element.SHOCK)
	var inside: Unit = H.spawn_unit(self, ENEMY, Vector2i(reach, 0))
	var outside: Unit = H.spawn_unit(self, ENEMY, Vector2i(reach + 1, 0))
	var units: Array[Unit] = [shooter, inside, outside]
	var board := _board(units, _row(reach + 2))
	var struck: Array[Vector2i] = [Vector2i(0, 0)]

	var arc := Conduction.arc_cells(shooter, shooter.get_fired_attack(), struck, board)
	var no_one: Array[Unit] = []
	var hit := Conduction.caught(arc, board, {}, no_one)
	assert_bool(hit.has(inside)).is_true()
	assert_bool(hit.has(outside)).is_false()

# Ice is dry ground, so freezing a lake cuts it in half. The liquid control is what makes this mean
# something: without it the case passes against an arc that never reached that far anyway.
func test_ice_breaks_the_chain() -> void:
	var shooter := _shooter(Elemental.Element.SHOCK)
	var far: Unit = H.spawn_unit(self, ENEMY, Vector2i(3, 0))
	var units: Array[Unit] = [shooter, far]
	var water := _row(4)
	var struck: Array[Vector2i] = [Vector2i(0, 0)]
	var attack := shooter.get_fired_attack()

	var liquid := Conduction.arc_cells(shooter, attack, struck, _board(units, water))
	assert_bool(liquid.has(Vector2i(3, 0))).is_true()

	var frozen: Array[Vector2i] = [Vector2i(2, 0)]
	var iced := Conduction.arc_cells(shooter, attack, struck, _board(units, water, frozen))
	assert_bool(iced.has(Vector2i(1, 0))).is_true()      # up to the ice
	assert_bool(iced.has(Vector2i(3, 0))).is_false()     # and no further

# A soaked body is a conductor wherever it stands, so it carries the current onto dry ground. The dry
# control is the half that pins RELAYING rather than range: `far` is well inside the reach either
# way, and only the relay's own wetness decides whether the current gets to him.
func test_a_soaked_body_carries_the_current_across_dry_ground() -> void:
	var shooter := _shooter(Elemental.Element.SHOCK)
	var relay: Unit = H.spawn_unit(self, ENEMY, Vector2i(1, 0))
	var far: Unit = H.spawn_unit(self, ENEMY, Vector2i(2, 0))
	far.add_element_state(Elemental.State.WET)
	var units: Array[Unit] = [shooter, relay, far]
	var pond: Array[Vector2i] = [Vector2i(0, 0)]       # ONE water cell; the rest is dry
	var attack := shooter.get_fired_attack()

	var blocked := Conduction.arc_cells(shooter, attack, pond, _board(units, pond))
	assert_bool(blocked.has(Vector2i(2, 0))).is_false()

	relay.add_element_state(Elemental.State.WET)
	var open := Conduction.arc_cells(shooter, attack, pond, _board(units, pond))
	assert_bool(open.has(Vector2i(2, 0))).is_true()

# The current does not check tags (dev, 2026-09-10): a squadmate in the lake is caught, and so is the
# shooter standing in it, though the attack itself hits neither. Asked through sweep, because pairing
# the tag-blind gather with the tag-aware one is the part that is easy to get wrong.
func test_the_current_does_not_check_tags() -> void:
	var shooter := _shooter(Elemental.Element.SHOCK, Vector2i(0, 0))
	var ally: Unit = H.spawn_unit(self, PLAYER, Vector2i(1, 0))
	var enemy: Unit = H.spawn_unit(self, ENEMY, Vector2i(2, 0))
	var units: Array[Unit] = [shooter, ally, enemy]
	var board := _board(units, _row(3))
	var attack := shooter.get_fired_attack()
	assert_bool(attack.hits_allies).is_false()      # the ordinary rule this deliberately ignores
	assert_bool(attack.hits_self).is_false()

	var struck: Array[Vector2i] = [Vector2i(2, 0)]
	var reach := Conduction.sweep(shooter, attack, struck, board)
	assert_bool(reach.victims.has(enemy)).is_true()
	assert_bool(reach.victims.has(ally)).is_true()
	assert_bool(reach.victims.has(shooter)).is_true()

func test_an_attack_carrying_no_shock_does_not_arc() -> void:
	var shooter := _shooter(Elemental.Element.FIRE)
	var swimmer: Unit = H.spawn_unit(self, ENEMY, Vector2i(2, 0))
	var units: Array[Unit] = [shooter, swimmer]
	var board := _board(units, _row(4))
	var struck: Array[Vector2i] = [Vector2i(0, 0)]

	var arc := Conduction.arc_cells(shooter, shooter.get_fired_attack(), struck, board)
	assert_int(arc.size()).is_equal(0)

# The seed gate: the shot has to TOUCH a conductor. A lake one cell away is not a lake you hit.
func test_a_shock_beside_the_water_does_not_arc_into_it() -> void:
	var shooter := _shooter(Elemental.Element.SHOCK)
	var swimmer: Unit = H.spawn_unit(self, ENEMY, Vector2i(1, 0))
	var units: Array[Unit] = [shooter, swimmer]
	var board := _board(units, _row(4))
	var struck: Array[Vector2i] = [Vector2i(0, 1)]      # dry, and orthogonally touching the water

	var arc := Conduction.arc_cells(shooter, shooter.get_fired_attack(), struck, board)
	assert_int(arc.size()).is_equal(0)

# E4 through the arc, and the case a live read cannot pass: a body an earlier order in THIS pass
# soaked conducts for a shock later in it, while the board still says he is dry because execution
# has not run. The two readings of one board are asserted side by side.
func test_the_current_reads_this_passs_wetness_and_not_the_boards() -> void:
	var soaker := _shooter(Elemental.Element.WATER, Vector2i(0, -3))
	var shooter := _shooter(Elemental.Element.SHOCK, Vector2i(0, -4))
	var relay: Unit = H.spawn_unit(self, ENEMY, Vector2i(1, 0))
	var far: Unit = H.spawn_unit(self, ENEMY, Vector2i(2, 0))
	far.add_element_state(Elemental.State.WET)
	var units: Array[Unit] = [soaker, shooter, relay, far]
	var pond: Array[Vector2i] = [Vector2i(0, 0)]
	var board := _board(units, pond)

	var plan := ResolvedPlan.new()
	plan.attacks.append(H.stamped_attack(soaker, relay))
	var reactions: Array[ElementalReaction] = [_water_sets_wet()]
	var no_terrain: Array[TerrainReaction] = []
	PlanResolver.resolve_attacks(plan, plan.hypo, reactions, board, no_terrain)

	assert_bool(relay.element_states.has(Elemental.State.WET)).is_false()   # dry on the live board
	var attack := shooter.get_fired_attack()
	assert_bool(Conduction.arc_cells(shooter, attack, pond, board).has(Vector2i(2, 0))).is_false()
	assert_bool(Conduction.arc_cells(shooter, attack, pond, board, plan.hypo).has(Vector2i(2, 0))).is_true()
