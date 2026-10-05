# Contract guards for the Play API core (docs/play-api.md, #46 M2).
# Locks the two laws the headless executor must honor: preview == execution (Law #2),
# and preview/look-ahead never mutates live state. Plus the player-parity gates
# (off-faction units can't be ordered; end_turn hands control over).
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const BoardView := preload("res://play/board_view.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _board: Dictionary
var _session

func before_test() -> void:
	_board = BoardBuilder.build(self)            # adds a PlayRoot under the suite (active tree -> _ready fires)
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(-2, -2, 12, 12))
	var p := BoardBuilder.spawn(_board, _data("P1", PLAYER), Vector2i(0, 0))   # -> handle A
	var e := BoardBuilder.spawn(_board, _data("E1", ENEMY), Vector2i(2, 0))    # -> handle a
	BoardBuilder.arm(p, 6)
	BoardBuilder.arm(e, 4)
	_session = PlaySession.new(_board)

func _data(name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, fac)


# Law #2: the HP the preview promises is exactly what execution leaves behind.
func test_preview_equals_execution() -> void:
	_session.queue_move("A", Vector2i(1, 0))
	_session.queue_attack("A", Vector2i(2, 0))
	var prev: Dictionary = _session.preview()
	assert_bool(prev.ok).is_true()
	var atk: Dictionary = prev.plan.attacks[0]
	assert_int(atk.dmg).is_greater(0)

	var target: Unit = _session.unit_by_handle("a")
	var res: Dictionary = _session.execute()
	assert_bool(res.ok).is_true()
	assert_int(target.get_current_hp()).is_equal(atk.hp_after)

# Law #2 for a HEAL (#46). The headless executor used to land every hit as take_damage(damage), and a
# heal's resolved damage is 0 -- only heal_amount carries it -- so a queued heal restored nothing here
# while the game, and the preview, gave the HP back. Both hosts now land through AttackAction.land.
func test_a_queued_heal_restores_the_hp_the_preview_promised() -> void:
	var b: Dictionary = BoardBuilder.build(self, "HealRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var medic: Unit = BoardBuilder.spawn(b, _data("Medic", PLAYER), Vector2i(0, 0))
	var hurt: Unit = BoardBuilder.spawn(b, _data("Hurt", PLAYER), Vector2i(1, 0))
	BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(5, 5))
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 4
	template.main_attack.heals = true
	template.main_attack.hits_allies = true
	medic.add_item(WeaponInstance.make(template))
	hurt.unit_instance.stats[Stats.Stat.MHP] = 200
	hurt.set_current_hp(100)   # far under the cap, so the whole heal shows
	var sess = PlaySession.new(b)

	assert_bool(sess.queue_attack(sess.handle_for(medic), hurt.movement.cell).ok).override_failure_message(
			"fixture: the heal was refused").is_true()
	var prev: Dictionary = sess.preview()
	assert_bool(prev.ok).is_true()
	var promised: int = prev.plan.attacks[0].hp_after
	assert_int(promised).override_failure_message(
			"fixture: the preview promises no HP back, so this case could not see a dropped heal").is_greater(100)

	assert_bool(sess.execute().ok).is_true()
	assert_int(hurt.get_current_hp()).override_failure_message(
			"the headless executor left the healed ally at %d HP; the preview promised %d" % [hurt.get_current_hp(), promised]
			).is_equal(promised)


