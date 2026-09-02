extends VBoxContainer
class_name DevInfoTool

# The Info page (#690) -- what the dev tools can tell you that a document cannot.
#
# Two halves, and the second is why this exists. The BINDINGS half is a pure projection of
# Classes/core/Controls.gd, the way GlossaryScreen is of Glossary: it reorders and styles, it never
# authors an entry. The MACHINE half is read at display time from the thing that already owns each
# fact -- the report folder from BugReporter, the version from Build, the branch from Checkout --
# so it is a second RENDER of one fact, never a second source.
#
# The machine half is the reason the ticket was filed: onboarding a co-dev to the camera trace,
# "where does my report land?" has no answer a markdown table can give, because the path differs
# per user and per OS. ProjectSettings.globalize_path() knows it exactly.
#
# Copy-to-clipboard rather than OS.shell_open on the paths: Explorer stealing focus is the
# two-OS-window trap, and the next dev key would go nowhere (see CLAUDE.md).

const NO_ACTION_TIP := "No Input Map action -- a hardcoded key check."
const ACTION_TIP := "Input Map action: %s"
const UPLOAD_ON := "configured -- F3 also reaches Discord"
const UPLOAD_OFF := "not configured -- F3 writes locally only"
const COPIED := "Copied"
const COPY := "Copy"
const LABEL_WIDTH := 150.0
const COPIED_SECONDS := 1.0

var _game   # untyped back-ref: game.gd has no class_name
var _rows: VBoxContainer
# Rebuilt on show rather than written into: the machine rows are four reads, and a rebuild is the
# same code path as the first build, so there is no second spelling to keep in step.
var _machine: VBoxContainer


# Built here rather than in _ready() for the reason every other tool is: children ready BEFORE the
# window that wires them, so `game` does not exist yet at _ready() time.
func init(game) -> void:
	_game = game
	_rows = DevWidgets.add_knob_scroll(self)
	_build_machine()
	_build_bindings()


# The window calls this when the page comes up. The checkout can change under a running game (he
# merges while it is open), so the branch line is read again rather than snapshotted at wiring.
func refresh_on_show() -> void:
	if _machine == null:
		return
	for child in _machine.get_children():
		_machine.remove_child(child)
		child.queue_free()
	_fill_machine()


func _build_machine() -> void:
	_header("This machine")
	_machine = VBoxContainer.new()
	_rows.add_child(_machine)
	_fill_machine()


func _fill_machine() -> void:
	_path_row("Report folder", ProjectSettings.globalize_path(BugReporter.REPORT_DIR),
		"Where F3 and the report card write. Each report is a timestamped folder holding report.md and its frames.")
	_path_row("Log file", ProjectSettings.globalize_path(BugReporter.LOG_PATH),
		"Godot's own log. A report carries its tail; this is the whole thing.")
	_fact_row("Checkout", Checkout.describe(), "The branch and commit this build was launched from.")
	_fact_row("Build", Build.version(), "project.godot's application/config/version -- the one store.")
	var reporter: BugReporter = null if _game == null else _game.bug_reporter
	var configured: bool = reporter != null and reporter.upload_configured()
	_fact_row("Report upload", UPLOAD_ON if configured else UPLOAD_OFF,
		"Whether a filed report is posted as well as written. Unconfigured is not a failure -- the folder above still fills.")


func _build_bindings() -> void:
	for value: int in Controls.Context.values():
		var context: Controls.Context = value
		_header(Controls.context_name(context))
		for entry: Dictionary in Controls.in_context(context):
			_binding_row(entry)


# --- Row builders ------------------------------------------------------------------------------

func _header(text: String) -> void:
	# No theme header variation: nothing in Classes/dev uses one, and a page inventing its own
	# heading style is how a window comes to look like four windows.
	DevWidgets.add_label(_rows, "-- %s --" % text)


# Key, condition and description in one row. The description AUTOWRAPS and expands: a fixed-width
# label here would set the page's minimum width, and tests/dev/test_dev_window_fit.gd measures the
# widest row against what the window leaves the page.
func _binding_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	var key := Label.new()
	key.text = entry["key"]
	key.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	key.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	row.add_child(key)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var when: String = entry["when"]
	if when != "":
		var cond := Label.new()
		cond.text = when
		cond.modulate = Color(1, 1, 1, 0.6)
		body.add_child(cond)
	var does := Label.new()
	does.text = entry["does"]
	does.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# An autowrap Label collapses to zero width in a container without the expand flag (#383).
	does.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(does)
	row.add_child(body)
	var action: String = entry["action"]
	DevWidgets.apply_tooltip(row, DevWidgets.wrap_tooltip(
		NO_ACTION_TIP if action == Controls.HARDCODED else ACTION_TIP % action))
	_rows.add_child(row)


func _fact_row(label_text: String, value: String, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	row.add_child(label)
	var value_label := Label.new()
	value_label.text = value
	value_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)
	DevWidgets.apply_tooltip(row, DevWidgets.wrap_tooltip(tip))
	_machine.add_child(row)
	return row


func _path_row(label_text: String, path: String, tip: String) -> void:
	var row := _fact_row(label_text, path, tip)
	var copy := Button.new()
	copy.text = COPY
	copy.tooltip_text = "Copy this path to the clipboard."
	copy.pressed.connect(func() -> void: _copy(path, copy))
	row.add_child(copy)


# The label flip is the only feedback a clipboard write can give: no dialog, no log line, and the
# path is already on screen beside it.
func _copy(text: String, button: Button) -> void:
	DisplayServer.clipboard_set(text)
	button.text = COPIED
	await get_tree().create_timer(COPIED_SECONDS).timeout
	if is_instance_valid(button):
		button.text = COPY
