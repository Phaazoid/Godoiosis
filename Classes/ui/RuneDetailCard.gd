class_name RuneDetailCard
extends ModalCard

# The rune detail card (#1019) -- what a rune HOLDS, and what each carving asks of whoever is carrying
# it. ModFittingCard's mirror one kind of gear over, reached by the same chip on the same rows.
#
# IT IS A DISPLAY AND NOTHING ELSE (dev, 2026-09-17: "let's just make it a display so that users know
# what they are equipping"). Carving is absent by DESIGN rather than deferred: inscription is ratified
# as BLIND, WORKSHOP-ONLY and IRREVERSIBLE, and offering it here would contradict all three at once --
# the card it mirrors fits and pulls freely, previews before committing, and lives in a phase with no
# workshop in it. The parity stops at display, and that is a boundary rather than a missing slice.
#
# THE ELEMENT DEMAND IS THE AURA RING (dev, on the mockups: "I think we can do a little better with
# showing what elements a thing needs, visually. Something like the circle around the units"), so
# there is no second widget: AuraRing grew `wanted` plus two tick states and this card hands it the
# picked carving. What the ring is NOT is a verdict -- it explains its own marks and judges nothing,
# so whether a carving actually channels is printed here, off the carving's own ladder.
#
# IT HAS BOTH OF QueueStyle'S GROUNDS, exactly as ModFittingCard does and for the same reason (#814):
# ModalCard's frame is panel_box(), dark under either palette, so the ring takes AUTHORED ink and the
# readout labels take the FRAME roles -- while the carvings list is a section box, i.e. paper under
# parchment, so its rows take NAME_TEXT and its cost bars take SKINNED. Ask which ground a mark is on.
#
# IT CLAIMS THE MODAL LOCK, like the card it mirrors: game.gd gates Tab and the commit key on
# ModalLock.any_open, so nothing can swap the board out from under it.

signal closed

const CARD_W := 600
# ...and how much of it ONE carving name may claim (#1024). Half, which is arithmetic rather than
# taste: the bars are guaranteed the other half whatever the dev writes into a display_name, and
# CARD_W is a MINIMUM on the card's content, so an unbounded name would widen the whole modal.
const NAME_MAX_W := CARD_W / 2.0
# The ring stands beside the plate at the PLATE's own height, which is why this is not a number of
# this file's own: two squares of one size read as a pair, and a hollow tick needs the radius to come
# out as an outline rather than as a smudge.
const RING_PX := ShapePlate.BOX_PX
const LIST_H := 168
# One cost mark per sigil. RECTANGLES, matching the ring's own bars (dev: "it should be the same
# rectangle shape as the ring for consistency instead of circles") -- one motif, twice on one card.
const COST_BAR := Vector2(4, 12)
# ...and carrying the ring's own THREE STATES (#1022). A bar is solid where the carrier's aura pays
# that sigil, hollow where it is asked for and unpaid, and lighter for a spare point past the recipe.
# The two numbers are the RING's, read off AuraRing where they exist, so the two motifs cannot drift;
# only these two have no tick equivalent to borrow, the hollow tick being an outline rather than a fill.
const HOLLOW_SWATCH_FILL := 0.14
const SPARE_ALPHA := 0.45

var _rune: RuneData
# Null for a rune nobody is holding -- one sitting in the stash. The ring then draws demand alone and
# every wielder-dependent readout drops out, rather than being computed against nobody.
var _wielder: Unit
var _carving: TransmutationData

var _picker: OptionButton
var _plate: ShapePlate
var _ring: AuraRing
var _headline: Label
var _damage: Label
var _range: Label
# Everything else this carving does that another on the same rune might not (#1017's enumeration).
# A VBox rather than a fixed set of Labels because the count is the carving's business, not the card's.
var _channels: VBoxContainer
var _aura: Label
var _list: VBoxContainer
var _hint: Label


static func open(game_node: Node, rune: RuneData, wielder: Unit) -> RuneDetailCard:
	var card := RuneDetailCard.new()
	card._rune = rune
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
	_build_legend(content)
	content.add_child(HSeparator.new())
	_build_list(content)

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
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


