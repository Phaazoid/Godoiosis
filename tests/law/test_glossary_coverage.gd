# Glossary completeness (#135): every term the game can put in front of a player has a real
# entry, and every game vocabulary that feeds the glossary is fully bridged. A miss here is
# fixed by AUTHORING the entry, not by editing this suite — the whole point is that a new
# stat, tile state, element state or menu verb cannot ship without its glossary line.
#
# Presence only, never wording: content is tuned freely (and numbers are interpolated from
# the constants that rule them), so nothing here pins what any entry SAYS.
extends GdUnitTestSuite


func test_every_term_has_a_complete_entry() -> void:
	for value: int in Glossary.Term.values():
		var term: Glossary.Term = value
		var term_name: String = Glossary.Term.keys()[term]
		assert_str(Glossary.title(term)) \
			.override_failure_message("Glossary.Term.%s has no title" % term_name).is_not_empty()
		assert_str(Glossary.short(term)) \
			.override_failure_message("Glossary.Term.%s has no short (tooltip) text" % term_name).is_not_empty()
		assert_str(Glossary.long_text(term)) \
			.override_failure_message("Glossary.Term.%s has no long (glossary-page) text" % term_name).is_not_empty()
		assert_bool(Glossary.CATEGORY_NAMES.has(Glossary.category_of(term))) \
			.override_failure_message("Glossary.Term.%s names a category with no display name" % term_name).is_true()


func test_no_category_page_is_empty() -> void:
	for value: int in Glossary.Category.values():
		var category: Glossary.Category = value
		assert_int(Glossary.terms_in(category).size()) \
			.override_failure_message("Glossary category %s has no terms — its page would render blank"
				% Glossary.Category.keys()[category]) \
			.is_greater(0)


# --- The bridges: each game vocabulary reaches an entry -------------------------------------

func test_every_stat_is_bridged() -> void:
	for value: int in Stats.Stat.values():
		var stat: Stats.Stat = value
		var term: Glossary.Term = Glossary.term_for_stat(stat)
		assert_str(Glossary.short(term)) \
			.override_failure_message("Stats.Stat.%s bridges to an empty glossary entry" % Stats.Stat.keys()[stat]) \
			.is_not_empty()


func test_every_tile_state_is_bridged() -> void:
	for value: int in Terrain.TileState.values():
		var state: Terrain.TileState = value
		if state == Terrain.TileState.NONE:
			continue
		var term: Glossary.Term = Glossary.term_for_tile_state(state)
		assert_str(Glossary.short(term)) \
			.override_failure_message("Terrain.TileState.%s bridges to an empty glossary entry" % Terrain.TileState.keys()[state]) \
			.is_not_empty()


func test_every_element_state_is_bridged() -> void:
	for value: int in Elemental.State.values():
		var state: Elemental.State = value
		if state == Elemental.State.NONE:
			continue
		var term: Glossary.Term = Glossary.term_for_element_state(state)
		assert_str(Glossary.short(term)) \
			.override_failure_message("Elemental.State.%s bridges to an empty glossary entry" % Elemental.State.keys()[state]) \
			.is_not_empty()


# Both tables, because since #467 a menu row is either a verb or one of the ring's CATEGORIES, and
# the player hovers both. Asking only ACTION_DATA would be a law aimed at a table rather than at
# the question it was written for.
func test_every_menu_row_names_a_term() -> void:
	for id: int in MainActionMenu.ACTION_DATA:
		var entry: Dictionary = MainActionMenu.ACTION_DATA[id]
		assert_bool(entry.has("term")) \
			.override_failure_message("ACTION_DATA row '%s' has no glossary term — its menu row would have no hover text"
				% entry["name"]) \
			.is_true()
	for group: int in MainActionMenu.CATEGORIES:
		var category: Dictionary = MainActionMenu.CATEGORIES[group]
		assert_bool(category.has("term")) \
			.override_failure_message("ring category '%s' has no glossary term — its slice would have no hover text"
				% category["name"]) \
			.is_true()


# Every verb has to be reachable, or it is declared and undrawable. The ring only draws categories,
# so a verb whose group is missing from CATEGORIES is a row no player can ever see.
func test_every_menu_verb_belongs_to_a_category_the_ring_draws() -> void:
	for id: int in MainActionMenu.ACTION_DATA:
		var entry: Dictionary = MainActionMenu.ACTION_DATA[id]
		assert_bool(entry.has("group")) \
			.override_failure_message("ACTION_DATA row '%s' names no ring category" % entry["name"]) \
			.is_true()
		assert_bool(MainActionMenu.CATEGORIES.has(entry["group"])) \
			.override_failure_message("ACTION_DATA row '%s' names a category the ring has no slice for" % entry["name"]) \
			.is_true()


# --- Composed interactions: one line per authored reaction, always ---------------------------
# The glossary's interaction list is READ off the catalogs, so its size must track them exactly.
# A mismatch means someone started authoring interaction prose by hand — the drift this design
# exists to prevent.

func test_reaction_lines_track_the_catalog() -> void:
	assert_int(Glossary.reaction_lines().size()).is_equal(ReactionCatalog.get_all().size())
	assert_int(Glossary.terrain_reaction_lines().size()).is_equal(TerrainReactionCatalog.get_all().size())


func test_reaction_lines_name_their_element() -> void:
	# Spot the composition actually reads the data: every line leads with its trigger element.
	var reactions: Array[ElementalReaction] = ReactionCatalog.get_all()
	var lines: Array[String] = Glossary.reaction_lines()
	for i: int in reactions.size():
		assert_str(lines[i]) \
			.override_failure_message("reaction line %d does not name its trigger element: '%s'" % [i, lines[i]]) \
			.contains(Elemental.display_name(reactions[i].incoming_element))
