# Weapon routines (#726): the per-family AI stance -- what a signature mechanic asks the AI to hold
# back on. Two hooks, one consumer each: the Drill refuses to re-burrow a covered cell
# (allows_preparation) and the Springspear defers its Spring unless it catches a line or fells
# (defers_candidate). The two laws the seam rests on are pinned here as well: a deferred candidate
# is still TAKEN when it is the member's only one (#711 stays literal), and deferral is MEMBER-LOCAL
# (it never becomes a precedence across members in the joint loop). The partition itself -- every
# family declares a routine -- is tests/law/test_ai_weapon_routine_coverage.gd.
#
# Real terrain via board_builder, whose board carries a TerrainStateManager, so a COVER deposit is
# readable through board.cover_def_at -- the one read point the Drill rule uses. Unlike the sibling
# AI suites, _context passes that store through.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const ZONE := "post"
const STURDY := {Stats.Stat.MHP: 40}   # nothing here fells it, so the choice is about the line and the disarm


func _build_board(size := Rect2i(0, 0, 8, 4)) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, size)
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i, weapon: WeaponInstance, overrides: Dictionary = {}) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data(overrides, faction), cell)
	unit.equipped_weapon = weapon
	return unit


func _context(board: Dictionary, zones: ZoneManager = null) -> BoardContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	return BoardContext.new(board.grid, units, board.squad_manager, board.terrain_states, zones)


func _drill() -> WeaponInstance:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.DRILL
	t.main_attack = WeaponAttackData.new()
	t.main_attack.power = 3
	return WeaponInstance.make(t)


# The shipped Springspear's shape: Stab needs the spring, Spring needs AND spends it, and Spring is
# a two-cell line that hits allies.
func _springspear() -> WeaponInstance:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.SPRINGSPEAR
	var stab := WeaponAttackData.new()
	stab.display_name = "Stab"
	stab.power = 3
	stab.requires_readiness = true
	var spring := WeaponAttackData.new()
	spring.display_name = "Spring"
	spring.power = 5
	spring.requires_readiness = true
	spring.consumes_readiness = true
	spring.hits_allies = true
	P.line(spring, 2)
	t.main_attack = stab
	t.extra_attacks.append(spring)
	return WeaponInstance.make(t)


func _cover(board: Dictionary, cell: Vector2i) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.append(Terrain.TileState.COVER)
	board.terrain_states.apply(effect)


func _hold(unit: Unit) -> Squad:
	unit.squad.archetype = AIArchetype.Type.HOLD
	return unit.squad


func _types(squad: Squad) -> Array[int]:
	var out: Array[int] = []
	for action in squad.action_queue:
		out.append(action.action_type)
	return out


func _attacks(squad: Squad) -> Array[AttackAction]:
	var out: Array[AttackAction] = []
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.ATTACK:
			out.append(action as AttackAction)
	return out


func _fired_name(a: AttackAction) -> String:
	return a.fired_attack.display_name if a.fired_attack != null else ""


# --- Drill: a drill with nothing to hit digs in where it stands, once ---

func test_a_drill_with_nothing_to_hit_burrows() -> void:
	var board := _build_board()
	var digger := _spawn(board, ENEMY, Vector2i(2, 2), _drill())
	var squad := _hold(digger)
	var _far: Unit = _spawn(board, PLAYER, Vector2i(7, 2), H.make_weapon())   # beyond Gouge; Hold never moves

	HoldArchetype.take_squad_turn(squad, _context(board), board.squad_manager)

	assert_array(_types(squad)).contains_exactly([BaseAction.ActionType.BURROW])


func test_a_drill_does_not_burrow_a_cell_already_covered() -> void:
	# can_burrow() is unconditionally true, so without the rule an idle drill re-digs its own cover
	# every turn -- a no-op deposit, an order and a pacing beat spent on nothing.
	var board := _build_board()
	var digger := _spawn(board, ENEMY, Vector2i(2, 2), _drill())
	var squad := _hold(digger)
	var _far: Unit = _spawn(board, PLAYER, Vector2i(7, 2), H.make_weapon())
	_cover(board, Vector2i(2, 2))

	HoldArchetype.take_squad_turn(squad, _context(board), board.squad_manager)

	assert_array(squad.action_queue).is_empty()


func test_a_drill_asks_about_the_cell_it_ends_on_not_the_one_it_leaves() -> void:
	# The deposit lands on the projected destination (test_cover_lands_where_the_digger_ends_up), so
	# the rule reads the same cell: covered origin, open destination -> it digs. Reading
	# movement.cell instead refuses here -- and would re-dig a covered destination from an open one.
	var board := _build_board()
	var zones: ZoneManager = auto_free(ZoneManager.new())
	for x in range(0, 8):
		for y in range(0, 4):
			zones.paint_cell(ZONE, ZoneManager.Kind.PATROL, Vector2i(x, y))
	var digger := _spawn(board, ENEMY, Vector2i(0, 1), _drill())
	var squad: Squad = digger.squad
	squad.archetype = AIArchetype.Type.SENTRY
	squad.zone_name = ZONE
	squad.home_cell = Vector2i(0, 1)
	var _intruder: Unit = _spawn(board, PLAYER, Vector2i(7, 1), H.make_weapon())   # in the zone, beyond one move
	_cover(board, Vector2i(0, 1))

	SentryArchetype.take_squad_turn(squad, _context(board, zones), board.squad_manager)

	var types := _types(squad)
	assert_bool(types.has(BaseAction.ActionType.MOVE)) \
		.override_failure_message("expected the sentry to advance on the intruder: %s" % [str(types)]).is_true()
	assert_that(digger.get_projected_destination()).is_not_equal(Vector2i(0, 1))
	assert_bool(types.has(BaseAction.ActionType.BURROW)) \
		.override_failure_message("expected a burrow at the open destination: %s" % [str(types)]).is_true()


