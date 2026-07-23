# AI action coverage (#78): every main action type must have a DECLARED AI stance for every
# archetype -- in the priority list or the NEVER set, never absent, never both. This is the
# action registry's AI column, mirroring test_action_registry.gd's pipeline pin: a new verb
# (or a new archetype) turns this suite red until someone declares how the AI treats it,
# even if the declaration is NEVER.
extends GdUnitTestSuite


func _archetypes() -> Array:
	var result := []
	for t in AIArchetype.Type.values():
		if t != AIArchetype.Type.FACTION_DEFAULT:   # sentinel, not an implementation
			result.append(t)
	return result


func test_every_archetype_declares_both_tables() -> void:
	for t in _archetypes():
		var label: String = AIArchetype.Type.keys()[t]
		assert_bool(AIArchetype.MAIN_ACTION_PRIORITY.has(t)) \
			.override_failure_message("archetype %s missing from MAIN_ACTION_PRIORITY" % label) \
			.is_true()
		assert_bool(AIArchetype.MAIN_ACTION_NEVER.has(t)) \
			.override_failure_message("archetype %s missing from MAIN_ACTION_NEVER" % label) \
			.is_true()


func test_tables_partition_main_action_types_exactly() -> void:
	for t in _archetypes():
		var priority: Array = AIArchetype.MAIN_ACTION_PRIORITY[t]
		var never: Array = AIArchetype.MAIN_ACTION_NEVER[t]
		for action_type in BaseAction.MAIN_ACTION_TYPES:
			var declared: int = int(priority.has(action_type)) + int(never.has(action_type))
			assert_int(declared) \
				.override_failure_message("%s must declare %s exactly once (priority or NEVER); found %d" % [
					AIArchetype.Type.keys()[t], BaseAction.ActionType.keys()[action_type], declared]) \
				.is_equal(1)


func test_tables_contain_no_foreign_entries() -> void:
	# Only main actions belong in the tables -- MOVE and COUNTER_ATTACK are not choices the
	# chooser makes (movement is archetype personality; counters are derived, Law #2).
	for t in _archetypes():
		for action_type in AIArchetype.MAIN_ACTION_PRIORITY[t]:
			assert_bool(BaseAction.MAIN_ACTION_TYPES.has(action_type)) \
				.override_failure_message("%s priority lists non-main type %s" % [
					AIArchetype.Type.keys()[t], BaseAction.ActionType.keys()[action_type]]) \
				.is_true()
		for action_type in AIArchetype.MAIN_ACTION_NEVER[t]:
			assert_bool(BaseAction.MAIN_ACTION_TYPES.has(action_type)) \
				.override_failure_message("%s NEVER lists non-main type %s" % [
					AIArchetype.Type.keys()[t], BaseAction.ActionType.keys()[action_type]]) \
				.is_true()


func test_crisis_and_implementation_registries_cover_every_archetype() -> void:
	# The pre-#78 per-archetype declarations, held to the same completeness standard.
	for t in _archetypes():
		assert_bool(AIArchetype.CRISIS_STANCES.has(t)).is_true()
		assert_bool(AIArchetype.resolve(t).is_valid()).is_true()


func test_faction_default_resolves_to_the_default_archetypes_priority() -> void:
	# FACTION_DEFAULT is a sentinel -- same resolution rule as accepts_crisis/resolve.
	assert_array(AIArchetype.main_action_priority(AIArchetype.Type.FACTION_DEFAULT)) \
		.is_equal(AIArchetype.MAIN_ACTION_PRIORITY[AIArchetype.DEFAULT])
