# AI Crisis stances (#57, will-and-death.md "AI Crisis policy"): each archetype declares
# accept/decline at authoring time. Pure lookup, no scene needed.
extends GdUnitTestSuite

func test_rushdown_always_accepts() -> void:
	assert_bool(AIArchetype.accepts_crisis(AIArchetype.Type.RUSHDOWN)).is_true()

func test_hold_never_accepts() -> void:
	assert_bool(AIArchetype.accepts_crisis(AIArchetype.Type.HOLD)).is_false()

func test_sentry_never_accepts() -> void:
	assert_bool(AIArchetype.accepts_crisis(AIArchetype.Type.SENTRY)).is_false()

func test_faction_default_resolves_through_the_default_archetype() -> void:
	# FACTION_DEFAULT is a sentinel (AIArchetype.DEFAULT == RUSHDOWN) -> accepts, same as resolve().
	assert_bool(AIArchetype.accepts_crisis(AIArchetype.Type.FACTION_DEFAULT)).is_equal(AIArchetype.accepts_crisis(AIArchetype.DEFAULT))
	assert_bool(AIArchetype.accepts_crisis(AIArchetype.Type.FACTION_DEFAULT)).is_true()