# A heal the max-HP cap clips says what it GAVE BACK, not what it was worth (#46). The log printed the
# heal's whole size, so a medic topping up a scratched ally read as restoring HP nobody received.
func test_a_capped_heal_logs_the_hp_it_restored() -> void:
	var b: Dictionary = BoardBuilder.build(self, "CappedHealRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var medic: Unit = BoardBuilder.spawn(b, _data("Medic", PLAYER), Vector2i(0, 0))
	var hurt: Unit = BoardBuilder.spawn(b, _data("Hurt", PLAYER), Vector2i(1, 0))
	BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(5, 5))
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 6
	template.main_attack.heals = true
	template.main_attack.hits_allies = true
	medic.add_item(WeaponInstance.make(template))
	hurt.set_current_hp(hurt.get_max_hp() - 2)
	var sess = PlaySession.new(b)

	assert_bool(sess.queue_attack(sess.handle_for(medic), hurt.movement.cell).ok).override_failure_message(
			"fixture: the heal was refused").is_true()
	var plan: ResolvedPlan = sess.squad_manager.resolved_plan_for(medic.squad)
	var heal: AttackAction = plan.attacks[0]
	assert_int(heal.resolved.heal_amount).override_failure_message(
			"fixture: the heal fits under the cap, so the cap clips nothing").is_greater(2)

	var events: Array = sess.execute().get("events", [])
	var line := "%s heals %s for 2" % [sess.handle_for(medic), sess.handle_for(hurt)]
	assert_bool(events.has(line)).override_failure_message(
			"the log did not say the heal gave back 2: %s" % str(events)).is_true()

# #33 lifecycle: a would-be-fatal hit UNDER the overkill ceiling DOWNS (not kills) — preview
# must say DOWNED and execution must leave the target alive at 1 HP, with its counter skipped.
# This is the exact gap the view layer had: it read hp<=0 as "DIES".
func test_sub_ceiling_lethal_hit_downs_and_skips_counter() -> void:
	var target: Unit = _session.unit_by_handle("a")
	target.take_damage(target.get_current_hp() - 5)   # whittle to 5 HP (survivable -> stays ACTIVE)
	assert_int(target.get_current_hp()).is_equal(5)
	assert_bool(target.is_active()).is_true()

	_session.queue_move("A", Vector2i(1, 0))           # adjacent to 'a' at (2,0)
	_session.queue_attack("A", Vector2i(2, 0))         # 11 dmg vs 5 HP: overkill 6 <= ceiling -> DOWN
	var prev: Dictionary = _session.preview()
	assert_bool(prev.ok).is_true()
	assert_int(prev.plan.attacks[0].lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)
	assert_int(prev.plan.counters.size()).is_greater(0)
	assert_bool(prev.plan.counters[0].skipped).is_true()   # a downed target can't strike back

	# the rendered view must say DOWNED (not "DIES"), and leaves the skipped counter out the way the
	# queue panel does (#46) -- the structured `counters` key above is where it still shows
	var pv: String = BoardView.render_preview(_session)
	assert_str(pv).contains("DOWNED")
	assert_str(pv).override_failure_message("a skipped counter was rendered:\n%s" % pv).not_contains("REACTION")

	var attacker: Unit = _session.unit_by_handle("A")
	var attacker_hp: int = attacker.get_current_hp()
	var res: Dictionary = _session.execute()
	assert_bool(res.ok).is_true()
	assert_bool(target.is_downed()).is_true()              # NOT dead
	assert_int(target.get_current_hp()).is_equal(1)        # clings at 1 HP
	# ...and the headless twin's Law #2 claim now covers a FELL, which it could not before #1002:
	# the preview threaded the ladder's raw arithmetic (negative here) while execution clung at 1,
	# so test_preview_equals_execution above could only ever be asserted on a survivable hit.
	assert_int(prev.plan.attacks[0].hp_after).override_failure_message(
			"the headless preview promised an HP the execution did not land on") \
			.is_equal(target.get_current_hp())
	assert_int(attacker.get_current_hp()).is_equal(attacker_hp)   # counter was skipped — no reprisal
	assert_str(BoardView.render_overview(_session)).contains("[DOWNED]")   # legend flags the body

# Look-ahead is pure: previewing (even twice) changes no live HP or position.
func test_preview_does_not_mutate_live_state() -> void:
	var target: Unit = _session.unit_by_handle("a")
	var attacker: Unit = _session.unit_by_handle("A")
	var hp_before: int = target.get_current_hp()
	var cell_before: Vector2i = attacker.movement.cell
	_session.queue_move("A", Vector2i(1, 0))
	_session.queue_attack("A", Vector2i(2, 0))
	_session.preview()
	_session.preview()
	assert_int(target.get_current_hp()).is_equal(hp_before)
	assert_bool(attacker.movement.cell == cell_before).is_true()

