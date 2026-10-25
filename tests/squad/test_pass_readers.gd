# What a pass's own readers see (#1349, #1353, #1500). Inside one resolve, "where is this unit now?" has
# two answers: the pass's threaded one (PlanResolver.projected_position) and the PUBLISHED projection
# (get_projected_destination), which lets a walk beat a shove the pass landed after it and never holds
# a counter's shove. Every reader inside the pass must take the first. Each case here queues through
# the Play API's own doors, resolves, and where the claim is about execution, executes -- the shoves
# are real, never stamped by hand -- and compares the forecast with what the pass actually did.
#
# What it cannot see: the 3D board's ghosts (the projection is asserted, its drawing is not).
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


func _board(root_name: String) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	return b


func _spawn(b: Dictionary, unit_name: String, fac: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = BoardBuilder.spawn(b, _data(unit_name, fac), cell)
	unit.unit_instance.stats[Stats.Stat.MHP] = 200   # nobody here is meant to fall
	unit.set_current_hp(200)
	return unit


# One attack, range 1, that throws whatever it hits `knockback` tiles on -- squadmates included, the
# way the Air and Wind runes' Gust does. Built here, so no authored attack is pinned.
func _arm_shover(unit: Unit, knockback := 1) -> void:
	var shove := WeaponAttackData.new()
	shove.display_name = "Shove"
	shove.power = 1
	shove.knockback = knockback
	shove.hits_allies = true
	P.point(shove, 1, 1)
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = shove
	unit.add_item(WeaponInstance.make(t))


# A swing that can also stand watch, reaching two tiles.
func _arm_watcher(unit: Unit) -> void:
	var swing := WeaponAttackData.new()
	swing.display_name = "Swing"
	swing.power = 1
	swing.can_overwatch = true
	P.point(swing, 2, 1)
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = swing
	unit.add_item(WeaponInstance.make(t))


func _ignite(b: Dictionary, cell: Vector2i) -> void:
	var fire := ResolvedCellEffect.new()
	fire.cell = cell
	fire.states_added.assign([Terrain.TileState.BURNING])
	(b.terrain_states as TerrainStateManager).apply(fire)


func _forecast_for(sess, unit: Unit) -> TileHitAction:
	var squad: Squad = sess.squad_manager.active_squad
	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(squad, sess._board())
	for hit in plan.tile_hits:
		if hit.actor == unit and hit.resolved.damage > 0:
			return hit
	return null


# What the end-of-turn pass would burn NOW -- the rule both hosts' turn ends call.
func _burn_for(sess, unit: Unit) -> TileHitAction:
	for hit in TurnBoundary.tile_hits(sess.live_units(), sess.terrain_states, sess.gas_field,
			sess._weather(), unit.get_faction()):
		if hit.actor == unit and hit.resolved.damage > 0:
			return hit
	return null


func _shoves_of(plan: ResolvedPlan, unit: Unit) -> AttackAction:
	for atk in plan.attacks:
		if atk.target == unit and atk.resolved != null and atk.resolved.knockback_applied:
			return atk
	return null


# ==============================================================================
#  #1349 -- a walker a squadmate then shoves
# ==============================================================================

# THE case: walk to D, a squadmate's shove throws you onto fire. The pass lands the shove AFTER the
# walk, so the forecast, the projection and the end-of-turn burn all have to agree on the fire.
func test_a_walker_shoved_into_fire_is_forecast_where_it_lands() -> void:
	var b := _board("WalkThenShoveRoot")
	var pusher := _spawn(b, "Pusher", PLAYER, Vector2i(2, 3))
	var walker := _spawn(b, "Walker", PLAYER, Vector2i(0, 2))
	_arm_shover(pusher)
	b.squad_manager.join_squad(walker, pusher.squad)
	var walked_to := Vector2i(2, 2)
	var fire := Vector2i(2, 1)   # one tile on, the way the shove throws from below
	_ignite(b, fire)
	var sess = PlaySession.new(b)
	var p: String = sess.handle_for(pusher)
	var w: String = sess.handle_for(walker)
	assert_bool(sess.queue_move(w, walked_to).ok).override_failure_message("fixture: the walk was refused").is_true()
	var shot: Dictionary = sess.queue_attack(p, walked_to)
	assert_bool(shot.ok).override_failure_message("fixture: the shove was refused: %s" % str(shot)).is_true()

	var res: Dictionary = sess.preview()
	assert_bool(res.ok).override_failure_message("preview refused: %s" % str(res)).is_true()
	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(sess.squad_manager.active_squad, sess._board())
	var shove := _shoves_of(plan, walker)
	assert_object(shove).override_failure_message("fixture: the shove never reached the walker").is_not_null()
	var landed: Vector2i = shove.resolved.knockback_to
	assert_that(landed).override_failure_message("fixture: the shove did not throw onto the fire").is_equal(fire)

	assert_that(walker.get_projected_destination()).override_failure_message(
			"the walker is projected where it walked, not where the shove throws it").is_equal(landed)
	var forecast := _forecast_for(sess, walker)
	assert_object(forecast).override_failure_message(
			"END OF TURN says nothing for a walker the pass throws into fire").is_not_null()

	assert_bool(sess.execute().ok).is_true()
	assert_that(walker.movement.cell).is_equal(landed)
	var burn := _burn_for(sess, walker)
	assert_object(burn).override_failure_message("fixture: the end of turn does not burn the walker").is_not_null()
	assert_int(forecast.resolved.damage).override_failure_message(
			"the forecast and the burn name different numbers").is_equal(burn.resolved.damage)


# The same order of events, one verb along: a watcher a squadmate throws arms its watch where it
# LANDS, both in the resolve's stamp and on the live board after execute.
func test_a_watcher_shoved_after_its_walk_arms_where_it_lands() -> void:
	var b := _board("WatchThenShoveRoot")
	var pusher := _spawn(b, "Pusher", PLAYER, Vector2i(2, 3))
	var watcher := _spawn(b, "Watcher", PLAYER, Vector2i(0, 2))
	_arm_shover(pusher)
	_arm_watcher(watcher)
	b.squad_manager.join_squad(watcher, pusher.squad)
	var walked_to := Vector2i(2, 2)
	var aim := Vector2i(3, 1)   # in reach from the walk's end and from the landing alike
	var sess = PlaySession.new(b)
	var p: String = sess.handle_for(pusher)
	var w: String = sess.handle_for(watcher)
	assert_bool(sess.queue_move(w, walked_to).ok).is_true()
	assert_bool(sess.queue_attack(p, walked_to).ok).override_failure_message("fixture: the shove was refused").is_true()
	var armed: Dictionary = sess.overwatch(w, aim)
	assert_bool(armed.ok).override_failure_message("fixture: the watch was refused: %s" % str(armed)).is_true()

	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(sess.squad_manager.active_squad, sess._board())
	var landed: Vector2i = _shoves_of(plan, watcher).resolved.knockback_to
	assert_that(landed).override_failure_message("fixture: the shove left the watcher on its walk").is_not_equal(walked_to)
	var order: OverwatchAction = null
	for action in sess.squad_manager.active_squad.action_queue:
		if action is OverwatchAction:
			order = action
	assert_that(order.resolved_anchor).override_failure_message(
			"the watch anchors where the watcher walked, not where it was thrown").is_equal(landed)

	assert_bool(sess.execute().ok).is_true()
	assert_object(watcher.watch).override_failure_message("fixture: no watch went live").is_not_null()
	assert_that(watcher.watch.anchor_cell).is_equal(watcher.movement.cell)
	assert_that(watcher.movement.cell).is_equal(landed)


# A COUNTER throws the striker into fire. The projection never holds a counter's shove -- a newly
# queued aim lands before the counters, so publishing it would be wrong -- which makes this the case
# only the pass's own threaded cell can forecast.
func test_a_striker_a_counter_throws_into_fire_is_forecast_where_it_lands() -> void:
	var b := _board("CounterIntoFireRoot")
	var striker := _spawn(b, "Striker", PLAYER, Vector2i(1, 2))
	var foe := _spawn(b, "Foe", ENEMY, Vector2i(1, 1))
	BoardBuilder.arm(striker, 1)
	_arm_shover(foe)   # its counter is the shove
	var fire := Vector2i(1, 3)   # behind the striker, the way the counter throws
	_ignite(b, fire)
	var sess = PlaySession.new(b)
	assert_bool(sess.queue_attack(sess.handle_for(striker), foe.movement.cell).ok).override_failure_message(
			"fixture: the strike was refused").is_true()

	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(sess.squad_manager.active_squad, sess._board())
	var landed := Vector2i.MAX
	for ctr in plan.counters:
		if ctr.target == striker and ctr.resolved != null and ctr.resolved.knockback_applied:
			landed = ctr.resolved.knockback_to
	assert_that(landed).override_failure_message("fixture: the counter did not throw the striker onto the fire").is_equal(fire)
	var forecast := _forecast_for(sess, striker)
	assert_object(forecast).override_failure_message(
			"END OF TURN missed the fire a counter throws the striker into").is_not_null()

	assert_bool(sess.execute().ok).is_true()
	assert_that(striker.movement.cell).is_equal(fire)
	var burn := _burn_for(sess, striker)
	assert_object(burn).is_not_null()
	assert_int(forecast.resolved.damage).is_equal(burn.resolved.damage)


# A COUNTER shoves the rescuer off the body. The projection never holds a counter's shove, so only
# the pass can see this; the rescue must go red rather than preview green and fizzle at execute.
func test_a_rescue_whose_rescuer_a_counter_shoves_away_goes_red() -> void:
	var b := _board("CounterOffTheBodyRoot")
	var rescuer := _spawn(b, "Rescuer", PLAYER, Vector2i(1, 2))
	var striker := _spawn(b, "Striker", PLAYER, Vector2i(0, 1))
	var body := _spawn(b, "Body", PLAYER, Vector2i(2, 2))
	var foe := _spawn(b, "Foe", ENEMY, Vector2i(1, 1))
	BoardBuilder.arm(striker, 1)
	_arm_shover(foe)   # its counter is the shove
	b.squad_manager.join_squad(striker, rescuer.squad)
	body.take_damage(body.get_current_hp())
	assert_bool(body.is_downed()).override_failure_message("fixture: the body is not down").is_true()
	var sess = PlaySession.new(b)
	var r: String = sess.handle_for(rescuer)
	var s: String = sess.handle_for(striker)
	assert_bool(sess.queue_attack(s, foe.movement.cell).ok).override_failure_message("fixture: the strike was refused").is_true()
	var pickup: Dictionary = sess.rescue(r, sess.handle_for(body))
	assert_bool(pickup.ok).override_failure_message("fixture: the rescue was refused: %s" % str(pickup)).is_true()

	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(sess.squad_manager.active_squad, sess._board())
	var thrown := false
	for ctr in plan.counters:
		if ctr.target == rescuer and ctr.resolved != null and ctr.resolved.knockback_applied:
			thrown = not RescueAction.within_reach(ctr.resolved.knockback_to, body.movement.cell)
	assert_bool(thrown).override_failure_message(
			"fixture: the counter did not throw the rescuer out of reach of the body").is_true()

	var res: Dictionary = sess.preview()
	assert_bool(res.ok).override_failure_message(
			"a rescue the counter will shove away from the body previewed green").is_false()
	assert_bool(sess.execute().ok).override_failure_message("execute ran a rescue that can only fizzle").is_false()


# ==============================================================================
#  #1353 -- a bystander of the acting faction
# ==============================================================================

# Another squad's unit, already acted, thrown into fire by THIS plan: its burn is this plan's doing,
# so it is this squad's END OF TURN row (dev, 2026-10-21), and the burn at end of turn agrees.
func test_a_bystander_this_plan_throws_into_fire_gets_this_squads_row() -> void:
	var b := _board("BystanderRoot")
	var pusher := _spawn(b, "Pusher", PLAYER, Vector2i(2, 3))
	var bystander := _spawn(b, "Bystander", PLAYER, Vector2i(2, 2))
	var idler := _spawn(b, "Idler", PLAYER, Vector2i(6, 1))   # standing in old fire, nobody touches it
	_arm_shover(pusher)
	var fire := Vector2i(2, 1)
	_ignite(b, fire)
	_ignite(b, idler.movement.cell)
	bystander.squad.has_acted = true
	var sess = PlaySession.new(b)
	var p: String = sess.handle_for(pusher)
	assert_bool(sess.queue_attack(p, bystander.movement.cell).ok).override_failure_message(
			"fixture: the shove was refused").is_true()

	var res: Dictionary = sess.preview()
	assert_bool(res.ok).override_failure_message("preview refused: %s" % str(res)).is_true()
	var forecast := _forecast_for(sess, bystander)
	assert_object(forecast).override_failure_message(
			"END OF TURN names nobody for a same-faction unit outside the squad this plan throws into fire").is_not_null()
	assert_object(_forecast_for(sess, idler)).override_failure_message(
			"a bystander in old fire, untouched by this plan, got a row from it").is_null()

	assert_bool(sess.execute().ok).is_true()
	assert_that(bystander.movement.cell).override_failure_message("fixture: the shove missed the fire").is_equal(fire)
	var burn := _burn_for(sess, bystander)
	assert_object(burn).is_not_null()
	assert_int(forecast.resolved.damage).is_equal(burn.resolved.damage)


# ==============================================================================
#  #1500 -- a shove's flight and tumble meet bodies where the pass has them
# ==============================================================================
#
# Moves resolve as a block ahead of the attacks (R6), so by the time a shove lands every walk in the
# plan has happened. A body in the way is a body where the pass has it: a squadmate that walked out of
# the flight path has left, and one that walked into it is there.

# The hit on `unit`, shoved or not: a flight stopped before its first step applies no shove, and that
# is one of the answers these cases tell apart.
func _hit_on(plan: ResolvedPlan, unit: Unit) -> AttackAction:
	for atk in plan.attacks:
		if atk.target == unit and atk.resolved != null:
			return atk
	return null


# The mover joins the pusher's squad and walks; then the pusher shoves the foe. Both through the Play
# API's doors, the walk queued first.
func _walk_then_shove(b: Dictionary, pusher: Unit, mover: Unit, walk_to: Vector2i, foe: Unit):
	b.squad_manager.join_squad(mover, pusher.squad)
	var sess = PlaySession.new(b)
	var walk: Dictionary = sess.queue_move(sess.handle_for(mover), walk_to)
	assert_bool(walk.ok).override_failure_message("fixture: the walk was refused: %s" % str(walk)).is_true()
	var shot: Dictionary = sess.queue_attack(sess.handle_for(pusher), foe.movement.cell)
	assert_bool(shot.ok).override_failure_message("fixture: the shove was refused: %s" % str(shot)).is_true()
	return sess


func _hit_after_resolve(sess, foe: Unit) -> AttackAction:
	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(sess.squad_manager.active_squad, sess._board())
	var hit := _hit_on(plan, foe)
	assert_object(hit).override_failure_message("fixture: the shove never reached the foe").is_not_null()
	return hit


# A squadmate walks OUT of the cell beside the foe, and the shove throws the foe that way. The cell is
# empty by the time the shove lands, so the flight runs its full two tiles through it.
func test_a_shove_flies_through_a_cell_a_squadmate_walked_out_of() -> void:
	var b := _board("WalkedOutRoot")
	var pusher := _spawn(b, "Pusher", PLAYER, Vector2i(2, 6))
	var foe := _spawn(b, "Foe", ENEMY, Vector2i(2, 5))
	var mover := _spawn(b, "Mover", PLAYER, Vector2i(2, 4))   # in the flight path, until it walks
	_arm_shover(pusher, 2)
	var sess = _walk_then_shove(b, pusher, mover, Vector2i(3, 4), foe)

	var hit := _hit_after_resolve(sess, foe)
	assert_bool(hit.resolved.knockback_applied).override_failure_message(
			"the shove stopped dead against the cell the mover walked out of").is_true()
	var landed: Vector2i = hit.resolved.knockback_to
	assert_that(landed).override_failure_message(
			"the flight stopped short of an empty cell, at %s" % str(landed)).is_equal(Vector2i(2, 3))

	assert_bool(sess.execute().ok).is_true()
	assert_that(foe.movement.cell).is_equal(landed)


# A squadmate walks INTO the flight path. The flight halts short of it, rather than flying through
# the cell the squadmate is standing in by then.
func test_a_shove_halts_short_of_a_squadmate_that_walked_into_its_path() -> void:
	var b := _board("WalkedInRoot")
	var pusher := _spawn(b, "Pusher", PLAYER, Vector2i(2, 6))
	var foe := _spawn(b, "Foe", ENEMY, Vector2i(2, 5))
	var mover := _spawn(b, "Mover", PLAYER, Vector2i(3, 3))
	_arm_shover(pusher, 3)
	var walked_to := Vector2i(2, 3)   # the flight's second cell
	var sess = _walk_then_shove(b, pusher, mover, walked_to, foe)

	var hit := _hit_after_resolve(sess, foe)
	var landed: Vector2i = hit.resolved.knockback_to
	assert_that(landed).override_failure_message(
			"the flight did not halt short of the mover, landing at %s" % str(landed)).is_equal(Vector2i(2, 4))

	assert_bool(sess.execute().ok).is_true()
	assert_that(foe.movement.cell).is_equal(landed)
	assert_that(mover.movement.cell).is_equal(walked_to)


# The same walk onto the flight's LAST cell: the shove would land the foe on the mover. Nothing else in
# the plan refuses that, so the flight's own occupancy is the only thing between it and two bodies on
# one tile.
func test_a_shove_never_lands_on_a_squadmate_that_walked_onto_its_landing() -> void:
	var b := _board("WalkedOntoRoot")
	var pusher := _spawn(b, "Pusher", PLAYER, Vector2i(2, 6))
	var foe := _spawn(b, "Foe", ENEMY, Vector2i(2, 5))
	var mover := _spawn(b, "Mover", PLAYER, Vector2i(3, 3))
	_arm_shover(pusher, 2)
	var walked_to := Vector2i(2, 3)   # where the flight would end
	var sess = _walk_then_shove(b, pusher, mover, walked_to, foe)

	var hit := _hit_after_resolve(sess, foe)
	var landed: Vector2i = hit.resolved.knockback_to
	assert_that(landed).override_failure_message(
			"the shove landed the foe at %s, on the mover's cell or past it" % str(landed)).is_equal(Vector2i(2, 4))
	var res: Dictionary = sess.preview()
	assert_bool(res.ok).override_failure_message("preview refused: %s" % str(res)).is_true()

	assert_bool(sess.execute().ok).is_true()
	assert_that(foe.movement.cell).override_failure_message(
			"after execute the foe and the mover share a tile").is_not_equal(mover.movement.cell)
	assert_that(foe.movement.cell).is_equal(landed)


# The tumble asks the same question: a squadmate that walked out of the cell at the foot of a ramp has
# left it, so a foe shoved onto the ramp slides down into it. test_falls.gd's perpendicular-ramp board.
func test_a_tumble_slides_into_a_cell_a_squadmate_walked_out_of() -> void:
	var b := _board("TumbleWalkedOutRoot")
	(b.board_heights as BoardHeights).set_cell(Vector2i(3, 3), 0, Terrain.RampRise.NORTH)   # downhill is south
	var pusher := _spawn(b, "Pusher", PLAYER, Vector2i(1, 3))
	var foe := _spawn(b, "Foe", ENEMY, Vector2i(2, 3))
	var mover := _spawn(b, "Mover", PLAYER, Vector2i(3, 4))   # at the foot of the ramp, until it walks
	_arm_shover(pusher, 1)
	var sess = _walk_then_shove(b, pusher, mover, Vector2i(2, 4), foe)

	var hit := _hit_after_resolve(sess, foe)
	assert_bool(hit.resolved.knockback_applied).override_failure_message("fixture: the shove did not land").is_true()
	var landed: Vector2i = hit.resolved.knockback_to
	assert_that(landed).override_failure_message(
			"the tumble stopped at %s, short of the cell the mover walked out of" % str(landed)).is_equal(Vector2i(3, 4))

	assert_bool(sess.execute().ok).is_true()
	assert_that(foe.movement.cell).is_equal(landed)
