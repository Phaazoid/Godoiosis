extends Control
class_name HoverInfoPanelControl

# The info card, one thing at a time. Since #1105 it is asked for by a CLICK, never by hover (dev,
# 2026-09-27: "Nothing on hover, at all"), which is why the name no longer describes it -- kept
# because slice 2 brings hover back as a player setting. Two faces:
#   - the UNIT card, while that unit's ring is up (MainActionMenu shows and clears it);
#   - the TILE card, a tile's full readout in TileInfoSections: a clicked empty tile, or the tile
#     an inspected unit stands on, parked beside the Inspect dock and FOLLOWING that unit, since the
#     dock stays open through Execute and a card fixed on the old cell would describe where it was.
# It parks on the screen half opposite what it describes; the caller pushes its left edge right of
# the docked inspect column (#68). Y comes from the live viewport and the card's own size, never a
# hardcoded pixel constant (the old BOTTOM_LEFT_POS=410 broke on a viewport-height change once).

const MARGIN := 8
const TILE_WIDTH := 300          # the Inspect dock's width, the size the dev approved in the mockup
const TILE_ICON_SIZE := Vector2i(32, 32)

# Injected by game (the board_source idiom), so this card never learns what a game is. The whole
# readout is read when the card (re)draws a cell; the sections alone on every frame after, since
# the tile's picture is built fresh on each read.
var tile_source: Callable            # (cell) -> TileReadout.Readout
var tile_sections_source: Callable   # (cell) -> Array[TileReadout.Section]

@onready var hover_panel: Panel = $HoverPanel
@onready var hover_gridcontainer = $HoverPanel/HoverInfoGridContainer

var current_unit: Unit
var _tile_panel: PanelContainer
var _tile_icon: TextureRect
var _tile_header: Label
var _sections: TileInfoSections
var _tile_cell := GridUtils.NO_CELL   # the cell the tile card describes, or NO_CELL
var _follow: Unit = null              # the unit whose cell the tile card follows, or null

# The last park's inputs, kept so a late layout pass can re-run it (see _on_tile_panel_resized).
var _park_bottom: bool = false
var _park_left_x: int = MARGIN

# Hidden while a cinematic pass owns the frame (#722), and what the CONTENT rule last decided.
# The flag lives in this gate rather than being written from outside, so a show mid-pass cannot
# put the card back over the cinematic.
var _hidden_for_playback := false
var _content_shown := false

# Set here rather than in the .tscn so UiLayers is the single answer for the whole UI stack --
# the scene used to author a bare 2, which agreed with the rest of the order only by luck.
# The tile card is code-built (data-shaped UI), and both faces wear QueueStyle's one frame (restyle), so
# they match each other and the palette by construction rather than by copied values.
func _ready() -> void:
	z_index = UiLayers.HOVER_PANEL
	_tile_panel = PanelContainer.new()
	_tile_panel.visible = false
	_tile_panel.custom_minimum_size.x = TILE_WIDTH
	var box := VBoxContainer.new()
	_tile_panel.add_child(box)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	box.add_child(header_row)
	_tile_icon = TextureRect.new()
	_tile_icon.custom_minimum_size = TILE_ICON_SIZE
	_tile_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tile_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tile_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	header_row.add_child(_tile_icon)
	_tile_header = Label.new()
	header_row.add_child(_tile_header)
	_sections = TileInfoSections.new()
	box.add_child(_sections)
	add_child(_tile_panel)
	# Autowrapped rows report the wrong minimum height until layout hands them their width, and that
	# can cascade across passes — so a park computed at show time can be wrong, and a bottom-parked
	# card overflows the screen edge (dev report, 2026-08-11). The card re-parks whenever its real
	# size settles; `resized` fires only on actual change, and re-parking never changes size, so this
	# cannot loop.
	_tile_panel.resized.connect(_on_tile_panel_resized)
	_tile_panel.minimum_size_changed.connect(_fit.call_deferred)
	restyle()

# The palette's chrome (#1105): both faces wear QueueStyle's frame and its inks, asked fresh here
# because nothing is pushed on a palette switch -- SettingsScreen calls this on close.
func restyle() -> void:
	var frame: StyleBox = QueueStyle.panel_box()
	hover_panel.add_theme_stylebox_override("panel", frame)
	_tile_panel.add_theme_stylebox_override("panel", frame)
	_tile_header.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.TITLE_TEXT))
	hover_gridcontainer.restyle()
	if is_showing_tile():
		_draw_tile(_tile_cell)

# The unit card alone. world_pos anchors the top-or-bottom parking decision.
func show_unit(unit: Unit, world_pos: Vector2, left_x: int = MARGIN) -> void:
	_tile_cell = GridUtils.NO_CELL
	_follow = null
	current_unit = unit
	hover_gridcontainer.set_unit(unit)
	hover_panel.visible = true
	_tile_panel.visible = false
	_content_shown = true
	_apply_visibility()
	_park(world_pos, left_x)