# Player parity (Law #3 spirit): you cannot order an off-faction unit.
func test_cannot_order_off_faction_unit() -> void:
	var res: Dictionary = _session.queue_move("a", Vector2i(2, 1))   # 'a' is ENEMY on the PLAYER turn
	assert_bool(res.ok).is_false()

# end_turn hands the active faction over, enabling the other side.
func test_end_turn_hands_over_control() -> void:
	assert_int(_session.active_faction()).is_equal(PLAYER)
	_session.end_turn()
	assert_int(_session.active_faction()).is_equal(ENEMY)
	var res: Dictionary = _session.queue_move("a", Vector2i(2, 1))
	assert_bool(res.ok).is_true()

# The headless twin plays an attack's gas into ITS store (#508): a deposit only the game executor
# applied would have the Play API and the game disagree about the board after a pass.
func test_an_attack_that_leaves_gas_leaves_it_on_the_headless_board_too() -> void:
	var attacker: Unit = _session.unit_by_handle("A")
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.gas_level = Gas.Level.MEDIUM
	_session.queue_move("A", Vector2i(1, 0))
	_session.queue_attack("A", Vector2i(2, 0))
	var res: Dictionary = _session.execute()
	assert_bool(res.ok).is_true()
	var field: GasField = _board.gas_field
	assert_int(field.level_at(Vector2i(2, 0), Gas.Kind.STEAM)).is_equal(Gas.Level.MEDIUM)

# ...and its round spreads it as the game's does: game._on_round_completed's twin, checked against
# the store's own forecast so nothing about the rule is pinned here.
func test_the_headless_round_spreads_the_gas_too() -> void:
	var field: GasField = _board.gas_field
	field.set_level(Vector2i(5, 5), Gas.Kind.STEAM, Gas.Level.THICK)
	var expected := field.next_round(_session._board())
	assert_int(expected.size()).override_failure_message("fixture: the round would spread nothing").is_greater(1)
	_session.end_turn()   # PLAYER -> ENEMY
	_session.end_turn()   # ENEMY -> PLAYER: the round wraps
	assert_int(field.cells().size()).override_failure_message("the headless round never ticked the gas").is_equal(expected.size())
	for cell: Vector2i in expected:
		assert_int(field.packed_at(cell)).is_equal(expected[cell])

# ...and its turn end soaks as the game's does (#508 PR 3): OrderExecutor.apply_end_of_turn_tiles'
# twin, through the same TurnBoundary list. The state and its level are read off the rules file.
func test_the_headless_turn_end_soaks_a_unit_standing_in_steam() -> void:
	var rules := GasRules.for_kind(Gas.Kind.STEAM)
	assert_int(rules.state).override_failure_message(
			"fixture: steam's rules name no state").is_not_equal(Elemental.State.NONE)
	var unit: Unit = _session.unit_by_handle("A")
	var field: GasField = _board.gas_field
	field.set_level(unit.movement.cell, Gas.Kind.STEAM, rules.state_from)
	var res: Dictionary = _session.end_turn()
	assert_bool(unit.element_states.has(rules.state)).override_failure_message(
			"the headless turn end never soaked the unit standing in steam").is_true()
	var events: Array = res.get("ai_events", [])
	assert_bool(events.any(func(line: Variant) -> bool:
			return str(line).contains(Elemental.state_display_name(rules.state)))) \
		.override_failure_message("the headless turn end soaked without saying so").is_true()

# ...and the headless PREVIEW forecasts it first, off the session's own board -- the Play API's half
# of Law #2, which reads its gas through that board and nowhere else.
func test_the_headless_preview_forecasts_the_soak_at_the_walks_end() -> void:
	var rules := GasRules.for_kind(Gas.Kind.STEAM)
	var field: GasField = _board.gas_field
	field.set_level(Vector2i(1, 0), Gas.Kind.STEAM, rules.state_from)
	_session.queue_move("A", Vector2i(1, 0))
	var prev: Dictionary = _session.preview()
	assert_bool(prev.ok).is_true()
	var rows: Array = prev.plan.tile_hits
	assert_int(rows.size()).override_failure_message(
			"the headless preview forecast no soak at the end of the walk").is_equal(1)
	if rows.size() != 1:
		return
	assert_str(str((rows[0] as Dictionary).get("actor"))).is_equal("A")

