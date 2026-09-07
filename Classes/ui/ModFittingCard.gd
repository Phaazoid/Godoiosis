class_name ModFittingCard
extends ModalCard

# The weapon detail card (#732) -- one weapon's mod spaces, what is in them, and the mods it could
# take, fitted by dragging or by clicking exactly the way the stash moves gear.
#
# THE SOURCE IS THE WHOLE AUTHORED CATALOG (dev, 2026-09-06: "Perhaps we start this simple with the
# whole authored catalog, and file a followup issue for controlling what items/mods are in a
# scenario"). So fitting is free and unlimited here, and #812 is where scarcity arrives. The one
# limit that is real today is #732's own: a weapon holds one of any given mod.
#
# IT CLAIMS THE MODAL LOCK, and that is the point rather than a side effect. game.gd gates both Tab
# and the commit key on ModalLock.any_open, so while this is up neither can swap the board out from
# under it. ConfirmCard already stacks over PreMissionScreen through the same lock.
#
# IT JUDGES NOTHING. Every refusal is WeaponInstance.fit_block_reason's own sentence, and the two
# callables it wires into rows and zones are the same pair the click path uses -- #741's rule, one
# surface further in. A drag that decided for itself would be a second answer to "may this fit".
#
# THE SELECTION IS DATA, NEVER A ROW (#741's law again): every change redraws both lists and frees
# every row in them, so a selection holding a node would dangle on the first fit that worked.
#
# THIS CARD HAS BOTH OF QueueStyle'S GROUNDS, which is why its text roles look inconsistent and are
# not (#814): ModalCard's frame is panel_box(), dark under either palette -- parchment's PANEL_BG is
# the dark frame its paper lies on -- so everything directly on it takes the FRAME roles, while the
# zones inside are section_box()/row_box(), i.e. paper under parchment, and take HEADER_TEXT and
# BODY_TEXT. Ask which ground a label lands on.

signal closed

const CARD_W := 600
const LIST_H := 168
const ROW_H := 20

var _weapon: WeaponInstance
# WHICH MODS THIS MISSION OFFERS (#812), handed in by whoever opened the card. Empty = the whole
# authored catalogue, which is what the Item Editor and any board with no roster want.
var _pool: Array[WeaponModData] = []
# Null for a weapon nobody is holding -- one sitting in the stash. active_space_count answers
# UNREDUCED for that, so the card shows the BUILD rather than a weapon whose every mod reads inert.
var _wielder: Unit
var _attack: AttackData
var _selected: WeaponModData
var _selected_from: Object
var _last_refusal := ""

var _picker: OptionButton
var _plate: ShapePlate
var _headline: Label
var _damage: Label
var _range: Label
var _proficiency: Label
var _spaces_box: VBoxContainer
var _offer_box: VBoxContainer
var _offer_zone: GearDropZone
var _hint: Label


static func open(game_node: Node, weapon: WeaponInstance, wielder: Unit,
		pool: Array[WeaponModData] = []) -> ModFittingCard:
	var card := ModFittingCard.new()
	card._weapon = weapon
	card._pool = pool
	card._wielder = wielder
	game_node.ui_layer.add_child(card)
	card._build(game_node)
	return card


func _build(game_node: Node) -> void:
	var content := _build_chrome(game_node)
	content.custom_minimum_size.x = CARD_W
	content.add_theme_constant_override("separation", 8)

	_build_head(content)
	_build_readout(content)
	content.add_child(HSeparator.new())
	_build_lists(content)

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 10)
	content.add_child(_hint)
	refresh()


func _build_head(parent: Container) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	_headline = Label.new()
	_headline.add_theme_font_size_override("font_size", 14)
	_headline.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.TITLE_TEXT))
	_headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_headline.clip_text = true
	row.add_child(_headline)

	var close := Button.new()
	close.text = "Close"
	close.add_theme_font_size_override("font_size", 11)
	close.pressed.connect(_on_close)
	row.add_child(close)