# A clicked tile's card.
func show_tile(cell: Vector2i, world_pos: Vector2, left_x: int = MARGIN) -> void:
	_follow = null
	_open_tile(cell, world_pos, left_x)

# The card for the tile a unit stands on, kept on that unit as it moves.
func show_tile_of(unit: Unit, left_x: int = MARGIN) -> void:
	_follow = unit
	_open_tile(unit.movement.cell, unit.global_position, left_x)

func clear() -> void:
	current_unit = null
	_tile_cell = GridUtils.NO_CELL
	_follow = null
	_content_shown = false
	_apply_visibility()

func is_showing_tile() -> bool:
	return _content_shown and _tile_cell != GridUtils.NO_CELL

func is_showing_tile_at(cell: Vector2i) -> bool:
	return is_showing_tile() and _tile_cell == cell

func is_showing_unit_card() -> bool:
	return _content_shown and current_unit != null

# What the tile card says, its name first -- empty unless a tile card is up.
func tile_texts() -> Array[String]:
	var said: Array[String] = []
	if not (visible and is_showing_tile()):
		return said
	said.append(_tile_header.text)
	said.append_array(_sections.drawn_texts())
	return said

# A tile card stays live: a watch firing, a claim landing or its unit walking changes it without a
# second click.
func _process(_delta: float) -> void:
	if not (visible and is_showing_tile()):
		return
	_fit()
	if _follow != null:
		if not is_instance_valid(_follow):
			clear()
			return
		if _follow.movement.cell != _tile_cell:
			_open_tile(_follow.movement.cell, _follow.global_position, _park_left_x)
			return
	if tile_sections_source.is_valid():
		var sections: Array[TileReadout.Section] = tile_sections_source.call(_tile_cell)
		_sections.show_if_changed(sections)

# #722's one input.
func set_hidden_for_playback(hidden: bool) -> void:
	_hidden_for_playback = hidden
	_apply_visibility()

func _apply_visibility() -> void:
	visible = _content_shown and not _hidden_for_playback

func _open_tile(cell: Vector2i, world_pos: Vector2, left_x: int) -> void:
	current_unit = null
	_tile_cell = cell
	hover_panel.visible = false
	_tile_panel.visible = true
	_tile_panel.position = Vector2.ZERO
	_content_shown = true
	_apply_visibility()
	_draw_tile(cell)
	_park(world_pos, left_x)

func _draw_tile(cell: Vector2i) -> void:
	var readout: TileReadout.Readout = tile_source.call(cell) if tile_source.is_valid() \
		else TileReadout.Readout.new()
	_tile_icon.texture = readout.icon
	_tile_icon.visible = readout.icon != null
	_tile_header.text = readout.title
	_tile_header.visible = readout.title != ""
	_sections.forget()
	_sections.show_if_changed(readout.sections)
	# NO reset_size() here, and that is the giant-card fix (2026-09-27): the rows were just rebuilt, so
	# their minimum is the tall one a wrapped row reports before layout hands it a width, and sizing to
	# it left a same-readout card 514px tall for 98 of content. _fit() sizes it once layout has run.

func _park(world_pos: Vector2, left_x: int) -> void:
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * world_pos
	_park_bottom = screen_pos.y <= get_viewport_rect().size.y / 2.0
	_park_left_x = left_x
	_apply_park()

func _apply_park() -> void:
	var y: int = MARGIN
	if _park_bottom:
		y = int(get_viewport_rect().size.y - _card_height() - MARGIN)
	position = Vector2(_park_left_x, y)

# The tile card is exactly as tall as what it says. Growing needs nothing -- a control is never
# smaller than its minimum -- but shrinking does, because a free-floating container never shrinks by
# itself (the 2026-08-11 ratchet). Two callers: the minimum-changed hook, deferred so it lands after
# the layout pass that moved the minimum and inside the same frame; and every frame a tile card is
# up, because that signal fires only on a change from the LAST value it reported, and a second tile
# with the same readout settles straight back to it (the giant card, dev report 2026-09-27).
func _fit() -> void:
	if _tile_panel.size.y > _tile_panel.get_combined_minimum_size().y:
		_tile_panel.reset_size()

# The tile card settled taller (or shorter) than the park estimated — land it again with the real
# number. The half decision is unchanged: it depends only on the anchor's position.
func _on_tile_panel_resized() -> void:
	if visible and _tile_panel.visible:
		_apply_park()

func _card_height() -> float:
	if hover_panel.visible:
		return hover_panel.size.y
	# The SIZE, never the minimum: straight after a redraw the minimum is the mid-layout one, and
	# parking on it put the giant card's contents off the top of the screen. The resized hook above
	# re-parks when the real size arrives.
	return _tile_panel.size.y