# The headless scenario loader: an in-memory ScenarioData round-trips onto a fresh board
# (file-independent, so it survives scenario renames).
func test_apply_scenario_restores_units_terrain_and_turn() -> void:
	var src: Dictionary = BoardBuilder.build(self, "SrcRoot")
	auto_free(src.root)
	BoardBuilder.paint_rect(src.grid, Rect2i(0, 0, 5, 5))
	var scenario := ScenarioData.new()
	scenario.tile_data = src.grid.tile_map_data
	scenario.active_faction = ENEMY
	scenario.gas = {Vector2i(1, 1): Gas.with_level(0, Gas.Kind.STEAM, Gas.Level.THICK)}   # the atmosphere rides the third load path too (#508)
	var entry := ScenarioUnitEntry.new()
	entry.unit_data = _data("Loaded", PLAYER)
	entry.cell = Vector2i(2, 3)
	scenario.unit_entries.append(entry)

	var dst: Dictionary = BoardBuilder.build(self, "DstRoot")
	auto_free(dst.root)
	var spawned: Array = await BoardBuilder.apply_scenario(dst, scenario)

	assert_int(spawned.size()).is_equal(1)
	var u: Unit = spawned[0]
	assert_bool(u.movement.cell == Vector2i(2, 3)).is_true()
	var sess = PlaySession.new(dst)
	assert_bool(sess.terrain_at(Vector2i(2, 3)).exists).is_true()
	# Locks the #71 int migration end-to-end: tileset int layer -> Terrain.Kind -> display name.
	assert_str(sess.terrain_at(Vector2i(2, 3)).type).is_equal("grass")
	assert_int(sess.active_faction()).is_equal(ENEMY)
	var gas: GasField = dst.gas_field
	assert_int(gas.level_at(Vector2i(1, 1), Gas.Kind.STEAM)).override_failure_message(
		"the headless loader dropped the gas field -- #103 one store along").is_equal(Gas.Level.THICK)