# --- Springspear: the spearman saves the spring for a line or a kill ---

func test_a_spear_stabs_a_lone_target_it_could_have_sprung() -> void:
	# Spring outdamages Stab and the score alone takes it every time; but a spent spring gates Stab
	# as well, so the next turn is a Spring Load. One sturdy target, no line, no kill: Stab.
	var board := _build_board()
	var spear := _spawn(board, ENEMY, Vector2i(1, 1), _springspear())
	var squad := _hold(spear)
	var _target: Unit = _spawn(board, PLAYER, Vector2i(2, 1), H.make_weapon(), STURDY)

	HoldArchetype.take_squad_turn(squad, _context(board), board.squad_manager)

	var attacks := _attacks(squad)
	assert_int(attacks.size()).is_equal(1)
	assert_str(_fired_name(attacks[0])).is_equal("Stab")


func test_a_spear_springs_a_line_of_two() -> void:
	var board := _build_board()
	var spear := _spawn(board, ENEMY, Vector2i(1, 1), _springspear())
	var squad := _hold(spear)
	var _near: Unit = _spawn(board, PLAYER, Vector2i(2, 1), H.make_weapon(), STURDY)
	var _behind: Unit = _spawn(board, PLAYER, Vector2i(3, 1), H.make_weapon(), STURDY)

	HoldArchetype.take_squad_turn(squad, _context(board), board.squad_manager)

	var attacks := _attacks(squad)
	assert_int(attacks.size()).is_equal(1)
	assert_str(_fired_name(attacks[0])).is_equal("Spring")


func test_a_spear_springs_to_fell() -> void:
	# "Fells" is the MARGINAL removal term: the extra power over Stab is what takes the target down.
	var board := _build_board()
	var spear := _spawn(board, ENEMY, Vector2i(1, 1), _springspear())
	var squad := _hold(spear)
	var target: Unit = _spawn(board, PLAYER, Vector2i(2, 1), H.make_weapon(), STURDY)
	target.set_current_hp(_stab_damage_against(target, spear, board) + 1)   # Stab leaves it standing; Spring does not

	HoldArchetype.take_squad_turn(squad, _context(board), board.squad_manager)

	var attacks := _attacks(squad)
	assert_int(attacks.size()).is_equal(1)
	assert_str(_fired_name(attacks[0])).is_equal("Spring")


func test_a_deferred_spring_is_still_taken_when_it_is_the_only_option() -> void:
	# The routine DEFERS, it never deletes (#711): a target only the line can reach gets the
	# disarming Spring, because the alternative is not attacking.
	var board := _build_board()
	var spear := _spawn(board, ENEMY, Vector2i(1, 1), _springspear())
	var squad := _hold(spear)
	var _target: Unit = _spawn(board, PLAYER, Vector2i(3, 1), H.make_weapon(), STURDY)   # two cells: Spring's reach, not Stab's

	HoldArchetype.take_squad_turn(squad, _context(board), board.squad_manager)

	var attacks := _attacks(squad)
	assert_int(attacks.size()).is_equal(1)
	assert_str(_fired_name(attacks[0])).is_equal("Spring")


func test_deferral_is_member_local_never_a_precedence_across_members() -> void:
	# A deferred Spring is this member's whole option set, so in the joint loop it competes at its
	# full score and is queued FIRST, ahead of a squadmate's countered Slash. Threading "deferred"
	# through _Scored would make the Slash win round 1 -- the cross-member tier #720 deleted, with
	# one family's routine reordering another family's swing.
	var board := _build_board()
	var spear := _spawn(board, ENEMY, Vector2i(1, 2), _springspear())
	var sword := _spawn(board, ENEMY, Vector2i(1, 0), H.make_weapon())
	board.squad_manager.join_squad(sword, spear.squad)
	var squad := _hold(spear)
	var _line_target: Unit = _spawn(board, PLAYER, Vector2i(3, 2), H.make_weapon(), STURDY)    # Spring only; cannot answer from two away
	var _sword_target: Unit = _spawn(board, PLAYER, Vector2i(2, 0), H.make_weapon(), STURDY)   # adjacent to the sword, and counters it

	HoldArchetype.take_squad_turn(squad, _context(board), board.squad_manager)

	var attacks := _attacks(squad)
	assert_int(attacks.size()).is_equal(2)
	assert_object(attacks[0].actor).is_same(spear)
	assert_str(_fired_name(attacks[0])).is_equal("Spring")


# What one Stab from `attacker` does to `target` on this board, read off the same resolver the AI
# scores with -- so the "fells" fixture is set by the game's own arithmetic, not a guessed number.
func _stab_damage_against(target: Unit, attacker: Unit, board: Dictionary) -> int:
	attacker.active_attack = attacker.get_default_attack()
	var probe := AttackAction.declare(attacker, attacker.movement.cell, target.movement.cell)
	attacker.active_attack = null
	var one: Array[BaseAction] = [probe]
	var plan: ResolvedPlan = board.squad_manager.resolve_hypothetical(attacker.squad, one, _context(board),
			ReactionCatalog.get_all(), TerrainReactionCatalog.get_all())
	var dealt := 0
	for row in plan.attacks:
		if row.target == target and row.resolved != null:
			dealt += row.resolved.damage
	board.squad_manager.resolve_plan(attacker.squad, _context(board), ReactionCatalog.get_all(), TerrainReactionCatalog.get_all())
	return dealt