# The plate and the numbers that move with it, side by side: fitting a mod that replaces the main or
# grants an attack changes both, and they have to be read together to be read at all.
func _build_readout(parent: Container) -> void:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 12)
	parent.add_child(strip)

	_plate = ShapePlate.new()
	strip.add_child(_plate)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(column)

	# Rebuilt only by _refresh_attacks, never by the readout it drives -- a picker freed inside its own
	# item_selected is the #741 crash one surface over.
	_picker = OptionButton.new()
	_picker.clip_text = true
	_picker.fit_to_longest_item = false
	_picker.custom_minimum_size.x = 150
	_picker.add_theme_font_size_override("font_size", 11)
	_picker.item_selected.connect(_on_attack_picked)
	column.add_child(_picker)

	_damage = _readout_label(column)
	_range = _readout_label(column)
	_proficiency = _readout_label(column)
	column.add_child(_legend())


func _readout_label(parent: Container) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
	label.clip_text = true
	parent.add_child(label)
	return label


# What the plate's two inks MEAN, in the inks themselves -- they are the board's own aim colours, so
# this doubles as the bridge between the card and what the player sees over a live aim.
func _legend() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_swatch("hits", OverlayManager.aim_fill_color()))
	row.add_child(_swatch("can aim", OverlayManager.attack_reach_color(_attack)))
	return row


func _swatch(text: String, tint: Color) -> Control:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 3)
	var chip := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = tint
	chip.add_theme_stylebox_override("panel", box)
	chip.custom_minimum_size = Vector2(9, 9)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pair.add_child(chip)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
	pair.add_child(label)
	return pair


func _build_lists(parent: Container) -> void:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	parent.add_child(columns)

	var left := _column(columns, "SPACES", 3)
	_spaces_box = VBoxContainer.new()
	_spaces_box.add_theme_constant_override("separation", 6)
	_scroller(left, _spaces_box)

	var right := _column(columns, "MODS THAT FIT", 2)
	# The whole list is one drop zone, not just its rows: dropping into the gap under the last row is
	# the same gesture as dropping on a row, and it is how a fitted mod comes OFF.
	_offer_zone = GearDropZone.new()
	_offer_zone.add_theme_stylebox_override("panel", QueueStyle.section_box())
	_offer_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_offer_zone.wire(null, _judge_pull, _perform_pull)   # null holder IS the library
	_offer_zone.clicked.connect(_on_library_clicked)
	_scroller(right, _offer_zone)

	_offer_box = VBoxContainer.new()
	_offer_box.add_theme_constant_override("separation", 4)
	_offer_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_offer_zone.add_child(_offer_box)


