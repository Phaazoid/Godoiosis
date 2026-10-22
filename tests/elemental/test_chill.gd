# CHILLED — the first PAIRED element state: the marker on element_states answers "is it chilled"
# (reactions key on it), a paired StatEffect carries the DEX debuff AND is the state's clock
# (Elemental.paired_stat_mods / STATE_DEFAULT_TURNS). Unit's element-state doors own the lockstep.
# Resolver cases run against the AUTHORED catalog (ice_sets_chilled / ice_wet_deep_chill /
# fire_chilled_temp_shock .tres), so a bad enum int in the content fails here. The end-to-end
# case drives the headless Play API — the same SquadManager.resolve_plan + playback the game runs.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const BASE := 4
const CHILLED := Elemental.State.CHILLED
const WET := Elemental.State.WET

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

static func _authored(element: Elemental.Element, state: Elemental.State) -> ElementalReaction:
	for r in ReactionCatalog.get_all():
		if r.incoming_element == element and r.required_state == state:
			return r
	return null

func _attacker(element: Elemental.Element, cell: Vector2i) -> Unit:
	var u := H.spawn_solo(self, _sm, PLAYER, cell, {Stats.Stat.STR: 0}, true, BASE)
	(u.get_equipped_weapon() as WeaponInstance).template.main_attack.elemental_damage_type = element
	return u

func _resolve_single(attacker: Unit, target: Unit) -> AttackAction:
	var attack := H.stamped_attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)
	return attack

# --- The authored content -----------------------------------------------------------------------

func test_the_chill_reactions_are_authored() -> void:
	var base := _authored(Elemental.Element.ICE, Elemental.State.NONE)
	assert_object(base).is_not_null()
	assert_bool(base.add_states.has(CHILLED)).is_true()

	var deep := _authored(Elemental.Element.ICE, WET)
	assert_object(deep).is_not_null()
	assert_bool(deep.add_states.has(CHILLED)).is_true()
	assert_bool(deep.remove_states.has(WET)).is_true()          # the payoff spends the soak
	assert_int(deep.damage_bonus).is_greater(0)
	assert_int(int(deep.add_state_turns.get(CHILLED, 0))).is_greater(Elemental.STATE_DEFAULT_TURNS[CHILLED])

	var shock := _authored(Elemental.Element.FIRE, CHILLED)
	assert_object(shock).is_not_null()
	assert_bool(shock.remove_states.has(CHILLED)).is_true()     # cold-to-heat ends the chill
	assert_int(shock.damage_bonus).is_greater(0)

# --- Resolver: composition off the catalog --------------------------------------------------------

func test_ice_chills_a_dry_target_at_the_default_clock() -> void:
	var attacker := _attacker(Elemental.Element.ICE, Vector2i(0, 0))
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})

	var attack := _resolve_single(attacker, target)

	assert_int(attack.resolved.damage).is_equal(BASE)   # the base setter carries no damage change
	assert_bool(attack.resolved.states_added.has(CHILLED)).is_true()
	# No authored override -> no state_turns entry; playback falls back to the default clock.
	assert_bool(attack.resolved.state_turns.has(CHILLED)).is_false()

func test_ice_on_a_wet_target_deep_chills() -> void:
	# BOTH ice reactions fire on the pre-hit snapshot (E8): the base setter and the deep chill.
	# Damage composes additively; the CHILLED clock composes by MAX, so the authored override wins.
	var attacker := _attacker(Elemental.Element.ICE, Vector2i(0, 0))
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	target.add_element_state(WET)

	var attack := _resolve_single(attacker, target)

	var deep := _authored(Elemental.Element.ICE, WET)
	assert_int(attack.resolved.damage).is_equal(int(round(BASE + deep.damage_bonus)))
	assert_bool(attack.resolved.states_added.has(CHILLED)).is_true()
	assert_bool(attack.resolved.states_removed.has(WET)).is_true()
	assert_int(int(attack.resolved.state_turns.get(CHILLED, 0))).is_equal(int(deep.add_state_turns[CHILLED]))

