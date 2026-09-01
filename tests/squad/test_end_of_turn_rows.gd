# The END OF TURN forecast (#419): a tile that will damage a unit when its faction's turn ends
# grows its own derived queue row, read off where the pass LEAVES that unit.
#
# The hop under test is the one nothing else covers. tests/terrain/test_burning_damage.gd owns what
# the end-of-turn pass DOES (and, since #419, that the forecast names the same number); the panel
# draws whatever entries it is handed. Between them sit PlanResolver.resolve_tile_hits and
# ActionQueueDisplayEntry.build_for, and neither was ever asked whether a burn reaches a row.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const FIRE := Vector2i(3, 0)
const STOUT := {Stats.Stat.MHP: 60}   # survives a burn, so a rung assertion means what it says

var _sm: SquadManager
var _states: TerrainStateManager


func before_test() -> void:
	_sm = H.make_manager(self)
	_states = auto_free(TerrainStateManager.new())


func after_test() -> void:
	await await_idle_frame()   # #473: settle before gdUnit4 counts orphans


func _ignite(cell: Vector2i, state := Terrain.TileState.BURNING) -> void:
	_states.apply(_deposit(cell, state))


func _deposit(cell: Vector2i, state: Terrain.TileState) -> ResolvedCellEffect:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([state])
	return effect


func _board(units_in: Array) -> BoardContext:
	var units: Array[Unit] = []
	units.assign(units_in)
	return BoardContext.new(_sm.grid, units, _sm, _states)


func _walk(unit: Unit, dest: Vector2i) -> MoveAction:
	var path: Array[Vector2i] = []
	for x in range(unit.movement.cell.x, dest.x + 1):
		path.append(Vector2i(x, dest.y))
	var move := MoveAction.new()
	move.init(unit, path, null)
	return move


func _hit_for(plan: ResolvedPlan, unit: Unit) -> TileHitAction:
	for hit in plan.tile_hits:
		if hit.actor == unit:
			return hit
	return null


# ==============================================================================
#  Who the forecast is about
# ==============================================================================

func test_a_walk_that_ends_in_fire_grows_a_row_naming_the_unit_and_the_damage() -> void:
	_ignite(FIRE)
	var walker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), STOUT, false)
	walker.squad._queue_action(_walk(walker, FIRE))

	var plan := _sm.resolve_plan(walker.squad, _board([walker]))

	var hit := _hit_for(plan, walker)
	assert_object(hit).override_failure_message(
			"a walk that ends on a burning tile said nothing").is_not_null()
	assert_int(hit.resolved.damage).is_equal(Terrain.BURNING_TILE_DAMAGE)
	assert_int(hit.resolved.hp_before).is_equal(walker.get_current_hp())
	assert_object(hit.get_action_icon()).override_failure_message(
			"the row has no icon for the tile").is_not_null()


# The whole reason this is a SECTION and not a row indented under MOVE: a unit that stands still in
# fire burns exactly as hard, and has no move for a consequence to hang off.
func test_a_unit_that_never_moved_still_gets_its_row() -> void:
	_ignite(FIRE)
	var stander := H.spawn_solo(self, _sm, PLAYER, FIRE, STOUT, false)

	var plan := _sm.resolve_plan(stander.squad, _board([stander]))

	assert_object(_hit_for(plan, stander)).override_failure_message(
			"a unit standing in fire with no orders was left out of the forecast").is_not_null()


# The end-of-turn pass burns the ACTING faction alone, so an enemy standing in fire is not this
# squad's business -- that happens at the end of THEIR turn, on THEIR panel.
func test_an_enemy_standing_in_the_same_fire_is_not_forecast_here() -> void:
	_ignite(FIRE)
	var player := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), STOUT, false)
	var enemy := H.spawn_solo(self, _sm, ENEMY, FIRE, STOUT, false)

	var plan := _sm.resolve_plan(player.squad, _board([player, enemy]))

	assert_int(plan.tile_hits.size()).override_failure_message(
			"an enemy's own end-of-turn burn was forecast onto the player's queue").is_equal(0)


# ==============================================================================
#  What it reads
# ==============================================================================

# Cell effects only reach the store at EXECUTION, so a forecast reading the live store alone misses
# the fire this very pass is about to light -- your own fireball landing under your own squadmate.
func test_the_forecast_sees_a_fire_this_pass_is_about_to_light() -> void:
	var stander := H.spawn_solo(self, _sm, PLAYER, FIRE, STOUT, false)
	var plan := ResolvedPlan.new()
	plan.cell_effects.append(_deposit(FIRE, Terrain.TileState.BURNING))

	PlanResolver.resolve_tile_hits(plan, stander.squad, plan.hypo, _board([stander]))

	assert_object(_hit_for(plan, stander)).override_failure_message(
			"the forecast read the live store and missed the fire this pass lights").is_not_null()


# ...and the mirror image, which is the same fold read the other way: a pass that DOUSES the tile
# leaves nothing to forecast.
func test_a_fire_this_pass_puts_out_is_not_forecast() -> void:
	_ignite(FIRE)
	var stander := H.spawn_solo(self, _sm, PLAYER, FIRE, STOUT, false)
	var plan := ResolvedPlan.new()
	var douse := ResolvedCellEffect.new()
	douse.cell = FIRE
	douse.states_removed.assign([Terrain.TileState.BURNING])
	plan.cell_effects.append(douse)

	PlanResolver.resolve_tile_hits(plan, stander.squad, plan.hypo, _board([stander]))

	assert_int(plan.tile_hits.size()).override_failure_message(
			"the forecast burned a unit standing on a fire this pass puts out").is_equal(0)