func _column(parent: Container, title: String, stretch: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = stretch
	parent.add_child(column)

	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
	column.add_child(label)
	return column


# PreMissionScreen._scroller's rule, and its reason: a ScrollContainer lays its child out at COMBINED
# MINIMUM unless that child's horizontal flags carry SIZE_EXPAND, and every label here is clip_text,
# so forgetting it renders as rows a pixel or two wide (#788).
func _scroller(parent: Container, content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = LIST_H
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	parent.add_child(scroll)
	return scroll


# --- state ---------------------------------------------------------------------------------------

func refresh() -> void:
	_refresh_attacks()
	_refresh_readout()
	_refresh_spaces()
	_refresh_offers()
	_refresh_hint()


# A REDRAW NEVER RUNS INSIDE THE SIGNAL THAT CAUSED IT (#741). Every handler below is reached from a
# row's own clicked or _drop_data, and refresh() frees every row in both lists -- the emitting one
# included, which Godot refuses outright.
func _redraw() -> void:
	refresh.call_deferred()


# The repertoire, not the fireable set: a watch-only attack has geometry too, and this is a readout
# rather than an order. Rebuilt whole because a fitted mod can add to it or replace its main -- the
# selection is kept by IDENTITY, so a mod that swapped the main lands the picker on the new one.
func _refresh_attacks() -> void:
	var attacks := _weapon.available_attacks(_wielder)
	_picker.clear()
	# FALLING BACK TO INDEX 0 IS THE FALLBACK, and it is the only one there can be: available_attacks
	# leads with effective_main, so an attack the fitting just took away lands the picker on whatever
	# the weapon's main has become. An explicit `_attack = effective_main()` stood here until a mutant
	# proved it dead -- the assignment below overwrites it either way, and the only case it was
	# reachable in was the one where the two agreed.
	var chosen := 0
	for i in range(attacks.size()):
		_picker.add_item(attacks[i].display_name)
		_picker.set_item_metadata(i, attacks[i])
		if attacks[i] == _attack:
			chosen = i
	if attacks.is_empty():
		_picker.add_item("no attack")
	else:
		_picker.select(chosen)
		_attack = attacks[chosen]
	_picker.disabled = attacks.size() < 2


func _on_attack_picked(index: int) -> void:
	_attack = _picker.get_item_metadata(index) as AttackData
	_refresh_readout()   # NOT refresh(): a rebuilt picker inside its own item_selected frees the emitter


func _refresh_readout() -> void:
	var family: String = WeaponData.WeaponType.keys()[_weapon.template.weapon_type].capitalize() \
		if _weapon.template != null else "no family"
	var carrier := "in the stash" if _wielder == null else "carried by %s" % _wielder.get_unit_name()
	_headline.text = "%s  ·  %s  ·  %s" % [_weapon.shown_name(), family, carrier]

	_plate.show_attack(_attack)
	# attack_detail asks the WIELDER's stats, so a weapon nobody holds has no number to show rather
	# than a number computed against nobody.
	_damage.text = _weapon.attack_detail(_wielder, _attack) if _wielder != null and _attack != null else ""
	_damage.visible = _damage.text != ""
	_range.text = _range_text(_attack)
	_proficiency.text = _proficiency_text(family)


static func _range_text(attack: AttackData) -> String:
	if attack == null:
		return ""
	if attack.is_directional():
		return "Aims a facing"
	var span := "Range %d" % attack.max_range if attack.min_range == attack.max_range \
		else "Range %d-%d" % [attack.min_range, attack.max_range]
	return "%s, bevelled corners" % span if attack.max_and_a_half else span


# What the carrier can actually reach (#732, dev: "what the carrier's current proficiency is").
# Nothing in shipped content authors a reduced one, so this reads "every space" for the whole cast
# until one is -- which is worth SAYING rather than leaving the line to look broken.
func _proficiency_text(family: String) -> String:
	if _wielder == null:
		return "No carrier, so no proficiency applies"
	var active := _weapon.active_space_count(_wielder)
	if active >= _weapon.space_count():
		return "%s proficiency: every space" % family
	return "%s proficiency: spaces 1-%d of %d" % [family, active, _weapon.space_count()]


func _refresh_spaces() -> void:
	_clear(_spaces_box)
	for i in range(_weapon.space_count()):
		_spaces_box.add_child(_space_block(i))


# One space: a drop zone wrapping its own header and rows, so the header is a target too -- clicking
# anywhere in the block means "put it here".
func _space_block(index: int) -> Control:
	var zone := GearDropZone.new()
	zone.add_theme_stylebox_override("panel", QueueStyle.section_box())
	zone.wire(_weapon, _judge_fit.bind(index), _perform_fit.bind(index))
	zone.clicked.connect(_on_space_clicked.bind(index))

	# Nothing here sets mouse_filter, and that is MEASURED rather than assumed: a Container defaults to
	# PASS (1), so the press reaches the ZONE through it, which is what makes "click a space to put it
	# there" work where the space has no row to click. A Panel or a PanelContainer added in here would
	# default to STOP and break exactly that, silently -- the suite has a case for it.
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 5)
	zone.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	pad.add_child(column)

	var head := HBoxContainer.new()
	var active: bool = _wielder == null or index < _weapon.active_space_count(_wielder)
	var title := Label.new()
	title.text = "Space %d  ·  needs %s %d" % [
		index + 1, WeaponData.WeaponType.keys()[_weapon.template.weapon_type].capitalize(), index + 1]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
	head.add_child(title)

	var used := Label.new()
	used.text = "%d / %d used" % [_weapon.used_capacity(index), _weapon.template.mod_spaces[index]] \
		if active else "inactive"
	used.add_theme_font_size_override("font_size", 10)
	used.add_theme_color_override("font_color", QueueStyle.ink(
		QueueStyle.Role.HEADER_TEXT if active else QueueStyle.Role.ROW_REFUSED_BORDER))
	head.add_child(used)
	column.add_child(head)

	var fitted := _weapon.space(index)
	for mod: WeaponModData in fitted:
		column.add_child(_mod_row(mod, _weapon, _judge_fit.bind(index), _perform_fit.bind(index),
			_on_space_clicked.bind(index), ""))
	if fitted.is_empty():
		var empty := Label.new()
		empty.text = "empty"
		empty.add_theme_font_size_override("font_size", 10)
		# HEADER_TEXT, the muted role for paper -- SECTION_BORDER is a BORDER, and borrowing it as ink
		# left "empty" at a gap of 0.12 on SLATE, which the walker found and no palette caused (#814).
		empty.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
		column.add_child(empty)
	return zone


func _refresh_offers() -> void:
	_clear(_offer_box)
	var offerable := WeaponModCatalog.offerable_for(_weapon.template.weapon_type, _pool)
	if offerable.is_empty():
		var none := Label.new()
		# The sentence forks on WHY there is nothing, because the two are different problems: an
		# empty pool is what this MISSION offers; anything else is what exists at all.
		var family: String = WeaponData.WeaponType.keys()[_weapon.template.weapon_type].capitalize()
		none.text = ("This mission offers no mods for a %s." % family) if not _pool.is_empty() \
			else ("Nothing authored fits a %s." % family)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_font_size_override("font_size", 10)
		none.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
		_offer_box.add_child(none)
		return
	for key in offerable:
		var mod: WeaponModData = offerable[key]
		_offer_box.add_child(_mod_row(mod, null, _judge_pull, _perform_pull, _on_library_clicked,
			str(key), _offer_block_reason(mod)))


# WHY IT CANNOT GO ON THIS WEAPON AT ALL -- "" when some space would take it. A row is about the
# whole weapon, so the answer is a scan; the sentence it reports is the one from the space this mod
# would actually go in, which is the same space the "needs" line names.
func _offer_block_reason(mod: WeaponModData) -> String:
	for i in range(_weapon.space_count()):
		if _weapon.fit_block_reason(i, mod) == "":
			return ""
	var lowest := _weapon.lowest_space_for(mod)
	if lowest == -1:
		return "No space on %s is big enough for a size-%d mod." % [_weapon.shown_name(), mod.size]
	return _weapon.fit_block_reason(lowest, mod)


# One mod, in either list -- a GearRow so a fitted mod and an offered one are picked up the same way,
# and so both lists inherit the click-vs-drag threshold and the drag preview #798 fixed.
#
# THE NAME IS THE CATALOG'S KEY where there is one, which falls back to the FILENAME: a mod with no
# authored display_name (Test.tres ships as one) would otherwise be a blank row. A fitted row has no
# key to hand, so it uses the field and its own fallback.
func _mod_row(mod: WeaponModData, holder: Object, judge: Callable, perform: Callable,
		on_click: Callable, key: String, refusal: String = "") -> Control:
	var row := GearRow.new()
	row.custom_minimum_size.y = ROW_H
	row.carry(mod)
	row.wire(holder, judge, perform)
	row.clicked.connect(on_click)
	row.add_theme_stylebox_override("panel", QueueStyle.row_box(refusal != "", mod == _selected))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 4)
	pad.add_theme_constant_override("margin_right", 4)
	row.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	pad.add_child(column)

	var name_label := Label.new()
	name_label.text = key if key != "" else _mod_name(mod)
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.BODY_TEXT))
	column.add_child(name_label)

	# One line of what it does and what it costs (dev, 2026-09-06: "Let's keep it, this is a zoom in
	# window for clarity"). The proficiency is DERIVED -- a mod authors no requirement, so what it
	# needs is the lowest space big enough to hold it.
	var detail := Label.new()
	detail.text = "%s  ·  size %d  ·  %s" % [mod.effect_text(), mod.size, _needs_text(mod)]
	detail.clip_text = true
	detail.add_theme_font_size_override("font_size", 9)
	detail.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
	column.add_child(detail)

	row.tooltip_text = UiText.wrap("%s\n%s" % [detail.text, refusal] if refusal != "" else detail.text)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	return row


