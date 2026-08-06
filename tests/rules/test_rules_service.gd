# Parity guard for the rules extracted from game.gd into RulesService (M1, docs/play-api.md, #46).
# Movement-reach over terrain is covered in-game now and by the headless board in M2; here we
# lock the node-graph rules that run grid-free: path reconstruction and victim gathering.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _board() -> BoardContext:
	var units: Array[Unit] = []
	for squad in _sm.squads:
		for member in squad.get_members():
			if not units.has(member):
				units.append(member)
	return BoardContext.new(_sm.grid, units, _sm)

func test_reconstruct_path_walks_came_from_back_to_start() -> void:
	var came_from := {
		Vector2i(0, 0): Vector2i(0, 0),
		Vector2i(1, 0): Vector2i(0, 0),
		Vector2i(2, 0): Vector2i(1, 0),
	}
	var path := RulesService.reconstruct_path(came_from, Vector2i(0, 0), Vector2i(2, 0))
	assert_array(path).is_equal([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])

func test_gather_victims_picks_enemies_not_allies() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1))

	var victims := RulesService.gather_attack_victims(attacker, [Vector2i(1, 0), Vector2i(0, 1)], _board(), attacker.get_fired_attack())

	assert_array(victims).contains([enemy])
	assert_array(victims).not_contains([ally])

func test_gather_victims_includes_allies_when_weapon_hits_allies() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1))
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.hits_allies = true

	# The flag is read off the attack passed in, not off the attacker (#102).
	var victims := RulesService.gather_attack_victims(attacker, [Vector2i(0, 1)], _board(), attacker.get_fired_attack())

	assert_array(victims).contains([ally])

# --- self as a victim (#123) — a third category on the same axis as hits_allies ---

func test_attacker_is_not_a_victim_of_itself_by_default() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var attack := attacker.get_fired_attack()

	assert_bool(RulesService.is_attack_victim(attacker, attacker, attack)).is_false()

func test_attacker_is_a_victim_of_itself_when_hits_self() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var attack := attacker.get_fired_attack()
	attack.hits_self = true

	assert_bool(RulesService.is_attack_victim(attacker, attacker, attack)).is_true()

# hits_self and hits_allies are independent flags on the same predicate -- neither implies the
# other, which is what lets Heal (both true) differ from a plain self-buff (hits_self only) or an
# ally-splash weapon (hits_allies only, self still refused).
func test_hits_self_and_hits_allies_are_independent() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1))
	var attack := attacker.get_fired_attack()

	attack.hits_self = true
	attack.hits_allies = false
	assert_bool(RulesService.is_attack_victim(attacker, attacker, attack)).is_true()
	assert_bool(RulesService.is_attack_victim(attacker, ally, attack)).is_false()

	attack.hits_self = false
	attack.hits_allies = true
	assert_bool(RulesService.is_attack_victim(attacker, attacker, attack)).is_false()
	assert_bool(RulesService.is_attack_victim(attacker, ally, attack)).is_true()