# ==============================================================================
#  The rung it predicts
# ==============================================================================

# Burn is a damage source like any other and the end-of-turn pass has no is_active filter (#191),
# so the forecast must not add one either.
func test_a_downed_body_in_fire_forecasts_a_kill() -> void:
	_ignite(FIRE)
	var body := H.spawn_solo(self, _sm, PLAYER, FIRE, STOUT, false)
	body.force_down()

	var plan := _sm.resolve_plan(body.squad, _board([body]))

	var hit := _hit_for(plan, body)
	assert_object(hit).is_not_null()
	assert_int(hit.resolved.lethality).override_failure_message(
			"a downed body sitting in fire was forecast to survive its own turn end") \
		.is_equal(ResolvedOutcome.Lethality.KILLED)


# The burn starts from the HP the PASS leaves, not the HP the board holds (R4) — which is also what
# pins the forecast's slot at the END of resolve_plan, after the counters it has to see.
func test_the_burn_starts_from_the_hp_the_pass_leaves_not_the_live_one() -> void:
	_ignite(FIRE)
	var attacker := H.spawn_solo(self, _sm, PLAYER, FIRE, STOUT, true, 3)
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0), STOUT, true, 4)
	attacker.squad._queue_action(H.stamped_attack(attacker, enemy))

	var plan := _sm.resolve_plan(attacker.squad, _board([attacker, enemy]))

	assert_int(PlanResolver.projected_hp(attacker, plan.hypo)).override_failure_message(
			"precondition: no counter landed, so there is no pass damage to thread") \
		.is_less(attacker.get_current_hp())
	var hit := _hit_for(plan, attacker)
	assert_object(hit).is_not_null()
	assert_int(hit.resolved.hp_before).override_failure_message(
			"the burn was forecast from LIVE hp, ignoring the counter this same pass lands") \
		.is_less(attacker.get_current_hp())


# The side-channel tail runs AFTER everything the hypo threads, so a queued Rescue's revive is
# invisible to it -- and a DOWNED reading turns an ordinary burn into a kill. R9: a plan that would
# diverge from execution is redesigned until the resolver can predict it.
func test_a_body_this_pass_rescues_is_forecast_standing_not_dead() -> void:
	_ignite(FIRE)
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), STOUT, false)
	var body := H.spawn_solo(self, _sm, PLAYER, FIRE, STOUT, false)
	_sm.join_squad(body, rescuer.squad)
	body.force_down()
	var rescue := RescueAction.new()
	rescue.init(rescuer, body, body.movement.cell)   # ordinary ground: the body stays where it lies
	rescuer.squad._queue_action(rescue)

	var plan := _sm.resolve_plan(rescuer.squad, _board([rescuer, body]))

	var hit := _hit_for(plan, body)
	assert_object(hit).override_failure_message(
			"the rescued body got no burn row at all").is_not_null()
	assert_int(hit.resolved.lethality).override_failure_message(
			"the forecast killed a body this same pass stands back up") \
		.is_not_equal(ResolvedOutcome.Lethality.KILLED)


# ==============================================================================
#  Where the row lands
# ==============================================================================

# LAST, because it happens last -- after every order in the queue, which is the pass's clock. And
# undraggable, or the player could sequence a consequence nobody ordered.
func test_the_row_closes_the_panel_in_its_own_section_and_cannot_be_dragged() -> void:
	# A walk AND an attack that draws a counter, so the panel really has a REACTION section to be
	# ordered against -- without one the "last section" assertion passes on a board that has none.
	_ignite(FIRE)
	var walker := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), STOUT, true, 3)
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0), STOUT, true, 4)
	walker.squad._queue_action(_walk(walker, FIRE))
	walker.squad._queue_action(H.stamped_attack(walker, enemy))
	var plan := _sm.resolve_plan(walker.squad, _board([walker, enemy]))

	var entries := ActionQueueDisplayEntry.build_for(walker.squad, plan)

	var headers: Array[String] = []
	var heading := ""
	var rows := 0
	for entry: ActionQueueDisplayEntry in entries:
		if entry.entry_type == ActionQueueDisplayEntry.EntryType.HEADER:
			heading = entry.label
			headers.append(entry.label)
		elif entry.entry_type == ActionQueueDisplayEntry.EntryType.ACTION and entry.action is TileHitAction:
			rows += 1
			assert_str(heading).override_failure_message(
					"the burn row landed under the wrong section").is_equal("END OF TURN")
			assert_bool(entry.action.is_reorderable()).override_failure_message(
					"the burn row is draggable -- the player could sequence a consequence").is_false()
	assert_int(rows).override_failure_message("the burn never reached the panel").is_equal(1)
	assert_bool(headers.has("REACTION")).override_failure_message(
			"precondition: no counter was drawn, so there is no later section to order against") \
		.is_true()
	assert_str(headers[-1]).override_failure_message(
			"END OF TURN is not the last section -- it happens after everything in the queue") \
		.is_equal("END OF TURN")