func _needs_text(mod: WeaponModData) -> String:
	var lowest := _weapon.lowest_space_for(mod)
	if lowest == -1:
		return "fits no space here"
	return "needs %s %d" % [
		WeaponData.WeaponType.keys()[_weapon.template.weapon_type].capitalize(), lowest + 1]


static func _mod_name(mod: WeaponModData) -> String:
	if mod == null:
		return ""
	if mod.display_name != "":
		return mod.display_name
	return mod.id if mod.id != "" else "unnamed mod"


static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()


# --- fitting, both input paths -------------------------------------------------------------------

# The judge every space zone and every row in one is wired with, click and drag alike. `from` and
# `to` go unread: the bound INDEX carries the destination, and where the mod came from is a question
# the weapon can answer itself, since a fitted mod IS the object in one of its spaces.
func _judge_fit(mod: Item, _from: Object, _to: Object, index: int) -> String:
	var piece := mod as WeaponModData
	if piece == null:
		return "That is not a weapon mod."
	if _weapon.space_holding(piece) == index:
		return ""   # dropped back in the space it already sits in: a no-op, not a refusal
	return _weapon.fit_block_reason(index, piece)


func _perform_fit(mod: Item, from: Object, to: Object, index: int) -> String:
	var refusal := _judge_fit(mod, from, to, index)
	var piece := mod as WeaponModData
	if refusal == "" and piece != null and _weapon.space_holding(piece) != index:
		_weapon.fit(index, piece)
		_selected = null
		_selected_from = null
	_last_refusal = refusal
	_redraw()
	return refusal


