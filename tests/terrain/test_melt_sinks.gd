# #922: ice melting under a standing unit drops it into the water. The floor leaving is #116's
# drowning from the other side, so it reaches the same rung -- the water takes whatever is left, the
# unit comes up WET, and a rescue from the bank is the answer.
#
# WHEN is the dev's ruling (2026-09-27): a unit goes under when the pass's deposits land, straight
# after the volley and before any counter -- and a melt only a COUNTER makes, known only once the
# counters resolve, goes under when the pass settles. Both moments are ordering claims, so both are
# driven through the real resolve and the real execute_orders on the game scene.
#
# Boards are hand-painted on the fixture's grass (the content razor); water is the deep tile, which
# is what ice forms on.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const F := preload("res://tests/support/job_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const DEEP_WATER := Vector2i(5, 6)
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const ICE := Vector2i(3, 1)

var _main: Node
var game: Node2D
var _scout: JobData
var _scout_snap: Dictionary


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(10):
		for y in range(5):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	# Waterwalk has to come from somewhere and the fixtures carry no kit -- test_falls.gd's
	# arrangement: Scout's pool is forced to just WATERWALK for the duration.
	_scout = JobCatalog.get_job("scout")
	_scout_snap = F.snapshot(_scout)
	var ability := AbilityData.new()
	ability.id = Abilities.Id.WATERWALK
	_scout.ability_pool = [ability]
	await await_idle_frame()


func after_test() -> void:
	F.restore(_scout, _scout_snap)
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# --- fixture -------------------------------------------------------------------------------------

# Deep water at `cell`, iced over. Frozen BEFORE anyone is spawned on it, since spawn refuses a cell
# nothing may stand on.
func _ice(cell: Vector2i) -> void:
	(game.grid as BoardGrid).paint(cell, GRASS_SOURCE, DEEP_WATER)
	var freeze := ResolvedCellEffect.new()
	freeze.cell = cell
	freeze.states_added.assign([Terrain.TileState.FROZEN])
	game.terrain_states.apply(freeze)


func _spawn(faction: Team.Faction, cell: Vector2i, stats: Dictionary = {}, power := 3) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data(stats, faction), cell)
	assert_object(unit).override_failure_message("fixture: nothing spawned at %s" % [cell]).is_not_null()
	unit.equipped_weapon = H.make_weapon(power)
	return unit


# The unit's main attack carries `element` and lands where `targets` says.
func _imbue(unit: Unit, element: Elemental.Element,
		targets := EquippableData.TargetMode.BOTH) -> void:
	var attack: WeaponAttackData = (unit.get_equipped_weapon() as WeaponInstance).template.main_attack
	attack.elemental_damage_type = element
	attack.targets = targets


func _queue(attacker: Unit, cell: Vector2i) -> void:
	game.squad_manager.active_squad = attacker.squad
	var action := AttackAction.declare(attacker, attacker.movement.cell, cell)
	assert_bool(game.squad_manager.queue_action(attacker.squad, action)).override_failure_message(
			"fixture: the attack at %s never queued (%s)" % [cell, ", ".join(action.validation_errors)]) \
		.is_true()
	game.refresh_action_queue(attacker.squad)


func _plan(squad: Squad) -> ResolvedPlan:
	return game.squad_manager.resolve_plan(squad, game._board())


func _hit_on(plan: ResolvedPlan, victim: Unit) -> AttackAction:
	for attack in plan.attacks:
		if attack.target == victim:
			return attack
	return null


func _live_counter_by(plan: ResolvedPlan, reactor: Unit) -> CounterAttackAction:
	for counter in plan.counters:
		if counter.actor == reactor and not counter.resolved.skipped:
			return counter
	return null


func _sink_of(plan: ResolvedPlan, unit: Unit) -> SinkAction:
	for sink in plan.sinks:
		if sink.actor == unit:
			return sink
	return null


func _frozen(cell: Vector2i) -> bool:
	return (game.terrain_states as TerrainStateManager).has_state(cell, Terrain.TileState.FROZEN)


# A fire on the ice under an enemy, from beside it: the case most of the file builds on.
func _fire_on_the_ice() -> Dictionary:
	_ice(ICE)
	var foe := _spawn(ENEMY, ICE, {Stats.Stat.MHP: 30})
	var hero := _spawn(PLAYER, Vector2i(2, 1))
	_imbue(hero, Elemental.Element.FIRE)
	_queue(hero, ICE)
	return {"hero": hero, "foe": foe}


# --- the preview (Law #2) ------------------------------------------------------------------------

