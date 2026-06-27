extends HBoxContainer
class_name ActionQueueRow

@onready var actor_texture: TextureRect = $ActorTexture
@onready var action_icon: TextureRect = $ActionIcon
@onready var target_texture: TextureRect = $TargetTexture
@onready var description_label: Label = $DescriptionLabel
@onready var cancel_button: Button = $CancelButton

const CROWN_ICON := preload("res://Art/Icons/CrownIcon.png")

const STATE_ICONS := {
	Elemental.State.WET: preload("res://Art/Icons/WetIcon.png"),
}

var action: BaseAction
var draggable := false
var is_volley_header := false
var _hovered := false

signal cancel_requested(action: BaseAction)
signal hover_changed(action: BaseAction, hovering: bool)
signal drag_requested(row: ActionQueueRow)

func setup(action_ref: BaseAction):
	action = action_ref

	actor_texture.texture = action.get_actor_texture()
	actor_texture.modulate = action.get_actor_modulate()
	# Squad leader keeps its own sprite; the crown rides behind it, shifted up like a hat.
	if action.actor != null and action.actor.is_leader() and action.actor.has_squad():
		_overlay_behind(actor_texture, CROWN_ICON, Vector2(0, -10))
		
	action_icon.texture = action.get_action_icon()
	target_texture.texture = action.get_target_texture()
	description_label.text = action.get_description()

	if action is AttackAction:
		var atk := action as AttackAction
		_show_elemental_overlays(atk)
		_show_hp_delta(atk)

	action_icon.modulate = action.get_ui_modulate()

	# The X keeps its slot on every row (so content stays aligned) but is inert on rows that
	# can't be cancelled: hold-position moves and derived counters (counters are computed, not
	# player orders — Law #2).
	var hide_cancel: bool = (action is MoveAction and action.is_hold_position) or action is CounterAttackAction
	if hide_cancel:
		cancel_button.modulate.a = 0.0
		cancel_button.disabled = true
		cancel_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		cancel_button.modulate.a = 1.0
		cancel_button.disabled = false
		cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP

	# The sprites must not eat pointer input, or the row never sees the press that starts a drag.
	actor_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE

	cancel_button.pressed.connect(_on_cancel_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_cancel_pressed():
	cancel_requested.emit(action)

func _on_mouse_entered():
	_hovered = true
	queue_redraw()
	hover_changed.emit(action, true)

func _on_mouse_exited():
	_hovered = false
	queue_redraw()
	hover_changed.emit(action, false)

func _draw() -> void:
	if _hovered:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.15))   # soft light behind the row

func _show_elemental_overlays(atk: AttackAction) -> void:
	if atk.resolved == null:
		return
	for state in atk.resolved.states_added:
		if STATE_ICONS.has(state):
			_overlay_behind(action_icon, STATE_ICONS[state], Vector2(0, -8))
	for icon in atk.resolved.reaction_icons:
		if icon != null:
			_overlay_behind(target_texture, icon)

func _overlay_behind(host: TextureRect, tex: Texture2D, pixel_offset := Vector2.ZERO) -> void:
	var bg := TextureRect.new()
	bg.texture = tex
	bg.show_behind_parent = true
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.offset_left += pixel_offset.x
	bg.offset_right += pixel_offset.x
	bg.offset_top += pixel_offset.y
	bg.offset_bottom += pixel_offset.y
	
func _show_hp_delta(atk: AttackAction) -> void:
	if atk.resolved == null:
		return
	# target_hp_after is threaded across the whole pass (R4): for the Nth hit it already accounts
	# for the earlier hits this combat. The raw number goes negative on a fatal hit, so the
	# DISPLAYED "after" is clamped by the lifecycle result -- a down/maim leaves HP at 1, a kill at 0.
	var raw_after: int = atk.resolved.target_hp_after
	var hp_before: int = raw_after + atk.resolved.damage
	var hp_after: int = raw_after
	match atk.resolved.lethality:
		ResolvedOutcome.Lethality.DOWNED, ResolvedOutcome.Lethality.MAIMED:
			hp_after = 1
		ResolvedOutcome.Lethality.KILLED:
			hp_after = 0

	var hp_label := Label.new()
	hp_label.text = "%d->%d" % [hp_before, hp_after]
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_label.add_theme_font_size_override("font_size", 9)

	# Team-color the readout: green when a friendly is losing HP, red for an enemy.
	var friendly := true
	if atk.target != null and is_instance_valid(atk.target):
		friendly = not Team.is_enemy(atk.target.get_faction(), Team.Faction.PLAYER)
	var hp_color := Color(0.4, 1.0, 0.4) if friendly else Color(1.0, 0.4, 0.4)
	hp_label.add_theme_color_override("font_color", hp_color)

	# Outline so the digits read over the sprite without stealing a row of height.
	hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hp_label.add_theme_constant_override("outline_size", 4)

	action_icon.add_child(hp_label)
	hp_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hp_label.offset_top = -12   # ride the bottom ~12px of the 32px icon, row height unchanged
	
func is_attack_row() -> bool:
	# Only real attacks reorder. Counters are AttackActions too, but they're derived and live in
	# their own (inert) section.
	return action is AttackAction and not action is CounterAttackAction

func _gui_input(event: InputEvent) -> void:
	# Draggable single attacks AND volley headers (collapsed header: drag to reorder / click to expand).
	if not (draggable or is_volley_header):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		drag_requested.emit(self)
		accept_event()
		
func setup_volley_summary(lead: AttackAction, count: int, expanded: bool) -> void:
	action = lead
	is_volley_header = true

	actor_texture.texture = lead.get_actor_texture()
	actor_texture.modulate = lead.get_actor_modulate()
	if lead.actor != null and lead.actor.is_leader() and lead.actor.has_squad():
		_overlay_behind(actor_texture, CROWN_ICON, Vector2(0, -12))

	# Plain attack icon (not the lead's lethality icon — the group has many outcomes).
	action_icon.texture = AttackAction.ATTACK_ICON
	action_icon.modulate = lead.get_ui_modulate()

	# The target slot becomes the hit-count + expand affordance.
	target_texture.texture = null
	var badge := Label.new()
	badge.text = ("[-] x%d" if expanded else "[+] x%d") % count
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", Color(1, 1, 1))
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	badge.add_theme_constant_override("outline_size", 4)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_texture.add_child(badge)
	badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Sprites must not eat the drag press.
	actor_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Cancelling the summary cancels the whole volley (it's one aim) — keep the X live.
	cancel_button.modulate.a = 1.0
	cancel_button.disabled = false
	cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP
	cancel_button.pressed.connect(_on_cancel_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