# #33 rescue loop: a unit picks up an ADJACENT DOWNED ally (a main action). After execute the
# ally is ACTIVE again at 1 HP — the other half of the down/rescue cycle the bridge now exposes.
func test_rescue_revives_adjacent_downed_ally() -> void:
	var b: Dictionary = BoardBuilder.build(self, "RescueRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var ally: Unit = BoardBuilder.spawn(b, _data("Ally", PLAYER), Vector2i(1, 0))
	BoardBuilder.arm(hero, 3)
	var sess = PlaySession.new(b)
	ally.take_damage(ally.get_current_hp())   # damage == HP: overkill 0 <= ceiling -> DOWNED at 1 hp
	assert_bool(ally.is_downed()).is_true()
	sess._process_downed_pending()            # eject to solo, as a prior turn's post-pass would
	var hero_h: String = sess.handle_for(hero)
	var ally_h: String = sess.handle_for(ally)

	var res: Dictionary = sess.rescue(hero_h, ally_h)
	assert_bool(res.ok).is_true()
	var exe: Dictionary = sess.execute()
	assert_bool(exe.ok).is_true()
	assert_bool(ally.is_active()).is_true()
	assert_int(ally.get_current_hp()).is_equal(1)

# Rescue rejects a healthy (non-downed) target — only bodies get picked up.
func test_rescue_rejects_a_healthy_target() -> void:
	var b: Dictionary = BoardBuilder.build(self, "RescueRoot2")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var ally: Unit = BoardBuilder.spawn(b, _data("Ally", PLAYER), Vector2i(1, 0))
	var sess = PlaySession.new(b)
	var res: Dictionary = sess.rescue(sess.handle_for(hero), sess.handle_for(ally))
	assert_bool(res.ok).is_false()

# Rev rides the generic side-channel tail (BaseAction.SIDE_CHANNEL_ORDER, #84): a queued Rev shows
# in the preview's side_actions and actually revs the equipped chainsword when executed headless
# (Law #2 parity).
func test_rev_previews_and_executes() -> void:
	var hero: Unit = _session.unit_by_handle("A")
	var weapon := hero.get_equipped_weapon() as ChainswordWeaponInstance
	assert_bool(weapon != null).is_true()
	assert_bool(weapon.is_revved()).is_false()
	var res: Dictionary = _session.rev("A")
	assert_bool(res.ok).is_true()
	var prev: Dictionary = _session.preview()
	assert_bool(prev.ok).is_true()
	assert_int(prev.plan.side_actions.size()).is_equal(1)
	assert_str(prev.plan.side_actions[0].type).is_equal("REV")
	_session.execute()
	assert_bool(weapon.is_revved()).is_true()

# A queued rescue rides the same generic side_actions list, target handle included.
func test_rescue_appears_in_side_actions() -> void:
	var b: Dictionary = BoardBuilder.build(self, "RescueDescribeRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var ally: Unit = BoardBuilder.spawn(b, _data("Ally", PLAYER), Vector2i(1, 0))
	var sess = PlaySession.new(b)
	ally.take_damage(ally.get_current_hp())
	sess._process_downed_pending()
	var res: Dictionary = sess.rescue(sess.handle_for(hero), sess.handle_for(ally))
	assert_bool(res.ok).is_true()
	var prev: Dictionary = sess.preview()
	assert_bool(prev.ok).is_true()
	assert_int(prev.plan.side_actions.size()).is_equal(1)
	assert_str(prev.plan.side_actions[0].type).is_equal("RESCUE")
	assert_str(prev.plan.side_actions[0].target).is_equal(sess.handle_for(ally))

# Squad management through the same SquadManager the player uses: join, then leave.
func test_frozen_water_reads_walkable_to_the_headless_view() -> void:
	# #109: terrain_at re-read the `walkable` tile flag itself, so it could not see tile STATE. A
	# FROZEN water tile — which BoardContext, and therefore queue_move, GroupMoveSolver and
	# knockback, all treat as crossable — rendered as `#` impassable in board_view while the rules
	# pathed straight across it. The headless VIEW contradicting the headless RULES is precisely
	# the Law #2 failure the Play API exists to surface, so the view now asks the board.
	var cell := Vector2i(5, 5)
	BoardBuilder.paint_cell(_board.grid, cell, BoardBuilder.WATER_ATLAS)
	assert_bool(_session.terrain_at(cell).walkable).is_false()
	# Deep water draws as deep water (#46), no longer as rock.
	assert_str(_glyph_at(cell)).is_equal(BoardView.GROUND["deep"][0])

	# terrain_states.apply IS the production write path — play_session._apply_cell_effects and
	# OrderExecutor both hand a resolved effect to exactly this call. Only the effect's source is
	# synthesized here; test_ice.gd covers deriving one from a real ICE hit.
	var freeze := ResolvedCellEffect.new()
	freeze.cell = cell
	freeze.states_added.assign([Terrain.TileState.FROZEN])
	_board.terrain_states.apply(freeze)

	assert_bool(_session.terrain_at(cell).walkable).is_true()
	assert_str(_glyph_at(cell)).is_equal(BoardView.GROUND["frozen"][0])

# #922: melting the ice under a unit drops it in, and the headless twin plays that where the game
# does -- when the deposits land, before any counter -- with the preview naming it first (Law #2).
func test_melting_the_ice_under_a_unit_sinks_it_headlessly_too() -> void:
	var b: Dictionary = BoardBuilder.build(self, "SinkRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var ice := Vector2i(2, 0)
	BoardBuilder.paint_cell(b.grid, ice, BoardBuilder.WATER_ATLAS)
	var freeze := ResolvedCellEffect.new()
	freeze.cell = ice
	freeze.states_added.assign([Terrain.TileState.FROZEN])
	(b.terrain_states as TerrainStateManager).apply(freeze)
	var sturdy := Stats.STAT_DEFAULTS.duplicate()
	sturdy[Stats.Stat.MHP] = 40
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(1, 0))
	var foe: Unit = BoardBuilder.spawn(b, UnitFactory.create_unit_data(sturdy, "Foe", ENEMY), ice)
	BoardBuilder.arm(hero, 3)
	BoardBuilder.arm(foe, 3)
	var fire: WeaponAttackData = (hero.get_equipped_weapon() as WeaponInstance).template.main_attack
	fire.elemental_damage_type = Elemental.Element.FIRE
	fire.targets = EquippableData.TargetMode.BOTH
	var sess = PlaySession.new(b)
	assert_bool(sess.queue_attack(sess.handle_for(hero), ice).ok).is_true()

	var prev: Dictionary = sess.preview()
	assert_bool(prev.ok).is_true()
	assert_int(prev.plan.attacks[0].lethality).override_failure_message(
			"fixture: the fire alone must leave the foe standing").is_equal(ResolvedOutcome.Lethality.NONE)
	assert_int(prev.plan.sinks.size()).is_equal(1)
	assert_str(prev.plan.sinks[0].actor).is_equal(sess.handle_for(foe))
	assert_str(prev.plan.sinks[0].lethality).is_equal("DOWNED")
	for counter: Dictionary in prev.plan.counters:
		assert_bool(counter.skipped).override_failure_message("a sunk unit still counters").is_true()

	var hero_hp := hero.get_current_hp()
	assert_bool(sess.execute().ok).is_true()
	assert_bool(foe.is_downed()).override_failure_message(
			"the headless twin left the foe standing on the water").is_true()
	assert_bool(foe.element_states.has(Elemental.State.WET)).is_true()
	assert_int(hero.get_current_hp()).is_equal(hero_hp)

# #1135: a map-only aim at a unit hits nobody and is still LEGAL -- the game's whiff policy never
# refuses a map-hitting aim (#47), and the twin asks that policy rather than "did it find a victim",
# which would refuse the very order the game accepts. The foe's HP is the Law #2 half.
func test_a_map_only_aim_at_a_unit_is_offered_accepted_and_hits_nobody() -> void:
	var b: Dictionary = BoardBuilder.build(self, "MapOnlyRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(1, 0))
	BoardBuilder.arm(hero, 3)
	BoardBuilder.arm(foe, 3)
	(hero.get_equipped_weapon() as WeaponInstance).template.main_attack.targets = EquippableData.TargetMode.MAP
	var sess = PlaySession.new(b)
	var hero_h: String = sess.handle_for(hero)

	var offered: Array[Vector2i] = []
	for aim: Dictionary in sess.legal_targets(hero_h).aims:
		offered.append(aim.cell)
	assert_array(offered).contains([Vector2i(1, 0)])
	assert_bool(sess.queue_attack(hero_h, Vector2i(1, 0)).ok).is_true()

	var hp := foe.get_current_hp()
	assert_bool(sess.execute().ok).is_true()
	assert_int(foe.get_current_hp()).is_equal(hp)

func test_join_and_leave_squad() -> void:
	var b: Dictionary = BoardBuilder.build(self, "SquadRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var lead: Unit = BoardBuilder.spawn(b, _data("Lead", PLAYER), Vector2i(0, 0))
	var mate: Unit = BoardBuilder.spawn(b, _data("Mate", PLAYER), Vector2i(1, 0))
	var sess = PlaySession.new(b)
	var lead_h: String = sess.handle_for(lead)
	var mate_h: String = sess.handle_for(mate)

	var joined: Dictionary = sess.join(mate_h, lead_h)
	assert_bool(joined.ok).is_true()
	assert_object(mate.squad).is_same(lead.squad)
	assert_bool(mate.has_squad()).is_true()

	var left: Dictionary = sess.leave(mate_h)
	assert_bool(left.ok).is_true()
	assert_bool(mate.has_squad()).is_false()

# #612: Scenario objectives, zones and lose conditions are retained and surfaced in the overview.
func test_scenario_objectives_and_zones_surface_in_overview() -> void:
	var src: Dictionary = BoardBuilder.build(self, "MissionRoot")
	auto_free(src.root)
	BoardBuilder.paint_rect(src.grid, Rect2i(0, 0, 8, 8))
	var scenario := ScenarioData.new()
	scenario.tile_data = src.grid.tile_map_data
	scenario.active_faction = PLAYER
	scenario.scenario_name = "test_mission"
	scenario.objectives.assign([MissionRules.Objective.EXTRACT, MissionRules.Objective.CAPTURE])
	scenario.zones = {
		"CapPoint": {
			"kind": ZoneManager.Kind.CAPTURE,
			"cells": [Vector2i(2, 2), Vector2i(2, 3)],
		},
		"ExitPoint": {
			"kind": ZoneManager.Kind.EXTRACTION,
			"cells": [Vector2i(5, 5)],
		},
	}
	scenario.round_limit = 8
	scenario.lose_conditions.assign([MissionRules.LoseCondition.ROUND_LIMIT])
	var entry := ScenarioUnitEntry.new()
	entry.unit_data = _data("Runner", PLAYER)
	entry.cell = Vector2i(1, 1)
	scenario.unit_entries.append(entry)

	var dst: Dictionary = BoardBuilder.build(self, "MissionDst")
	auto_free(dst.root)
	var spawned: Array = await BoardBuilder.apply_scenario(dst, scenario)
	assert_int(spawned.size()).is_equal(1)

	var sess = PlaySession.new(dst)
	assert_object(sess.scenario_data).is_same(scenario)
	assert_int(sess.objectives().size()).is_equal(2)
	assert_int(sess.round_limit()).is_equal(8)
	assert_int(sess.lose_conditions().size()).is_equal(1)
	assert_bool(sess.zones().has("CapPoint")).is_true()

	var text: String = BoardView.render_overview(sess)
	assert_str(text).contains("Mission: EXTRACT + CAPTURE")
	assert_str(text).contains("limit: 8 rounds")
	assert_str(text).contains("CAPTURE  \"CapPoint\"  (2,2) (2,3)")
	assert_str(text).contains("EXTRACT  \"ExitPoint\"  (5,5)")
	assert_str(text).contains("FAIL IF  Time ran out.")
	# Grid overlay marks capture 'C' and extraction 'E'
	assert_str(text).contains(".C")
	assert_str(text).contains(".E")
	assert_str(text).contains("C = capture zone")
	assert_str(text).contains("E = extract zone")



# --- A hole and the edge of the world are different answers (#875) -----------------------------

const HOLE_TILE := Vector2i(18, 2)   # the authored VOID tile ("hole") in TestTiles


# The terrain glyph the RENDERED board shows for `cell`, read back out of render_overview rather
# than off the private helper -- test_board_view_rune.gd's rule, so the assert covers the wire.
# The header's first column names the left edge, so this cannot drift if the bounds move.
func _glyph_at(cell: Vector2i) -> String:
	var header := ""
	var row := ""
	for line in BoardView.render_overview(_session).split("\n"):
		if header == "" and line.begins_with("      "):
			header = line
		elif line.begins_with("y=%3d " % cell.y):
			row = line
	if header == "" or row == "":
		return ""
	var first_x := int(header.substr(6, 3))
	return row.substr(6 + (cell.x - first_x) * 3 + 1, 1)


func test_erased_ground_inside_the_board_reads_as_a_hole_not_as_off_the_map() -> void:
	_board.grid.erase_cell(Vector2i(3, 3))
	assert_str(_session.terrain_at(Vector2i(3, 3)).type).is_equal("void")
	# ...and past the painted rect the map simply stops, which is the other half of the rule.
	assert_str(_session.terrain_at(Vector2i(40, 40)).type).is_equal("offmap")


# A hole is UNWALKABLE, so the glyph renderer's `#` branch used to swallow every VOID cell and draw
# a chasm as MASONRY -- which left TERRAIN_GLYPH's own "void" entry unreachable from the day it was
# written. Both spellings of a hole render as open space now; `#` keeps meaning "unwalkable tile
# with no glyph of its own".
func test_a_hole_renders_as_open_space_rather_than_as_a_wall() -> void:
	_board.grid.set_cell(Vector2i(3, 3), 0, HOLE_TILE)
	_board.grid.erase_cell(Vector2i(4, 3))
	assert_str(_glyph_at(Vector2i(3, 3))).is_equal(" ")
	assert_str(_glyph_at(Vector2i(4, 3))).is_equal(" ")
	# The control: ordinary grass still renders as itself, so this is not "everything went blank".
	assert_str(_glyph_at(Vector2i(5, 3))).is_equal(".")
