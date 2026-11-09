class_name EmpoweredForm
extends Resource

# What a carving BECOMES where its caster is empowered (#695): a DELTA laid over the carving, never a
# second carving. It lives inside the carving's own file (TransmutationData.empowered), and the game
# builds the form at runtime as "this carving with the delta laid over it"
# (TransmutationData.empowered_carving) -- one derived carving per formed carving, never saved, never
# in the library.
#
# It holds ONLY what a form may change, and nothing an aim reads. Range, recipe, targets and the
# vertical rule are absent, so a form inherits them by construction: its cost, aura demand, fizzle and
# hit element are the base's, and an aim legal for the base is legal for the form. That is the
# declared second reading beside #97's weapon form (WeaponAttackData.empowered_form), which is a whole
# attack chosen at AIM time and may aim differently; a carving's form is chosen in the PASS
# (Materia.form_choice), at the caster's cell at its slot, so it must keep everything the aim depends on.
#
# Blank or zero keeps the base's value.

@export var display_name := ""
@export var popup := ""
# The form's shape, and whether it swings. Read only when a shape is set: a form with no shape of its
# own keeps the base's shape AND its swing.
@export var attack_shape: AttackShape = null
@export var swing := false
@export var power_bonus := 0
@export var knockback_bonus := 0
# The form's tile effect, its life and its shape. Read only when an effect is set (NONE keeps the base's).
@export var tile_effect: Elemental.Element = Elemental.Element.NONE
@export_range(1, 9) var tile_effect_turns: int = 2
@export var tile_effect_shape: AttackShape = null
# Gas the form adds on top of the base's, its level winning where both name a kind.
@export var gases: Dictionary[Gas.Kind, Gas.Level] = {}
# Which elements must ALL be empowered for the form to fire (#695 R1, dev 2026-11-08: "a checklist of
# what elements are needed for empowerment"). EMPTY means the elements the hit delivers -- the set
# the +1 fallback scales off (TransmutationData.form_requires).
@export var requires: Array[Elemental.Element] = []


# Write this delta onto `form`, a fresh copy of the base. Only TransmutationData's builder calls it.
func lay_over(form: TransmutationData) -> void:
	if display_name != "":
		form.display_name = display_name
	if popup != "":
		form.popup = popup
	if attack_shape != null:
		form.attack_shape = attack_shape
		form.swing = swing
	form.power += power_bonus
	form.knockback = maxi(0, form.knockback + knockback_bonus)
	if tile_effect != Elemental.Element.NONE:
		form.tile_effect = tile_effect
		form.tile_effect_turns = tile_effect_turns
		form.tile_effect_shape = tile_effect_shape
	if not gases.is_empty():
		var merged: Dictionary[Gas.Kind, Gas.Level] = form.gases.duplicate()
		merged.merge(gases, true)
		form.gases = merged


# Whether this delta changes anything a hit does -- AttackLint's empty-form finding. `requires` is
# not a change: it says WHEN, not WHAT.
func changes_anything() -> bool:
	return display_name != "" or popup != "" or attack_shape != null or power_bonus != 0 \
		or knockback_bonus != 0 or tile_effect != Elemental.Element.NONE or not gases.is_empty()


# Where its fields sit in the Attack Editor's nested form (#825's law: every export has one home).
static func property_sections() -> Array[Dictionary]:
	return [
		{"title": "Identity", "fields": PackedStringArray(["display_name", "popup"])},
		{"title": "When it fires", "fields": PackedStringArray(["requires"])},
		{"title": "Shape", "fields": PackedStringArray(["attack_shape", "swing"])},
		{"title": "On hit", "fields": PackedStringArray(["power_bonus", "knockback_bonus", "gases"])},
		{"title": "Tile effect", "fields": PackedStringArray(["tile_effect", "tile_effect_turns", "tile_effect_shape"])},
	]


static func property_tips() -> Dictionary:
	return {
		"display_name": "What the form is called when it fires. Blank = the carving's own name.",
		"popup": "Floating text over the target when the form lands. Blank = the carving's own.",
		"attack_shape": "The form's shape. Blank = the carving's own shape (and its swing).",
		"swing": "Whether the form's shape stops at the first body it meets. Read only with a shape set.",
		"power_bonus": "Added to the carving's power when the form fires. The form never also gets the +1 empowerment bonus.",
		"knockback_bonus": "Added to the carving's shove when the form fires (never below 0).",
		"tile_effect": "The tile effect the form lays. None = the carving's own.",
		"tile_effect_turns": "How many rounds the form's tile effect lasts. Read only with a tile effect set.",
		"tile_effect_shape": "Where the form's tile effect lands, if not where it strikes. Read only with a tile effect set.",
		"gases": "Gas the form releases on top of the carving's own.",
		"requires": "The elements the caster must ALL be empowered in for the form to fire (a source beside them, or their vial). Empty = the elements the carving's hit delivers.",
	}