func test_a_fire_that_melts_the_ice_under_an_enemy_sinks_it() -> void:
	var s := _fire_on_the_ice()
	var foe: Unit = s.foe
	var plan := _plan((s.hero as Unit).squad)
	var hit := _hit_on(plan, foe)
	assert_object(hit).override_failure_message("fixture: the fire never reaches the enemy").is_not_null()
	assert_that(hit.resolved.lethality).override_failure_message(
			"fixture: the blow alone must leave the enemy standing").is_equal(ResolvedOutcome.Lethality.NONE)

	var sink := _sink_of(plan, foe)
	assert_object(sink).override_failure_message("the melt previews nothing for the unit on the ice") \
		.is_not_null()
	assert_that(sink.moment).is_equal(SinkAction.Moment.DEPOSITS_LAND)
	assert_that(sink.cell).is_equal(ICE)
	# The water takes whatever the blow left (#116), through the ordinary ladder.
	assert_int(sink.resolved.hp_before).is_equal(hit.resolved.target_hp_after)
	assert_int(sink.resolved.drown_damage).is_equal(hit.resolved.target_hp_after)
	assert_that(sink.resolved.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)
	assert_bool(sink.resolved.states_added.has(Elemental.State.WET)).override_failure_message(
			"a unit that went under comes up WET (#884)").is_true()
	assert_object(sink.cause).override_failure_message("the sinking does not name the fire that melted the ice") \
		.is_same(hit)
	assert_that(PlanResolver.projected_lifecycle(foe, plan.hypo)).is_equal(Unit.LifecycleState.DOWNED)


func test_the_sinking_hangs_under_the_attack_that_melted_the_ice() -> void:
	var s := _fire_on_the_ice()
	var squad: Squad = (s.hero as Unit).squad
	var plan := _plan(squad)
	var entries := ActionQueueDisplayEntry.build_for(squad, plan)
	var hit := _hit_on(plan, s.foe as Unit)
	var at := -1
	for i in entries.size():
		if entries[i].action == hit:
			at = i
	assert_int(at).override_failure_message("fixture: the fire has no row").is_greater_equal(0)
	assert_int(at + 1).override_failure_message("nothing follows the fire's row").is_less(entries.size())
	var next := entries[at + 1]
	assert_bool(next.action is SinkAction).override_failure_message(
			"the row under the fire is not the sinking it caused").is_true()
	assert_int(next.indent_level).is_equal(entries[at].indent_level + 1)


# The sinking happens when the deposits land, BEFORE the counters are derived, so a unit the melt
# sinks cannot hit back. Pinned against its own fixture first: on dry ground the same enemy DOES
# counter, or the skip below would pass on a board where nobody could.
func test_a_unit_the_melt_sinks_does_not_counter() -> void:
	var foe := _spawn(ENEMY, ICE, {Stats.Stat.MHP: 30})
	var hero := _spawn(PLAYER, Vector2i(2, 1))
	_imbue(hero, Elemental.Element.FIRE)
	_queue(hero, ICE)
	assert_object(_live_counter_by(_plan(hero.squad), foe)).override_failure_message(
			"fixture: on dry ground the enemy must counter").is_not_null()

	# Now the ground under it is ice, which the same fire melts.
	(game.grid as BoardGrid).paint(ICE, GRASS_SOURCE, DEEP_WATER)
	var freeze := ResolvedCellEffect.new()
	freeze.cell = ICE
	freeze.states_added.assign([Terrain.TileState.FROZEN])
	game.terrain_states.apply(freeze)
	var plan := _plan(hero.squad)
	assert_object(_sink_of(plan, foe)).override_failure_message("fixture: the enemy never sinks").is_not_null()
	assert_object(_live_counter_by(plan, foe)).override_failure_message(
			"a unit that went under when the ice melted still counters").is_null()


# The melt, not the blow: a blast that spares the unit standing there still takes the floor away --
# here the caster's own squadmate, whom an attack that does not hit allies passes over. So the water
# takes the WHOLE of its health, and it is the player's own fire that did it.
func test_a_blast_that_spares_the_unit_on_the_ice_still_sinks_it() -> void:
	_ice(ICE)
	var ally := _spawn(PLAYER, ICE, {Stats.Stat.MHP: 30})
	var hero := _spawn(PLAYER, Vector2i(2, 1))
	_imbue(hero, Elemental.Element.FIRE)
	(hero.get_equipped_weapon() as WeaponInstance).template.main_attack.hits_allies = false
	_queue(hero, ICE)
	var plan := _plan(hero.squad)
	assert_object(_hit_on(plan, ally)).override_failure_message(
			"fixture: the blast must spare the ally").is_null()
	var sink := _sink_of(plan, ally)
	assert_object(sink).override_failure_message("a unit the blast spared stood on in the water") \
		.is_not_null()
	assert_int(sink.resolved.drown_damage).is_equal(ally.get_current_hp())
	assert_that(sink.resolved.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)