# The plate, the ring and the numbers, side by side: all three answer for the SAME picked carving, and
# picking another moves all three, so they have to be read together to be read at all.
#
# A LEGEND ROW SITS UNDER IT since #1022, reversing #1019's call that the ring's tooltip was enough
# (dev: *"it will be useful for the player, too"*). The earlier ruling was not wrong about the
# tooltip -- it is right there and it does word every mark -- it was wrong about who finds one.
func _build_readout(parent: Container) -> void:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 12)
	parent.add_child(strip)

	# AT FULL SIZE, deliberately: cropping the plate to buy the column some width was proposed and
	# turned down (dev: "Keeping the full size helps give a sense of scale").
	_plate = ShapePlate.new()
	strip.add_child(_plate)

	_ring = AuraRing.for_demand(_wielder, _sprite_of(_wielder), RING_PX)
	_ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_child(_ring)

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
	_picker.item_selected.connect(_on_carving_picked)
	column.add_child(_picker)

	_damage = _readout_label(column)
	_range = _readout_label(column)
	_channels = VBoxContainer.new()
	_channels.add_theme_constant_override("separation", 3)
	column.add_child(_channels)
	# The VERDICT, last, because everything above it is what the carving DOES and this is whether this
	# carrier can do it. It wraps rather than clipping: the anchor refusal names every element the
	# circle could open on, which is the half a player acts upon.
	_aura = _readout_label(column)
	_aura.clip_text = false
	_aura.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# WHAT THE RING'S MARKS MEAN, spelled out (dev, 2026-09-18: *"add the legend row that you included
# there, because it will be useful for the player, too"*). That REVERSES #1019's own call -- no legend,
# the ring's tooltip explains itself -- and it is recorded rather than flipped quietly, because the
# earlier ruling was a real one: a tooltip is found only by a player who already suspects there is
# something to find.
#
# THE RING'S OWN AUTHORED INKS AND ITS OWN ALPHAS, read off AuraRing rather than retyped, so a swatch
# and the mark it names cannot come out two different colours the day either is tuned. It sits on the
# card's FRAME, so the words take FRAME_TEXT while the swatches take the element wheel.
func _build_legend(parent: Container) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 11)
	row.add_theme_constant_override("v_separation", 2)
	parent.add_child(row)

	var fire := ElementPalette.color_for_element(Elemental.Element.FIRE)
	var air := ElementPalette.color_for_element(Elemental.Element.AIR)
	var aether := ElementPalette.color_for_element(Elemental.Element.AETHER)
	_legend_entry(row, _swatch_bar(fire, 1.0, false), "aura you hold")
	_legend_entry(row, _swatch_bar(air, HOLLOW_SWATCH_FILL, true), "asked for, unpaid")
	_legend_entry(row, _swatch_bar(fire, SPARE_ALPHA, false), "spare, powering it")
	_legend_entry(row, _swatch_bar(aether, AuraRing.DIM_ALPHA, false), "affinity, not grown")
	_legend_entry(row, _swatch_bar(ElementPalette.NEUTRAL, AuraRing.FAINT_ALPHA, false),
		"can never grow")
	_legend_entry(row, ArcSwatch.new(fire), "the cost")


func _legend_entry(parent: Container, swatch: Control, text: String) -> void:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 3)
	pair.add_child(swatch)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
	pair.add_child(label)
	parent.add_child(pair)


# One legend swatch, drawn as the ring's own rectangle so the key and the mark share a shape.
func _swatch_bar(tint: Color, alpha: float, outlined: bool) -> Control:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(tint, alpha)
	if outlined:
		box.border_color = tint
		box.set_border_width_all(1)
	var bar := Panel.new()
	bar.add_theme_stylebox_override("panel", box)
	bar.custom_minimum_size = Vector2(5, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar


# The cost's glyph, and the one legend mark that is not a rectangle -- because the cost is not one.
# A swatch that lied about its own shape would teach the wrong thing about the ring beside it.
class ArcSwatch extends Control:
	var tint := Color.WHITE

	func _init(colour: Color) -> void:
		tint = colour
		custom_minimum_size = Vector2(16, 12)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_arc(Vector2(size.x * 0.5, size.y - 1.0), size.x * 0.42, PI, TAU, 14, tint, 2.2, true)


# The carrier's map sprite, or nothing at all. A rune in the stash gets an EMPTY centre rather than a
# placeholder (dev's fork: demand only, nothing paid), and wherever there IS a carrier the character
# stays in the middle -- dev, on a mockup that moved a verdict in there: "if this is extending the
# Aura Ring, I think we need to keep it more consistent, and keep the character sprite in the center.
# Otherwise, it might be confusing what we're showing."
static func _sprite_of(unit: Unit) -> Texture2D:
	if unit == null or unit.unit_data == null:
		return null
	return unit.unit_data.map_sprite


func _readout_label(parent: Container) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
	label.clip_text = true
	parent.add_child(label)
	return label


# ONE list, where the card this mirrors has two. A weapon's second column is the mods it could take;
# a rune has no such list to show, because taking one is exactly what this card does not do.
func _build_list(parent: Container) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)

	var title := Label.new()
	title.text = "CARVINGS"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
	column.add_child(title)

	var back := PanelContainer.new()
	back.add_theme_stylebox_override("panel", QueueStyle.section_box())
	back.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(back)

	# PreMissionScreen._scroller's rule, and its reason: a ScrollContainer lays its child out at
	# COMBINED MINIMUM unless that child's horizontal flags carry SIZE_EXPAND, and every label here is
	# clip_text, so forgetting it renders as rows a pixel or two wide (#788).
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = LIST_H
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	back.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


