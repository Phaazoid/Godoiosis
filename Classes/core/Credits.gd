extends Object
class_name Credits

# WHOSE NAME MUST APPEAR IN THE BUILD (#139). Read by CreditsScreen, which is a pure projection of
# this table the way GlossaryScreen is of Glossary.
#
# THIS IS NOT THE PROVENANCE RECORD, and the split is deliberate. Two different questions:
#   - here: "whose name does a shipped build print" -- short, player-facing, only what ships
#   - #139: "where did this file come from, and may we ship it" -- complete, internal, and it
#     necessarily holds rows that get NO credit because they cannot be licensed at all
# One document answering both would put "terms: unknown" in front of a player.
#
# `required` IS A LICENCE CONDITION, NOT AN EMPHASIS. Two grants here were given ON CONDITION of
# attribution, so shipping without the row ships outside the terms:
#   - Sara Shen, verbally via dev 2026-09-10 -- "fine with us using whatever, and just to include
#     her name and insta link somewhere"
#   - Jamie Brownhill / World of Solaria, licence 2(b)(6) -- "grant proper credit to the Licensor
#     where due"
# tests/law/test_credits_required.gd asserts every required row reaches the screen. Do not delete
# a required row to tidy the page.
#
# THE FIRE EMBLEM PLACEHOLDER SPRITES ARE DELIBERATELY ABSENT. Art/Units/MapSprites/ and
# ZoomAnimations/ are GBA rips being replaced under #937; ZoomAnimations/README.md credits the
# rippers who asked for it. That is a rip credit, not a rights answer -- crediting an asset that
# cannot be licensed does not license it, and naming it on a public page is an admission that
# ships with the zip for no benefit. It belongs in #139's record, not here. This absence is a
# decision; it is not an oversight to fix.

# DEVELOPMENT IS ONE ROW CARRYING BOTH NAMES, not a row each (dev, 2026-09-12) -- the role is shared
# rather than held twice, and a single line is what says so. Order is alphabetical by surname.
# Do not "correct" any of this against who wrote the code in THIS repo: the GameMaker build a decade
# earlier was ~90% Simeon's where this one is ~90% Daniel's, and in his words the ideas synthesis has
# been a fully collaborative effort throughout. Simeon appears again under Music because composing
# the score is a separate contribution, not a second billing.

enum Section { DEVELOPMENT, ART, MUSIC, SOUND, ENGINE }

const SECTION_NAMES := {
	Section.DEVELOPMENT: "Development",
	Section.ART: "Art",
	Section.MUSIC: "Music",
	Section.SOUND: "Sound",
	Section.ENGINE: "Built with",
}

# One row: `name` is the credit, `role` what it is for, `detail` the handle or link the grant asks
# for (empty when none is owed). `required` marks a licence condition -- see the header.
const ENTRIES := {
	Section.DEVELOPMENT: [
		{
			"name": "Simeon Anfinrud  ·  Daniel Manzella",
			"role": "Design and development",
			"detail": "",
			"required": false,
		},
	],
	Section.ART: [
		{
			"name": "Sara Shen",
			"role": "Element runes, weapon icons, and the logo",
			"detail": "@stargarnishstudio  ·  instagram.com/stargarnishstudio",
			"required": true,
		},
		{
			"name": "Jamie Brownhill",
			"role": "Board tileset",
			"detail": "World of Solaria",
			"required": true,
		},
		{
			"name": "ProjectUtumno",
			"role": "Source art for the ward shield icons",
			"detail": "",
			"required": false,
		},
	],
	Section.MUSIC: [
		{
			"name": "Simeon Anfinrud",
			"role": "Splendor of Adventure  ·  Battlefield  ·  Enemy Approaching",
			"detail": "",
			"required": false,
		},
	],
	Section.SOUND: [
		{"name": "SoundBible.com", "role": "Sound effects", "detail": "", "required": false},
	],
	Section.ENGINE: [
		{"name": "Godot Engine", "role": "MIT licence", "detail": "godotengine.org", "required": false},
		{"name": "Dialogic", "role": "Dialogue system", "detail": "", "required": false},
	],
}


# Every row, in section order, flattened -- what the screen walks and what the law suite counts.
static func all_entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for section: Section in Section.values():
		for entry: Dictionary in ENTRIES.get(section, []):
			rows.append(entry)
	return rows


# The rows a licence condition forces into the build.
static func required_entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry in all_entries():
		if entry.get("required", false):
			rows.append(entry)
	return rows
