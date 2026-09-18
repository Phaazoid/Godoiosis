# No glossary entry carries a DASH TELL, in either spelling.
#
# THE RULE, and it is the first statement of it anywhere in this repo -- it had lived only in
# conversation. Dev, 2026-09-14, unprompted: *"I know I saw lots of -'s in the dialogic stuff you
# wrote, and that comes off as very AI. People hate stuff that was written by AI."* And the next day,
# which is the half that sets the scope: *"No, Simeon and I don't care about AI use. It's more just a
# hot button issue with gamers right now."* So this is an AUDIENCE-RECEPTION rule about the shipped
# surface, not a style preference and not a standard held anywhere else. Re-affirmed 2026-09-18 while
# he was reading the glossary: *"I'm seeing some telltale dashes in here."*
#
# SCOPE: strings a PLAYER reads. Code comments, issue bodies, PR text and everything in docs/ are
# explicitly EXEMPT -- he and the codev read those and they are not the audience the risk is about,
# so this file's own comments carry em dashes on purpose and Glossary.gd's nine still do.
#
# WHY IT STOPS AT THE GLOSSARY rather than sweeping every player-facing string: the wider net's first
# catch would be HoverPresenter._tile_readout_lines, which composes "%s — %s" as a LABEL SEPARATOR
# between a state's name and its meaning. That is ordinary typography rather than a tell, and it is
# the dev's call to make, not this law's. Flagged to him rather than silently widened.
#
# BOTH SPELLINGS, because four entries carried the ASCII one when this was written (DEF, Damage
# kinds, Undeploy, Reposition) and a law that knew only the em dash would have let them back.
# A BARE HYPHEN IS DELIBERATELY NOT MATCHED: "cold-slowed", "dug-in" and "%+d" are all legitimate,
# so the ASCII form is caught only with a space on each side, which is what makes it a dash rather
# than a compound.
extends GdUnitTestSuite

const EM_DASH := "—"
const ASCII_DASH := " -- "


func test_no_entry_text_carries_a_dash() -> void:
	for value: int in Glossary.Term.values():
		var term: Glossary.Term = value
		var term_name: String = Glossary.Term.keys()[term]
		for field: String in ["short", "long"]:
			var text: String = Glossary.short(term) if field == "short" else Glossary.long_text(term)
			assert_bool(text.contains(EM_DASH)).override_failure_message(
					"Glossary.Term.%s's %s carries an em dash, which reads as AI-written on a "
					% [term_name, field] + "surface a player sees: %s" % text).is_false()
			assert_bool(text.contains(ASCII_DASH)).override_failure_message(
					"Glossary.Term.%s's %s carries a spaced double hyphen, the same tell in ASCII: "
					% [term_name, field] + text).is_false()


# The non-vacuity guard, and it is the case that matters most here: the sweep above walks an enum,
# so a broken walk passes SILENTLY over nothing at all. A count rather than a non-empty check,
# because Term.values() returning one member would also satisfy "not empty".
func test_the_sweep_actually_read_every_term() -> void:
	var seen := 0
	for value: int in Glossary.Term.values():
		var term: Glossary.Term = value
		if not Glossary.short(term).is_empty() and not Glossary.long_text(term).is_empty():
			seen += 1
	assert_int(seen).override_failure_message(
			"the dash sweep saw %d terms with text; the registry has %d, so it is reading less "
			% [seen, Glossary.Term.size()] + "than the whole glossary and could pass vacuously"
			).is_equal(Glossary.Term.size())
	# ...and the registry is not itself empty, which the equality above would happily accept.
	assert_int(Glossary.Term.size()).override_failure_message(
			"the Term enum is empty, so every case in this file is vacuous").is_greater(50)
