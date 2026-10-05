# A headless rescue picks its bank and reads the plan, as the game's does (#46).
#
# The game hands the player the bank a drowning body is hauled to (#116: MainActionMenu's tile pick
# over RulesService.rescue_landings), and offers a squadmate this pass will drop as a body (#124: the
# candidate query takes the squad's last resolve). PlaySession.rescue did neither: it always took the
# first bank and asked the live board. Every expectation here is derived from those two seams, never
# from a cell this file chose to call a bank.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const Bridge := preload("res://play/play_bridge.gd")

const PLAYER := Team.Faction.PLAYER

# The body lies in deep water beside the rescuer, so it cannot stand where it lies and the rescuer's
# dry neighbours are the banks. Neither cell is (0,0), which the bridge case below depends on.
const HERO_CELL := Vector2i(2, 2)
const BODY_CELL := Vector2i(3, 2)


func _data(unit_name: String) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, PLAYER)


func _flat_board(root_name: String) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	return b


# {session, hero, body, banks}: a downed ally in deep water, ejected the way a prior pass leaves one.
func _drowning() -> Dictionary:
	var b := _flat_board("HeadlessRescueRoot")
	BoardBuilder.paint_cell(b.grid, BODY_CELL, BoardBuilder.WATER_ATLAS)
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero"), HERO_CELL)
	var body: Unit = BoardBuilder.spawn(b, _data("Body"), BODY_CELL)
	BoardBuilder.arm(hero, 3)
	var sess = PlaySession.new(b)
	body.take_damage(body.get_current_hp())
	assert_bool(body.is_downed()).override_failure_message("fixture: the body did not go down").is_true()
	sess._process_downed_pending()
	var board: BoardContext = sess._board()
	assert_bool(RulesService.rescue_needs_a_pick(body, board)) \
		.override_failure_message("fixture: the body can stand where it lies, so there is no bank to pick") \
		.is_true()
	var banks: Array[Vector2i] = RulesService.rescue_landings(hero, body, board)
	assert_int(banks.size()).override_failure_message(
		"fixture: the rescuer needs more than one dry neighbour for a pick to mean anything").is_greater(1)
	return {"session": sess, "hero": hero, "body": body, "banks": banks}


func test_a_rescue_onto_a_chosen_bank_hauls_the_body_there() -> void:
	var f := _drowning()
	var sess = f.session
	var body: Unit = f.body
	var banks: Array[Vector2i] = f.banks
	# The LAST bank, never the first: a verb that ignored the landing would still land on [0].
	var chosen: Vector2i = banks[banks.size() - 1]

	var res: Dictionary = sess.rescue(sess.handle_for(f.hero), sess.handle_for(body), chosen)
	assert_bool(res.ok).override_failure_message("a legal bank was refused: %s" % str(res.get("error", ""))).is_true()
	assert_bool((sess.execute() as Dictionary).ok).override_failure_message("the rescue did not execute").is_true()

	assert_bool(body.movement.cell == chosen).override_failure_message(
		"the body came out at %s, not the bank that was named (%s)" % [str(body.movement.cell), str(chosen)]).is_true()
	assert_bool(body.is_active()).override_failure_message("the hauled body was not revived").is_true()


func test_a_landing_that_is_not_a_bank_is_refused_and_names_the_banks() -> void:
	var f := _drowning()
	var sess = f.session
	var hero: Unit = f.hero
	var body: Unit = f.body
	var banks: Array[Vector2i] = f.banks
	# The water itself: the one cell beside the rescuer the body can never be put down on.
	var bad: Vector2i = body.movement.cell
	assert_bool(banks.has(bad)).override_failure_message("fixture: the water reads as a bank").is_false()

	var res: Dictionary = sess.rescue(sess.handle_for(hero), sess.handle_for(body), bad)
	assert_bool(res.ok).override_failure_message("a rescue onto a cell that is not a bank was accepted").is_false()
	for bank: Vector2i in banks:
		assert_str(str(res.get("error", ""))).override_failure_message(
			"the refusal does not list the legal bank %s" % str(bank)).contains(str(bank))
	assert_bool(hero.has_main_action_queued()).override_failure_message("a refused rescue queued anyway").is_false()


func test_omitting_the_landing_takes_the_first_bank_and_names_the_others() -> void:
	var f := _drowning()
	var sess = f.session
	var body: Unit = f.body
	var banks: Array[Vector2i] = f.banks

	var res: Dictionary = sess.rescue(sess.handle_for(f.hero), sess.handle_for(body))
	assert_bool(res.ok).override_failure_message("a rescue with no bank named was refused: %s" % str(res.get("error", ""))).is_true()
	var summary := str(res.get("summary", ""))
	for bank: Vector2i in banks:
		assert_str(summary).override_failure_message(
			"the reply does not name the bank %s, so a caller cannot learn it had a choice" % str(bank)).contains(str(bank))
	assert_bool((sess.execute() as Dictionary).ok).override_failure_message("the rescue did not execute").is_true()
	assert_bool(body.movement.cell == banks[0]).override_failure_message(
		"an unnamed bank should be the first, as the AI takes it; the body is at %s" % str(body.movement.cell)).is_true()