# --- state ---------------------------------------------------------------------------------------

func refresh() -> void:
	_refresh_attacks()
	_refresh_readout()
	_refresh_carvings()
	_refresh_hint()


# THE WHOLE REPERTOIRE, never the channelable subset -- #166's law, which RuneData.choice_attacks
# already states: an unaffordable carving LISTS and greys with its reason rather than vanishing,
# because which of its gaps to close is the player's decision. Rebuilt whole, selection kept by
# IDENTITY so the picker stays where it was.
func _refresh_attacks() -> void:
	var carvings := _rune.inscriptions
	_picker.clear()
	var chosen := 0
	for i in range(carvings.size()):
		_picker.add_item(_carving_name(carvings[i]))
		_picker.set_item_metadata(i, carvings[i])
		if carvings[i] == _carving:
			chosen = i
	if carvings.is_empty():
		_picker.add_item("nothing carved")
		_carving = null
	else:
		_picker.select(chosen)
		_carving = carvings[chosen]
	_picker.disabled = carvings.size() < 2


func _on_carving_picked(index: int) -> void:
	_carving = _picker.get_item_metadata(index) as TransmutationData
	_refresh_readout()   # NOT refresh(): a rebuilt picker inside its own item_selected frees the emitter


func _refresh_readout() -> void:
	var size_word: String = RuneData.Size.keys()[_rune.size].capitalize()
	var carrier := "in the stash" if _wielder == null else "carried by %s" % _wielder.get_unit_name()
	_headline.text = "%s  ·  %s rune  ·  %s" % [_rune.shown_name(), size_word, carrier]

	_plate.show_attack(_carving)
	_ring.set_carving(_carving)
	# attack_detail scales off the WIELDER's aura, so a rune nobody holds shows no number rather than
	# a number computed against nobody.
	_damage.text = _rune.attack_detail(_wielder, _carving) \
		if _wielder != null and _carving != null else ""
	_damage.visible = _damage.text != ""
	_range.text = AttackChannelText.range_text(_carving)
	_range.visible = _range.text != ""
	_refresh_channels()
	_refresh_aura()


func _refresh_channels() -> void:
	_clear(_channels)
	for line in _channel_lines():
		var label := Label.new()
		label.text = line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
		_channels.add_child(label)


# A CARVING'S CHANNELS ARE ITS OWN. "A carving carries no mods" (TransmutationData's own note), so
# there is nothing to compose here and the authored field IS the composed answer -- the exact opposite
# of the weapon card, which is why AttackChannelText takes these four as parameters instead of looking
# any of them up. get_elements() is still the DERIVED set, since a flourish can turn Water into ICE.
func _channel_lines() -> Array[String]:
	if _carving == null:
		return [] as Array[String]
	return AttackChannelText.lines(_carving, _carving.knockback, _carving.get_elements(),
		_carving.can_overwatch, _carving.hits_allies)


# The channelling verdict, refusal or not -- ONE call, because aura_text asks the ladder first and
# builds its positive half only when that comes back empty. The ring beside it says the same thing in
# marks and structurally cannot disagree, both being read off the same two numbers.
#
# A RUNE NOBODY HOLDS HAS NO VERDICT: channeling is a property of the PAIRING, not of either half
# (RuneData's own note above attack_block_reason).
func _refresh_aura() -> void:
	if _carving == null or _wielder == null:
		_aura.text = ""
		_aura.visible = false
		return
	var refusal := _carving.channel_block_reason(_wielder, _rune.temper)
	var role: QueueStyle.Role = QueueStyle.Role.FRAME_REFUSED_TEXT if refusal != "" \
		else QueueStyle.Role.FRAME_TEXT
	_aura.text = _carving.aura_text(_wielder, _rune.temper)
	_aura.add_theme_color_override("font_color", QueueStyle.ink(role))
	_aura.visible = true