func test_fire_on_a_chilled_target_is_temperature_shock() -> void:
	var attacker := _attacker(Elemental.Element.FIRE, Vector2i(0, 0))
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	target.add_element_state(CHILLED)

	var attack := _resolve_single(attacker, target)

	var shock := _authored(Elemental.Element.FIRE, CHILLED)
	assert_int(attack.resolved.damage).is_equal(int(round(BASE + shock.damage_bonus)))
	assert_bool(attack.resolved.states_removed.has(CHILLED)).is_true()
	# The meltwater wets the unit (#1423), and the same hit does not then dry it: every reaction is
	# matched against the states held BEFORE the hit (E8), and a Chilled unit is never Wet (#1092).
	assert_bool(attack.resolved.states_added.has(WET)).is_true()
	assert_bool(attack.resolved.fired_reactions.has(_authored(Elemental.Element.FIRE, WET))).is_false()

func _thaw_then(follow: Elemental.Element) -> Array[AttackAction]:
	var fire := _attacker(Elemental.Element.FIRE, Vector2i(0, 0))
	var second := _attacker(follow, Vector2i(0, 1))
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	target.add_element_state(CHILLED)
	var hits: Array[AttackAction] = [H.stamped_attack(fire, target), H.stamped_attack(second, target)]
	var plan := ResolvedPlan.new()
	plan.attacks.append_array(hits)
	PlanResolver.resolve(plan)
	return hits

# The combo the thaw opens: a shock later in the same pass sees the meltwater (E4).
func test_a_shock_after_the_thaw_electrocutes() -> void:
	var shock := _thaw_then(Elemental.Element.SHOCK)[1]

	var electrocute := _authored(Elemental.Element.SHOCK, WET)
	assert_bool(shock.resolved.fired_reactions.has(electrocute)).is_true()
	assert_int(shock.resolved.damage).is_equal(BASE + electrocute.damage_bonus)

# ...and a second fire hit dries it, the Quick Dry the first could not be.
func test_a_second_fire_hit_dries_the_meltwater() -> void:
	var dry := _thaw_then(Elemental.Element.FIRE)[1]

	var quick_dry := _authored(Elemental.Element.FIRE, WET)
	assert_bool(dry.resolved.fired_reactions.has(quick_dry)).is_true()
	assert_bool(dry.resolved.fired_reactions.has(_authored(Elemental.Element.FIRE, CHILLED))).is_false()
	assert_int(dry.resolved.damage).is_equal(int(round(BASE * quick_dry.damage_mult + quick_dry.damage_bonus)))
	assert_bool(dry.resolved.states_removed.has(WET)).is_true()

# --- The door pairing (unit level) ----------------------------------------------------------------

func test_chilling_pairs_a_dex_effect_with_the_marker() -> void:
	var u := H.spawn_unit(self, PLAYER, Vector2i.ZERO, {}, false)
	var dex_before := u.get_body_stat(Stats.Stat.DEX)

	u.add_element_state(CHILLED)

	assert_bool(u.element_states.has(CHILLED)).is_true()
	assert_bool(u.has_stat_effect_from(Elemental.state_effect_source(CHILLED))).is_true()
	assert_int(u.get_body_stat(Stats.Stat.DEX)).is_equal(dex_before + Elemental.CHILL_STAT_MODS[Stats.Stat.DEX])

func test_the_clock_expiring_ends_the_state() -> void:
	var u := H.spawn_unit(self, PLAYER, Vector2i.ZERO, {}, false)
	var dex_before := u.get_body_stat(Stats.Stat.DEX)
	u.add_element_state(CHILLED)

	for _i in Elemental.STATE_DEFAULT_TURNS[CHILLED] - 1:
		u.tick_stat_effects()
	assert_bool(u.element_states.has(CHILLED)).is_true()   # alive through the clock's last turn

	u.tick_stat_effects()
	assert_bool(u.element_states.has(CHILLED)).is_false()  # spent clock ends the state itself
	assert_int(u.get_body_stat(Stats.Stat.DEX)).is_equal(dex_before)

func test_removing_the_state_retires_the_effect() -> void:
	# The Temperature Shock shape one layer down: a reaction's remove_states lands on this door,
	# and the debuff must die WITH the marker or the pairing has drifted.
	var u := H.spawn_unit(self, PLAYER, Vector2i.ZERO, {}, false)
	var dex_before := u.get_body_stat(Stats.Stat.DEX)
	u.add_element_state(CHILLED)

	u.remove_element_state(CHILLED)

	assert_bool(u.element_states.has(CHILLED)).is_false()
	assert_bool(u.has_stat_effect_from(Elemental.state_effect_source(CHILLED))).is_false()
	assert_int(u.get_body_stat(Stats.Stat.DEX)).is_equal(dex_before)