# Coming OFF is always allowed -- the library is infinite, so there is nothing to refuse against.
func _judge_pull(mod: Item, _from: Object, _to: Object) -> String:
	return "" if mod is WeaponModData else "That is not a weapon mod."


func _perform_pull(mod: Item, _from: Object, _to: Object) -> String:
	var piece := mod as WeaponModData
	if piece != null:
		_weapon.unfit(piece)
	_selected = null
	_selected_from = null
	_last_refusal = ""
	_redraw()
	return ""


func _on_space_clicked(item: Item, _holder: Object, index: int) -> void:
	if _selected != null:
		_perform_fit(_selected, _selected_from, _weapon, index)
		return
	_pick(item, _weapon)


func _on_library_clicked(item: Item, _holder: Object) -> void:
	if _selected == null:
		_pick(item, null)
		return
	# Something in hand, clicked onto the library: take it off if it is on, otherwise this is putting
	# down what was picked up.
	if _weapon.space_holding(_selected) != -1:
		_perform_pull(_selected, _selected_from, null)
		return
	_clear_selection()


func _pick(item: Item, from: Object) -> void:
	var piece := item as WeaponModData
	if piece == null:
		return   # an empty space with nothing in hand is not a selection
	if piece == _selected:
		_clear_selection()
		return
	_last_refusal = ""
	_selected = piece
	_selected_from = from
	_redraw()


func _clear_selection() -> void:
	_selected = null
	_selected_from = null
	_last_refusal = ""
	_redraw()


func _refresh_hint() -> void:
	if _last_refusal != "":
		_hint.text = _last_refusal
		_hint.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_REFUSED_TEXT))
		return
	_hint.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
	if _selected == null:
		_hint.text = "Drag a mod into a space, or click it and click the space it should go in."
		return
	_hint.text = "%s in hand. Click a space to fit it, or the list to put it back." % _mod_name(_selected)


# --- closing -------------------------------------------------------------------------------------

func _on_close() -> void:
	closed.emit()
	queue_free()


# Esc drops what is in hand first, and only then closes -- the same two-step the screen underneath
# uses, so the key never does two things at once.
func _on_cancel() -> bool:
	if _selected != null:
		_clear_selection()
		return true
	_on_close()
	return true


# --- the affordance that opens it ----------------------------------------------------------------

# OCCUPIED SPACES over spaces (dev, 2026-09-06: "I like 1/3 mod spaces"). Counting MODS would be the
# other reading of that and it can print 4/3, since one capacity-3 space holds three size-1 mods.
# Null for anything with no spaces to open -- armour, a vial, a weapon whose template authors none.
#
# A BUTTON rather than a label, so its own press cannot become the row's pick-up: Godot's drag walk
# stops at the first MOUSE_FILTER_STOP under the cursor. The cost is that moving onto it fires the
# row's mouse_exited and clears the #745 hover preview while the pointer sits on the chip -- cosmetic,
# and cheaper than a label the row would have to special-case.
#
# It reads through space(), which GROWS the lazily-sized array (#624). Deliberate: that is the one
# door, and a second non-growing reader is exactly what that ticket should not be paid for here.
static func chip_for(item: Item) -> Button:
	var weapon := item as WeaponInstance
	if weapon == null or weapon.space_count() == 0:
		return null
	var filled := 0
	for i in range(weapon.space_count()):
		if not weapon.space(i).is_empty():
			filled += 1
	var chip := Button.new()
	chip.text = "%d/%d" % [filled, weapon.space_count()]
	chip.add_theme_font_size_override("font_size", 9)
	chip.focus_mode = Control.FOCUS_NONE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.tooltip_text = UiText.wrap("Fit mods — %d of %d spaces hold something." % [
		filled, weapon.space_count()])
	return chip
