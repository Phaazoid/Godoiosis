class_name ItemDetail

# WHICH DETAIL CARD A PIECE OF GEAR HAS, and how it is opened (#1019). ONE file, because the question
# is asked twice per surface -- once to build the affordance, once to act on it -- across three surfaces
# (PreMissionCard's unit gear rows, PreMissionScreen's stash rows, and since #1152 the battle
# inventory's Inspect). Hand-written kind forks at each are places to forget the next kind the day one
# exists.
#
# IT IS ALSO WHY THERE IS ONE SIGNAL. `PreMissionCard.detail_requested` carries an `Item`, not a
# weapon, so the chip and the handler ask the same question of the same value; a per-kind signal would
# put the fork back in the wiring, where nothing could see the two halves together.
#
# A NULL CHIP MEANS THIS ROW GETS NO CHIP -- armour, a vial, and a weapon whose template authors no mod
# spaces, since a weapon's chip is the FITTING affordance and there is nothing to fit. A rune always
# has one, blank included; RuneDetailCard.chip_for says why. Whether an item has a card to READ at all
# is has_card below, which a spaceless weapon answers yes to (#1152).

static func chip_for(item: Item) -> Button:
	var weapon := item as WeaponInstance
	if weapon != null:
		return ModFittingCard.chip_for(weapon)
	var rune := item as RuneData
	if rune != null:
		return RuneDetailCard.chip_for(rune)
	return null


# THE CHIP ITSELF, in one place (#1022). Both cards spelled these lines and neither set a stylebox,
# so both took the engine's default chrome -- which is exactly what EXECUTE_BG's own comment already
# records as *grey on a grey panel, and it simply disappeared* (dev, 2026-09-03), and the dev read
# this one the same way: it did not look interactable. The cure is Execute's: a box of its own.
#
# ONE BUILDER, so "make it pop" is a one-place change rather than two that agree until they do not --
# which is the same argument that made `chip_for` above a single fork.
#
# ALL FOUR FONT STATES, and that is not belt-and-braces: a Button falls back to the THEME's colour on
# hover, so overriding only `font_color` is how the Loadout button vanished under parchment (#814).
# The pointing hand costs no width and is the one signal that survives any palette.
static func chip(text: String, tip: String) -> Button:
	var chip := Button.new()
	chip.text = text
	chip.add_theme_font_size_override("font_size", 9)
	chip.focus_mode = Control.FOCUS_NONE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.tooltip_text = UiText.wrap(tip)
	chip.add_theme_stylebox_override("normal", QueueStyle.chip_box(false))
	chip.add_theme_stylebox_override("focus", QueueStyle.chip_box(false))
	chip.add_theme_stylebox_override("hover", QueueStyle.chip_box(true))
	chip.add_theme_stylebox_override("pressed", QueueStyle.chip_box(true))
	chip.add_theme_color_override("font_color", QueueStyle.chip_ink(false))
	chip.add_theme_color_override("font_focus_color", QueueStyle.chip_ink(false))
	chip.add_theme_color_override("font_hover_color", QueueStyle.chip_ink(true))
	chip.add_theme_color_override("font_pressed_color", QueueStyle.chip_ink(true))
	return chip


# Does this item have a card to read? The kinds open() forks on, and nothing else (#1152) -- the
# battle inventory's Inspect asks this, where the pre-mission rows ask chip_for.
static func has_card(item: Item) -> bool:
	return item is WeaponInstance or item is RuneData


# `mods` is the mission's own mod pool (#812) and `on_closed` what the host does afterwards. Both are
# the WEAPON card's business and are carried past the rune branch rather than forked at the call site,
# which is the whole point of one door -- see below for why the rune branch drops the second.
# `read_only` is the battle's door (#1152): the weapon card shows its spaces and fits nothing.
static func open(game_node: Node, item: Item, owner_unit: Unit,
		mods: Array[WeaponModData], on_closed: Callable = Callable(), read_only := false) -> void:
	var weapon := item as WeaponInstance
	if weapon != null:
		var card := ModFittingCard.open(game_node, weapon, owner_unit, mods, read_only)
		if on_closed.is_valid():
			card.closed.connect(on_closed)
		return
	var rune := item as RuneData
	if rune != null:
		# NOTHING TO REDRAW BEHIND IT. Fitting a mod moves WT, DEF, the ability chips and the stat
		# grid, so that card's host redraws on the way out; this one is a read and wrote nothing, so
		# redrawing on its close would be a screen rebuilding itself over an event that changed no
		# state. `on_closed` goes unused here deliberately rather than by omission.
		RuneDetailCard.open(game_node, rune, owner_unit)