func _refresh_carvings() -> void:
	_clear(_list)
	if _rune.inscriptions.is_empty():
		var blank := Label.new()
		blank.text = "Nothing is carved on this rune yet."
		blank.add_theme_font_size_override("font_size", 11)
		blank.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.BODY_TEXT))
		_list.add_child(blank)
		return
	for carving: TransmutationData in _rune.inscriptions:
		_list.add_child(_carving_row(carving))


# A ROW SAYS HOW COMFORTABLY IT CHANNELS, in three states (dev: *"red for pressure spray since the
# unit cannot cast, yellow for zap cannon since it can only be cast with the extra slot, none for
# fireball since it can be comfortably cast"*). The rule is the LADDER's -- see
# TransmutationData.channel_state -- and this only paints it.
#
# THE TINT REPLACED A "!" LABEL. That mark said *refused* and nothing else, and with the whole row
# carrying validity it would have been the same fact twice, on the one axis the border already owns.
func _carving_row(carving: TransmutationData) -> Control:
	var state := carving.channel_state(_wielder, _rune.temper)
	var reason := _block_reason(carving)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", QueueStyle.channel_box(_box_state(state), false))
	var tip := "%s\n%s" % [carving.sigil_text(), _rune.attack_detail(_wielder, carving)] \
		if _wielder != null else carving.sigil_text()
	if reason != "":
		tip += "\n%s" % reason
	row.tooltip_text = UiText.wrap(tip)
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 1)
	row.add_child(body)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	body.add_child(line)

	# NO EXPAND on the name: the bars sit right beside it, and the row's slack trails after them both.
	# Giving the label the row was what flung them to the far edge (dev: "the bars in the titles are
	# right aligned"), which read as two unrelated columns rather than a name and what it costs.
	#
	# SO IT HAS TO ASK FOR ITS OWN TEXT, and #1024 is what the row looks like when it does not: a
	# clip_text Label declares a minimum width of ONE and an HBox gives a child exactly its minimum,
	# so every carving name shipped as a sliver of its first glyph. The clip and the CAP are the other
	# half -- CARD_W is a floor on the card, not a ceiling, so an unbounded name widens the modal.
	var name_label := Label.new()
	name_label.text = _carving_name(carving)
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 11)
	UiText.fit_width(name_label, 0.0, NAME_MAX_W)
	name_label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.NAME_TEXT))
	line.add_child(name_label)

	line.add_child(_cost_bars(carving))

	# WHAT IT DOES, underneath -- damage, kind, targets, and deliberately NOT the cost: the bars above
	# ARE the cost (dev). It needs a carrier, since the damage scales off their aura, so a stash rune's
	# rows are a name and its recipe alone.
	if _wielder != null:
		var detail := Label.new()
		detail.text = carving.effect_text(_wielder)
		detail.clip_text = true
		detail.add_theme_font_size_override("font_size", 9)
		detail.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
		body.add_child(detail)
	return row


# The DOMAIN's answer mapped onto the CHROME's. Two enums on purpose -- one is what the rule says, the
# other what a row looks like -- and an explicit match rather than a cast, so re-ordering either one
# is a compile-time conversation instead of a silently wrong colour.
static func _box_state(state: TransmutationData.Channel) -> QueueStyle.Channel:
	match state:
		TransmutationData.Channel.REFUSED:
			return QueueStyle.Channel.REFUSED
		TransmutationData.Channel.WILDCARD:
			return QueueStyle.Channel.WILDCARD
	return QueueStyle.Channel.CLEAR