func test_rechilling_refreshes_and_never_stacks() -> void:
	var u := H.spawn_unit(self, PLAYER, Vector2i.ZERO, {}, false)
	var dex_before := u.get_body_stat(Stats.Stat.DEX)
	var long_clock: int = Elemental.STATE_DEFAULT_TURNS[CHILLED] + 2

	u.add_element_state(CHILLED, long_clock)
	u.add_element_state(CHILLED)   # default clock, shorter — must not shorten or stack

	assert_int(u.get_body_stat(Stats.Stat.DEX)).is_equal(dex_before + Elemental.CHILL_STAT_MODS[Stats.Stat.DEX])
	var source := Elemental.state_effect_source(CHILLED)
	var remaining := 0
	var count := 0
	for effect in u.stat_effects:
		if effect.source_name == source:
			count += 1
			remaining = effect.turns_remaining
	assert_int(count).is_equal(1)
	assert_int(remaining).is_equal(long_clock)

func test_wet_carries_no_paired_effect() -> void:
	var u := H.spawn_unit(self, PLAYER, Vector2i.ZERO, {}, false)
	u.add_element_state(WET)
	assert_bool(u.stat_effects.is_empty()).is_true()

# --- The wire: authored content -> resolve -> playback -> door, on the headless twin --------------

func test_a_real_ice_attack_deep_chills_through_the_play_api() -> void:
	var b := BoardBuilder.build(self, "ChillRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(b, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Hero", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Foe", ENEMY), Vector2i(1, 0))
	# Board spawns carry no starting kit — arm the hero with a throwaway ice blade (null pattern
	# = adjacent reach), the test_knockback shape.
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = BASE
	template.main_attack.elemental_damage_type = Elemental.Element.ICE
	hero.add_item(WeaponInstance.make(template))
	foe.add_element_state(WET)
	var dex_wet := foe.get_body_stat(Stats.Stat.DEX)

	var sess = PlaySession.new(b)
	var res: Dictionary = sess.queue_attack(sess.handle_for(hero), Vector2i(1, 0))
	assert_bool(res.ok).is_true()
	sess.execute()

	assert_bool(foe.element_states.has(CHILLED)).is_true()
	assert_bool(foe.element_states.has(WET)).is_false()
	assert_int(foe.get_body_stat(Stats.Stat.DEX)).is_equal(dex_wet + Elemental.CHILL_STAT_MODS[Stats.Stat.DEX])
	# The authored deep-chill clock arrived through playback, not the default.
	var deep := _authored(Elemental.Element.ICE, WET)
	var source := Elemental.state_effect_source(CHILLED)
	var clock := -1
	for effect in foe.stat_effects:
		if effect.source_name == source:
			clock = effect.turns_remaining
	assert_int(clock).is_equal(int(deep.add_state_turns[CHILLED]))

# Temperature Shock's meltwater (#1423): the preview row says it before Execute, and playback lands it.
func test_a_real_fire_attack_thaws_a_chilled_unit_to_wet_through_the_play_api() -> void:
	var b := BoardBuilder.build(self, "ThawRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(b, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Hero", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Foe", ENEMY), Vector2i(1, 0))
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = BASE
	template.main_attack.elemental_damage_type = Elemental.Element.FIRE
	hero.add_item(WeaponInstance.make(template))
	foe.add_element_state(CHILLED)
	var dex_chilled := foe.get_body_stat(Stats.Stat.DEX)

	var sess = PlaySession.new(b)
	var res: Dictionary = sess.queue_attack(sess.handle_for(hero), Vector2i(1, 0))
	assert_bool(res.ok).is_true()
	var preview: Dictionary = sess.preview()
	assert_bool(preview.ok).is_true()
	var gains: Array = []
	var loses: Array = []
	for row: Dictionary in preview.plan.rows:
		if row.get("target", "") == sess.handle_for(foe) and row.has("gains"):
			gains = row["gains"]
			loses = row["loses"]
	assert_bool(gains.has(Elemental.state_display_name(WET))).is_true()
	assert_bool(loses.has(Elemental.state_display_name(CHILLED))).is_true()
	sess.execute()

	assert_bool(foe.element_states.has(WET)).is_true()
	assert_bool(foe.element_states.has(CHILLED)).is_false()
	assert_int(foe.get_body_stat(Stats.Stat.DEX)).is_equal(dex_chilled - Elemental.CHILL_STAT_MODS[Stats.Stat.DEX])
