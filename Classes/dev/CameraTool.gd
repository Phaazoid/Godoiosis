extends VBoxContainer
class_name CameraTool

# The Camera page (#705 slice 3): what the camera is doing right now, and the key poses the dev has
# recorded against it.
#
# A PROJECTION with no store of its own. The shot table is the director's own row liveness
# (ShotDirector.live_rows, the clauses solve() ranks), the View line and the trace are the sources
# battle3d pushes at BugReporter -- so the page reads exactly what a report filed this moment would
# say -- and the recording is battle3d's. Polled only while the window is up and this page is showing
# (ScenarioHeader's gate). The trace is rewritten a few times a second rather than every frame: its
# times count back from now, so its text changes constantly.
#
# On WALL-CLOCK time, because the page matters most while the dev pause holds Engine.time_scale at 0,
# and a _process delta is scaled by it.

const TRACE_PERIOD_MSEC := 250
const NO_HOST := "No 3D host -- the camera lives in the Battle3D view, and a flat Main.tscn launch has none."
const PAUSED := "PAUSED (P) -- the director is standing down and the camera is yours. N records a key pose."
const PLAYING := "Playback owns the camera. P pauses it."
const RESTING := "The camera is the player's -- no pass is playing."
const EMPTY_RECORDING := "Nothing recorded. Pause a pass with P, frame the shot you want, press N."
const TABLE_NOTE := "Highest lit row wins. NONE is lit only while playback does not own the camera."
const JUMP_TIP := "Cut the camera to this key pose. Only while paused -- otherwise the director would take it straight back."
const LIVE_COLOR := Color(0.55, 1.0, 0.6)
const DARK_COLOR := Color(1, 1, 1, 0.35)
const TRACE_HEIGHT := 260.0

var _game   # untyped back-ref: game.gd has no class_name
var _host: Node3D = null
var _rows: VBoxContainer
var _status: Label
var _shot_labels: Array[Label] = []
var _view: Label
var _trace: TextEdit
var _keys: VBoxContainer
var _clear_all: Button
var _seen_version := -1
var _seen_paused := false
var _trace_due_msec := 0


func init(game) -> void:
	_game = game
	_rows = DevWidgets.add_knob_scroll(self)
	_build()
	refresh()


# Pushed by DevOverlay.attach_3d_host. The window is built before the host, so this arrives after init.
func attach_host(host: Node3D) -> void:
	_host = host
	_seen_version = -1
	refresh()


func _process(_delta: float) -> void:
	var window := get_window()
	if window == null or not window.visible or not is_visible_in_tree():
		return
	refresh()


func refresh() -> void:
	if _rows == null:
		return
	var paused := Pacing.dev_paused()
	_status.text = NO_HOST if not _has_host() else (PAUSED if paused
			else PLAYING if _game.camera_controller.playback_locked else RESTING)
	_draw_table()
	_view.text = _source_text("view_source")
	var now := Time.get_ticks_msec()
	if now >= _trace_due_msec:
		_trace_due_msec = now + TRACE_PERIOD_MSEC
		_draw_trace(_source_text("trace_source"))
	var recording := _recording()
	var version := -2 if recording == null else recording.version
	if version != _seen_version or paused != _seen_paused:
		_seen_version = version
		_seen_paused = paused
		_draw_recording(recording, paused)


# --- Building ------------------------------------------------------------------------------------

func _build() -> void:
	_status = _wrapped(_rows, "")
	DevWidgets.add_heading(_rows, "Shot table")
	for value: int in ShotDirector.Shot.values():
		var label := Label.new()
		_rows.add_child(label)
		_shot_labels.append(label)
	var note := _wrapped(_rows, TABLE_NOTE)
	note.modulate = DARK_COLOR
	DevWidgets.add_heading(_rows, "View")
	_view = _wrapped(_rows, "")
	DevWidgets.apply_tooltip(_view, DevWidgets.wrap_tooltip(
		"The View line a bug report filed now would carry: the channels, the live holds and the frame floor."))
	DevWidgets.add_heading(_rows, "Trace")
	_trace = TextEdit.new()
	_trace.editable = false
	_trace.focus_mode = Control.FOCUS_NONE   # never focusable, so the dev keys keep working from here
	_trace.custom_minimum_size = Vector2(0, TRACE_HEIGHT)
	_trace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	_trace.add_theme_font_override("font", mono)
	_rows.add_child(_trace)
	DevWidgets.add_heading(_rows, "Recording")
	_keys = VBoxContainer.new()
	_rows.add_child(_keys)
	_clear_all = Button.new()
	_clear_all.text = "Clear all"
	_clear_all.tooltip_text = "Drop every key pose (Shift+N does the same)."
	_clear_all.pressed.connect(_on_clear_all)
	_rows.add_child(_clear_all)