# A rescue over a queued main DISPLACES it, as every headless main verb does (#662: the chokepoint
# displaces, and a headless cancel takes all of a unit's orders, so a refusal here would strand it).
func test_a_rescue_over_a_queued_main_displaces_it_like_every_headless_main_verb() -> void:
	var f := _drowning()
	var sess = f.session
	var hero: Unit = f.hero
	var revved: Dictionary = sess.rev(sess.handle_for(hero))
	assert_bool(revved.ok).override_failure_message("precondition: the rev did not queue: %s" % str(revved.get("error", ""))).is_true()

	var res: Dictionary = sess.rescue(sess.handle_for(hero), sess.handle_for(f.body))
	assert_bool(res.ok).override_failure_message("a rescue over a queued main was refused: %s" % str(res.get("error", ""))).is_true()
	assert_bool(hero.has_action_type_queued(BaseAction.ActionType.RESCUE)).override_failure_message(
		"the rescue is not in the queue").is_true()
	assert_bool(hero.has_action_type_queued(BaseAction.ActionType.REV)).override_failure_message(
		"the rev survived beside the rescue -- two main actions for one unit").is_false()


# #124: a squadmate still STANDING, whom this squad's own plan drops before the side channel runs.
func test_a_squadmate_the_plan_will_drop_is_a_legal_rescue() -> void:
	var b := _flat_board("PredictedDownRoot")
	var striker: Unit = BoardBuilder.spawn(b, _data("Striker"), Vector2i(1, 0))
	var victim: Unit = BoardBuilder.spawn(b, _data("Victim"), Vector2i(2, 0))
	var medic: Unit = BoardBuilder.spawn(b, _data("Medic"), Vector2i(3, 0))
	BoardBuilder.arm(striker, 1)
	(striker.get_equipped_weapon() as WeaponInstance).template.main_attack.hits_allies = true
	var sm: SquadManager = b.squad_manager
	sm.join_squad(victim, striker.squad)
	sm.join_squad(medic, striker.squad)
	victim.take_damage(victim.get_current_hp() - 1)
	var sess = PlaySession.new(b)

	var aimed: Dictionary = sess.queue_attack(sess.handle_for(striker), victim.movement.cell)
	assert_bool(aimed.ok).override_failure_message("precondition: the aim did not queue: %s" % str(aimed.get("error", ""))).is_true()
	var plan: ResolvedPlan = sess.squad_manager.resolved_plan_for(striker.squad)
	assert_object(plan).override_failure_message("fixture: the session holds no resolve for the squad").is_not_null()
	assert_that(PlanResolver.projected_lifecycle(victim, plan.hypo)) \
		.override_failure_message("fixture: the aim does not predict a DOWN").is_equal(Unit.LifecycleState.DOWNED)
	assert_bool(victim.is_active()).override_failure_message("fixture: the victim is already down").is_true()
	# Non-vacuity: the live rule refuses this body, so only the plan can be what makes it legal.
	assert_bool(RulesService.adjacent_downed_allies(medic, sess._board()).has(victim)) \
		.override_failure_message("fixture: the live board already offers the victim").is_false()

	var res: Dictionary = sess.rescue(sess.handle_for(medic), sess.handle_for(victim))
	assert_bool(res.ok).override_failure_message(
		"a squadmate the plan drops was refused headlessly, where the menu offers it: %s" % str(res.get("error", ""))).is_true()
	assert_bool((sess.execute() as Dictionary).ok).override_failure_message("the pass did not execute").is_true()
	assert_bool(victim.is_active()).override_failure_message("the same-pass rescue did not stand the victim back up").is_true()


# The bridge's _xy reads a missing x/y as (0,0), a real cell, so a rescue command that names no bank
# must not reach the session as a request for one. Driven through _dispatch on a real bridge object.
func test_a_bridge_rescue_without_x_y_names_no_bank() -> void:
	var f := _drowning()
	var sess = f.session
	var body: Unit = f.body
	var banks: Array[Vector2i] = f.banks
	assert_bool(banks.has(Vector2i.ZERO)).override_failure_message("fixture: (0,0) is a bank").is_false()
	var unit_h: String = sess.handle_for(f.hero)
	var body_h: String = sess.handle_for(body)
	var bridge = Bridge.new()   # a MainLoop: gdUnit's auto_free refuses one, so it is freed by hand below
	bridge._session = sess

	# Named, (0,0) IS a request -- and not a bank, so it is refused naming the real ones.
	var named: Dictionary = bridge._dispatch("rescue", {"unit": unit_h, "target": body_h, "x": 0, "y": 0})
	assert_bool(named.ok).override_failure_message("the bridge dropped an x/y it was given").is_false()
	var ack := str(named.text).get_slice("\n", 0)   # the reply's own line, before the preview under it
	assert_str(ack).override_failure_message("the refusal is not the landing's: %s" % ack).contains(str(banks[0]))

	var unnamed: Dictionary = bridge._dispatch("rescue", {"unit": unit_h, "target": body_h})
	assert_bool(unnamed.ok).override_failure_message(
		"a rescue naming no bank was refused through the bridge: %s" % str(unnamed.text)).is_true()
	bridge.free()

	assert_bool((sess.execute() as Dictionary).ok).override_failure_message("the rescue did not execute").is_true()
	assert_bool(body.movement.cell == banks[0]).override_failure_message(
		"the bridge asked for a bank nobody named; the body is at %s" % str(body.movement.cell)).is_true()
