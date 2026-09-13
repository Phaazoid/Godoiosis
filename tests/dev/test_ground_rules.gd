# The Tiles page's GROUND section (#902): a burnable tick and a burn-turns dial, reached from a tile
# and scoped to its KIND.
#
# NO CASE HERE WRITES TO Resources/. The create and delete DECISIONS are asserted where they are
# made -- which file, and what would be written into it -- and the dialog cases cancel, which is
# tests/dev/test_dev_tool_overwrite_guards.gd's own stated convention. What that leaves uncovered is
# the disk act itself, and DevWidgets.save_over already has its own suites.
extends GdUnitTestSuite


# NO FIXTURE. Every case here asks a static about authored content, so a board would be scenery --
# and the ONE case that needs a live board (the fuel_source re-wire) lives in test_game_knobs.gd
# instead, whose fixture is the Battle3D scene: the flat Main.tscn has no 3D host, so the Tiles page
# there reports "no 3D host" and every wire through it answers vacuously.
func _reactions() -> Array[TerrainReaction]:
	return TerrainReactionCatalog.get_all()


# --- WHICH FILE a tick acts on ------------------------------------------------------------------

# THE case this section exists for. TREE's ignition reaction is `Burning.tres` -- authored before the
# kind had a name to be named after -- so a path composed from the kind misses it entirely, and
# ticking TREE off would report success while every fence on the board went on burning.
func test_the_path_is_the_file_the_catalog_found_not_a_name_built_from_the_kind() -> void:
	var reactions := _reactions()
	var found := TerrainReactionCatalog.fuel_for_kind(Terrain.Kind.TREE, reactions)
	assert_object(found).override_failure_message(
		"TREE has no ignition reaction any more -- this case is vacuous, re-point it at a kind that burns"
		).is_not_null()

	var path := ObjectKnobs.ignition_path_for(Terrain.Kind.TREE, reactions)

	assert_str(path).override_failure_message(
		"the tick composed a name instead of using the file fuel_for_kind returned, so un-ticking TREE would delete nothing"
		).is_equal(found.resource_path)


# The composed name is for a file that does not exist yet, and only then.
func test_a_ground_with_no_reaction_gets_a_name_built_from_its_kind() -> void:
	var reactions := _reactions()
	assert_object(TerrainReactionCatalog.fuel_for_kind(Terrain.Kind.MUD, reactions)
		).override_failure_message("MUD burns now -- pick a kind that does not for this case").is_null()

	var path := ObjectKnobs.ignition_path_for(Terrain.Kind.MUD, reactions)

	assert_str(path).is_equal("res://Resources/TerrainReactions/MudIgnites.tres")


# --- What a NEW reaction is -------------------------------------------------------------------

# The constructor and the predicate are one pairing: a reaction the tick creates and fuel_for_kind
# cannot find is a tick that reports success and changes nothing.
func test_a_created_reaction_is_one_the_catalog_can_find() -> void:
	var made: Array[TerrainReaction] = [ObjectKnobs.make_ignition(Terrain.Kind.MUD)]

	assert_object(TerrainReactionCatalog.fuel_for_kind(Terrain.Kind.MUD, made)
		).override_failure_message(
		"make_ignition built something fuel_for_kind refuses, so ticking a ground burnable would do nothing"
		).is_not_null()


# `required_kind` NONE means "don't care" on that gate, so a reaction built without it makes EVERY
# ground on the board catch fire -- the loudest possible way for a tick to be wrong.
func test_a_created_reaction_is_fuel_for_that_kind_alone() -> void:
	var made: Array[TerrainReaction] = [ObjectKnobs.make_ignition(Terrain.Kind.MUD)]

	assert_object(TerrainReactionCatalog.fuel_for_kind(Terrain.Kind.DIRT, made)
		).override_failure_message(
		"a reaction made for MUD answers for DIRT too -- required_kind is unset, so every ground burns"
		).is_null()


# #890's terminator. Without SCORCHED refused, fire re-crosses ground it has already burnt and the
# field never settles -- the property the whole spread model rests on.
func test_a_created_reaction_refuses_ground_whose_fuel_is_spent() -> void:
	var made := ObjectKnobs.make_ignition(Terrain.Kind.MUD)
	var spent: Array[Terrain.TileState] = [Terrain.TileState.SCORCHED]

	assert_bool(made.admits(spent)).override_failure_message(
		"a new ignition reaction admits SCORCHED ground, so a fire on it would never settle"
		).is_false()


# All six shipped reactions carry it, so a file saved without it is one the editor rewrites on its
# next save -- a tree that goes dirty for an edit nobody made (#111's shape).
func test_a_created_reaction_carries_the_custom_type_metadata() -> void:
	var made := ObjectKnobs.make_ignition(Terrain.Kind.MUD)

	assert_bool(made.has_meta("_custom_type_script")).override_failure_message(
		"a new reaction saves without its custom-type line, so Godot adds one and dirties the tree"
		).is_true()


# --- The dial's floor ---------------------------------------------------------------------------

# Dev, 2026-09-12: "let's keep floor at 1." An absent clock is legal .tres and means burns-forever,
# but test_fire_clock.gd refuses one on a SHIPPED fuel -- so the dial must be unable to author the
# state CI reds, and the TICK is how forever gets said.
func test_the_dial_cannot_author_the_clock_the_suite_refuses() -> void:
	assert_int(ObjectKnobs.MIN_BURN_TURNS).override_failure_message(
		"the turns dial reaches 0, which authors no clock at all -- test_fire_clock.gd reds on that"
		).is_greater(0)
	assert_int(ObjectKnobs.DEFAULT_BURN_TURNS).is_greater_equal(ObjectKnobs.MIN_BURN_TURNS)


func test_a_new_ground_starts_with_a_clock() -> void:
	assert_int(ObjectKnobs.burn_turns_of(ObjectKnobs.make_ignition(Terrain.Kind.MUD))
		).is_greater_equal(ObjectKnobs.MIN_BURN_TURNS)


# --- Which grounds are asked at all -------------------------------------------------------------

# NONE is "this tile declares no terrain_type" (the `crate` tile is one) and VOID is a hole. Neither
# is ground a fire could take, so neither gets the question.
func test_the_ground_section_skips_the_two_kinds_that_are_not_ground() -> void:
	assert_bool(ObjectKnobs.ground_rules_apply_to(Terrain.Kind.NONE)).is_false()
	assert_bool(ObjectKnobs.ground_rules_apply_to(Terrain.Kind.VOID)).is_false()
	assert_bool(ObjectKnobs.ground_rules_apply_to(Terrain.Kind.GRASS)).is_true()