func _wrapped(container: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # an autowrap Label collapses without it (#383)
	container.add_child(label)
	return label


# --- Drawing -------------------------------------------------------------------------------------

func _draw_table() -> void:
	var director: ShotDirector = _host.shots() if _has_host() else null
	for value: int in ShotDirector.Shot.values():
		var label := _shot_labels[value]
		var lit: bool = director != null and director.live_rows[value]
		var active: bool = director != null and director.active == value
		label.text = "%s %s" % ["▶" if active else "  ", ShotDirector.Shot.keys()[value]]
		label.modulate = LIVE_COLOR if lit else DARK_COLOR


# The trace arrives as a report section, fences and all; the page shows what is inside them. Rewritten
# in place, keeping the reader's scroll unless they were at the bottom, where the newest rows land.
func _draw_trace(text: String) -> void:
	var lines: PackedStringArray = []
	for line in text.split("\n"):
		if line != "```":
			lines.append(line)
	var shown := "\n".join(lines).strip_edges()
	if shown == _trace.text:
		return
	var following := _trace.get_last_full_visible_line() >= _trace.get_line_count() - 1
	var kept := _trace.scroll_vertical
	_trace.text = shown
	_trace.scroll_vertical = _trace.get_line_count() if following else kept


# Rebuilt only when the recording or the pause changes -- never from inside a row's own button, so a
# Delete never frees the node that is still emitting (#741).
func _draw_recording(recording: CameraRecording, paused: bool) -> void:
	for child in _keys.get_children():
		_keys.remove_child(child)
		child.queue_free()
	var empty := recording == null or recording.is_empty()
	_clear_all.disabled = empty
	if empty:
		_wrapped(_keys, EMPTY_RECORDING)
		return
	for key in recording.keyframes:
		var row := HBoxContainer.new()
		var line := " → ".join(key.line) if not key.line.is_empty() else "-"
		var shot := key.shot + ("" if key.trained == "" else " (%s)" % key.trained)
		var label := _wrapped(row, "K%d   %.2fs   %s   %s" % [key.index, key.pass_time, shot, line])
		label.tooltip_text = "Pass time is game seconds since the pass began; it stands still while paused."
		var index := key.index
		var jump := Button.new()
		jump.text = "Jump to"
		jump.disabled = not paused
		jump.tooltip_text = JUMP_TIP
		jump.pressed.connect(func() -> void: _host.jump_to_keyframe(index))
		row.add_child(jump)
		var delete := Button.new()
		delete.text = "Delete"
		delete.tooltip_text = "Drop this key pose; the ones after it move up a number."
		delete.pressed.connect(func() -> void: _host.delete_keyframe(index))
		row.add_child(delete)
		_keys.add_child(row)


func _on_clear_all() -> void:
	if _has_host():
		_host.clear_keyframes()


# --- Reads ---------------------------------------------------------------------------------------

func _has_host() -> bool:
	return is_instance_valid(_host) and _host.has_method("shots") and _game != null


func _recording() -> CameraRecording:
	return _host.recording() if _has_host() else null


# A source battle3d pushed at BugReporter, called as the report would call it; "" when unpushed.
func _source_text(source: String) -> String:
	if _game == null or _game.bug_reporter == null:
		return ""
	var pushed: Callable = _game.bug_reporter.get(source)
	if not pushed.is_valid():
		return ""
	var text: String = pushed.call()
	return text