# The recipe as MARKS, one bar per sigil, carrying the RING'S OWN THREE STATES (#1022): solid where
# this carrier's aura pays that sigil, hollow where it is asked for and unpaid, and a lighter bar past
# a `+` for each spare point. Shipped flat at #1019, which is why they said so little -- the shape was
# right and the vocabulary was missing.
#
# THE POOL IS WALKED DOWN A COPY, sigil by sigil, so a 2-Fire recipe against Fire 1 draws one paid bar
# and one hollow rather than two of either -- the ring's own per-tick rule, one surface along.
#
# SKINNED, because these sit on the list's paper, where the ring above takes AUTHORED off the card's
# own dark frame. Two grounds on one card is #814's rule, not an inconsistency.
func _cost_bars(carving: TransmutationData) -> Control:
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 2)
	bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var left: Dictionary[Elemental.Element, int] = {}
	for element: Elemental.Element in carving.distinct_elements():
		left[element] = _wielder.get_element_aura(element) if _wielder != null else 0
	for element: Elemental.Element in carving.sigils:
		var paid: bool = left.get(element, 0) > 0
		if paid:
			left[element] = left[element] - 1
		bars.add_child(_cost_bar(element, 1.0 if paid else HOLLOW_SWATCH_FILL, not paid))

	# What is LEFT after paying is the spare -- the halo's own number, said again in the list so the
	# ring and the row cannot disagree about how much is going spare.
	var spare: Array[Elemental.Element] = []
	for element: Elemental.Element in carving.distinct_elements():
		for _i in range(maxi(0, left.get(element, 0))):
			spare.append(element)
	if not spare.is_empty():
		var plus := Label.new()
		plus.text = "+"
		plus.add_theme_font_size_override("font_size", 9)
		plus.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
		plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bars.add_child(plus)
		for element: Elemental.Element in spare:
			bars.add_child(_cost_bar(element, SPARE_ALPHA, false))
	return bars


func _cost_bar(element: Elemental.Element, alpha: float, outlined: bool) -> Control:
	var tint := QueueStyle.element_ink(element)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(tint, alpha)
	if outlined:
		box.border_color = tint
		box.set_border_width_all(1)
	var bar := Panel.new()
	bar.add_theme_stylebox_override("panel", box)
	bar.custom_minimum_size = COST_BAR
	return bar


# THE RUNE'S OWN ANSWER, never a second one: attack_block_reason delegates to the carving with THIS
# rune's temper, which the carving cannot know on its own. Nobody carrying it means nobody for it to
# be refused by, so every row on a stash rune is plain.
func _block_reason(carving: TransmutationData) -> String:
	if _wielder == null:
		return ""
	return _rune.attack_block_reason(_wielder, carving)


# What this rune has room for and what it is locked to -- the two facts no carving can answer. The
# temper is PERMANENT, set by the first carving, so "not tempered yet" is the one state in which that
# choice is still open, and it is worth saying out loud rather than leaving the line blank.
func _refresh_hint() -> void:
	var parts: Array[String] = ["%d of %d capacity spent"
		% [_rune.used_capacity(), _rune.capacity()]]
	if _rune.temper == Elemental.Element.NONE:
		parts.append("not tempered — the first carving sets that, permanently")
	else:
		parts.append("tempered in %s" % Elemental.display_name(_rune.temper))
	_hint.text = "  ·  ".join(parts)


# A carving with no authored name still has a recipe, and a recipe reads better than "unnamed" --
# shown_name()'s own rule, one resource over: a kind that reads its name from somewhere else says so.
static func _carving_name(carving: TransmutationData) -> String:
	if carving == null:
		return ""
	return carving.display_name if carving.display_name != "" else carving.sigil_text()


static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()


# --- closing -------------------------------------------------------------------------------------

func _on_close() -> void:
	closed.emit()
	queue_free()


# Nothing is ever in hand here, so Esc has one job -- where the fitting card's has two.
func _on_cancel() -> bool:
	_on_close()
	return true


# --- the affordance that opens it ----------------------------------------------------------------

# The same chip a weapon row carries (#732, dev: "the little 1/3 on the far right of a weapon"),
# reading CAPACITY rather than spaces: a large rune holding two triples reads 6/6, which is the number
# that decides whether anything else could ever go on it.
#
# A BLANK RUNE GETS ONE TOO (dev), and that is where this parts from ModFittingCard.chip_for, which
# answers null for a weapon with no spaces. "0/1" is how a player learns a rune is blank without
# equipping it and reading the refusal off the gate.
static func chip_for(item: Item) -> Button:
	var rune := item as RuneData
	if rune == null:
		return null
	# The CHROME is ItemDetail's since #1022 -- only the COUNT is this kind's own business.
	return ItemDetail.chip("%d/%d" % [rune.used_capacity(), rune.capacity()],
		"What this rune holds — %d of %d capacity spent." % [
			rune.used_capacity(), rune.capacity()])