func test_a_waterwalker_on_melting_ice_keeps_standing() -> void:
	var s := _fire_on_the_ice()
	var foe: Unit = s.foe
	foe.unit_instance.add_job("scout")
	assert_bool(foe.has_live_ability(Abilities.Id.WATERWALK)).override_failure_message(
			"fixture: the enemy must walk on water").is_true()
	assert_object(_sink_of(_plan((s.hero as Unit).squad), foe)).is_null()


# The deposits land as one batch, so a pass that melts the ice and then freezes it again leaves ice.
func test_ice_the_same_pass_refreezes_sinks_nobody() -> void:
	var s := _fire_on_the_ice()
	var hero: Unit = s.hero
	var froster := _spawn(PLAYER, Vector2i(4, 1))
	_imbue(froster, Elemental.Element.ICE)
	game.squad_manager.join_squad(froster, hero.squad)
	assert_int(hero.squad.members.size()).override_failure_message("fixture: the squad did not form") \
		.is_equal(2)
	_queue(froster, ICE)
	var plan := _plan(hero.squad)
	var melted := false
	for effect in plan.cell_effects:
		if effect.cell == ICE and effect.states_removed.has(Terrain.TileState.FROZEN):
			melted = true
	assert_bool(melted).override_failure_message("fixture: the fire must still melt the ice").is_true()
	assert_bool(plan.sinks.is_empty()).override_failure_message(
			"a pass that ends with the ice back sank somebody").is_true()


# --- execution plays it back ---------------------------------------------------------------------

# The wire: a resolved sinking that nobody plays is #103's shape exactly, so this reads the board the
# pass leaves rather than the plan.
func test_after_the_pass_the_sunk_unit_is_down_and_wet_in_the_water() -> void:
	var s := _fire_on_the_ice()
	var hero: Unit = s.hero
	var foe: Unit = s.foe
	var hero_hp := hero.get_current_hp()
	var predicted := _sink_of(_plan(hero.squad), foe)
	assert_object(predicted).override_failure_message("fixture: the preview has no sinking").is_not_null()

	await game.order_executor.execute_orders(hero)

	assert_bool(_frozen(ICE)).override_failure_message("fixture: the ice never melted").is_false()
	assert_bool(foe.is_downed()).override_failure_message(
			"the enemy is still standing on water it cannot stand on").is_true()
	assert_int(foe.get_current_hp()).is_equal(predicted.resolved.target_hp_after)
	assert_bool(foe.element_states.has(Elemental.State.WET)).is_true()
	assert_that(foe.movement.cell).is_equal(ICE)
	assert_int(hero.get_current_hp()).override_failure_message(
			"the sunk enemy's counter landed after all").is_equal(hero_hp)


# A melt only a COUNTER makes is known once the counters resolve, so the unit it strands goes under
# when the pass settles -- here the attacker, standing on the ice to swing.
func test_a_counter_that_melts_the_ice_under_the_attacker_sinks_it_when_the_pass_settles() -> void:
	_ice(ICE)
	var hero := _spawn(PLAYER, ICE, {Stats.Stat.MHP: 30})
	var foe := _spawn(ENEMY, Vector2i(4, 1), {Stats.Stat.MHP: 30})
	_imbue(foe, Elemental.Element.FIRE)
	_queue(hero, foe.movement.cell)
	var plan := _plan(hero.squad)
	var counter := _live_counter_by(plan, foe)
	assert_object(counter).override_failure_message("fixture: the enemy must counter").is_not_null()

	var sink := _sink_of(plan, hero)
	assert_object(sink).override_failure_message("the counter's melt left the attacker standing on water") \
		.is_not_null()
	assert_that(sink.moment).is_equal(SinkAction.Moment.PASS_END)
	assert_object(sink.cause).is_same(counter)
	assert_int(sink.resolved.drown_damage).is_equal(counter.resolved.target_hp_after)

	var entries := ActionQueueDisplayEntry.build_for(hero.squad, plan)
	var at := -1
	for i in entries.size():
		if entries[i].action == counter:
			at = i
	assert_int(at).override_failure_message("fixture: the counter has no row").is_greater_equal(0)
	assert_bool(at + 1 < entries.size() and entries[at + 1].action == sink).override_failure_message(
			"the sinking does not hang under the counter that melted the ice").is_true()

	await game.order_executor.execute_orders(hero)
	assert_bool(hero.is_downed()).override_failure_message(
			"the attacker is still standing on the water the counter opened").is_true()
	assert_bool(hero.element_states.has(Elemental.State.WET)).is_true()
