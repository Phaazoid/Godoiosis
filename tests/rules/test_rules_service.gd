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

	var victims := RulesService.gather_attack_victims(attacker, [Vector2i(1, 0), Vector2i(0, 1)], _board())

	assert_array(victims).contains([enemy])
	assert_array(victims).not_contains([ally])

func test_gather_victims_includes_allies_when_weapon_hits_allies() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1))
	(attacker.get_equipped_weapon() as WeaponData).hits_allies = true

	var victims := RulesService.gather_attack_victims(attacker, [Vector2i(0, 1)], _board())

	assert_array(victims).contains([ally])
