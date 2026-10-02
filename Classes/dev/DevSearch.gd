extends Object
class_name DevSearch

# The dev-tools search (#1184): an index of what the window SHOWS, and the ranking over it. Static
# and stateless; DevSearchBox asks, DevOverlay.reveal goes there.
#
# The index is read off the BUILT controls of every DevOverlay.LEAVES page, never off the knob
# tables -- a declared index would be a second answer to "what is on this page", blind to every
# hand-built page and reflective form, and a new page would need an entry to be found. Three kinds:
# a TAB is a leaf or the title of a sub-tab inside a page; a SECTION is a DevWidgets.add_heading
# label; a VALUE is the first Label of a row that also holds an input (an HBoxContainer, or one row
# of a GridContainer), or a CheckBox's own text. Only what is SHOWING on its page is offered: a row
# the page has hidden (the Playback filters, a reflective form's not-applicable fields) is skipped,
# while sitting on a tab that is not current is not held against it (dev ruling, 2026-10-01).

enum Kind { TAB, SECTION, VALUE }

const KIND_LABELS: Array[String] = ["TAB", "SECTION", "VALUE"]


# One entry per thing a search can land on: {kind, name, where, control}. `where` is the location
# shown beside the name; `control` is what DevOverlay.reveal brings into view.
static func index(overlay: DevOverlay) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for leaf: Dictionary in DevOverlay.LEAVES:
		var page := overlay.get_node(leaf["page"]) as Control
		var scope: String = leaf["scope"]
		var label: String = leaf["label"]
		entries.append(_entry(Kind.TAB, label, scope, page))
		var ctx := {"where": "%s / %s" % [scope, label], "short": label, "section": ""}
		_walk(page, ctx, entries)
	return _distinct(entries)


# Drops an entry the list could not tell apart from an earlier one (the Character page's six
# "Equip" boxes): it would only repeat a row that already leads to the same place.
static func _distinct(entries: Array[Dictionary]) -> Array[Dictionary]:
	var seen := {}
	var kept: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var key := "%d|%s|%s" % [entry["kind"], entry["name"], entry["where"]]
		if not seen.has(key):
			seen[key] = true
			kept.append(entry)
	return kept


# DFS in child order, which is reading order for these VBox-built pages, so "the section a row is
# in" is simply the last heading seen. A sub-tab starts its own context.
static func _walk(node: Node, ctx: Dictionary, entries: Array[Dictionary]) -> void:
	for child: Node in node.get_children():
		var control := child as Control
		if control == null:
			continue
		var tabs := node as TabContainer
		if tabs == null and not control.visible:
			continue   # hidden by its page -- not offered
		var child_ctx := ctx
		if tabs != null and tabs.tabs_visible:
			var title := tabs.get_tab_title(tabs.get_tab_idx_from_control(control))
			entries.append(_entry(Kind.TAB, title, ctx["where"], control))
			child_ctx = {"where": "%s › %s" % [ctx["where"], title],
				"short": "%s › %s" % [ctx["short"], title], "section": ""}
		elif control is Label and control.has_meta(DevWidgets.HEADING_META):
			var heading := _clean((control as Label).text)
			if heading != "":
				entries.append(_entry(Kind.SECTION, heading, ctx["where"], control))
				ctx["section"] = heading
		elif control is CheckBox or control is CheckButton:
			_add_value(_clean((control as Button).text), control, ctx, entries)
		elif control is HBoxContainer:
			var row_label := _row_label(control.get_children())
			if row_label != null:
				_add_value(_clean(row_label.text), control, ctx, entries)
		elif control is GridContainer:
			_add_grid_values(control as GridContainer, ctx, entries)
		_walk(control, child_ctx, entries)


# A grid packs label/input PAIRS into its rows (Spawn's stats run two to a row), so every Label whose
# next cell in the same row is an input names a value. Rows are runs of `columns` visible cells -- a
# hidden cell takes no place in the layout. A pair has no node of its own, so the label is revealed.
static func _add_grid_values(grid: GridContainer, ctx: Dictionary, entries: Array[Dictionary]) -> void:
	var cells: Array[Control] = []
	for child: Node in grid.get_children():
		if child is Control and (child as Control).visible:
			cells.append(child)
	var columns := maxi(grid.columns, 1)
	for i in cells.size() - 1:
		if cells[i] is Label and (i + 1) % columns != 0 and _is_input(cells[i + 1]):
			_add_value(_clean((cells[i] as Label).text), cells[i], ctx, entries)


static func _add_value(value_name: String, control: Control, ctx: Dictionary,
		entries: Array[Dictionary]) -> void:
	if value_name == "":
		return
	var where: String = ctx["short"]
	if ctx["section"] != "":
		where += " › " + String(ctx["section"])
	entries.append(_entry(Kind.VALUE, value_name, where, control))


# A row's name: its first Label, but only when the row also holds something to edit -- so a plain
# Button row, a status line or a slider's number readout is never a value.
static func _row_label(row: Array[Node]) -> Label:
	var label: Label = null
	var has_input := false
	for child: Node in row:
		if label == null and child is Label:
			label = child
		elif _is_input(child):
			has_input = true
	return label if has_input else null


static func _is_input(node: Node) -> bool:
	return node is Range or node is LineEdit or node is OptionButton \
		or node is CheckBox or node is CheckButton


static func _entry(kind: Kind, entry_name: String, where: String, control: Control) -> Dictionary:
	return {"kind": kind, "name": entry_name, "where": where, "control": control}


static func _clean(text: String) -> String:
	return text.strip_edges().trim_suffix(":").strip_edges()


# --- Ranking ----------------------------------------------------------------------------------

# Every query word must appear in the name or the location. Best first: the name starts with the
# query, then a word of the name starts with each query word, then the name merely contains them,
# then only the location matched. Ties: TAB, SECTION, VALUE, then the shorter name.
static func rank(entries: Array[Dictionary], query: String) -> Array[Dictionary]:
	var words := fold(query).split(" ", false)
	if words.is_empty():
		return []
	var scored: Array[Dictionary] = []
	for i in entries.size():
		var tier := match_tier(entries[i], words)
		if tier >= 0:
			scored.append({"entry": entries[i], "tier": tier, "order": i})
	scored.sort_custom(_better)
	var ranked: Array[Dictionary] = []
	for item: Dictionary in scored:
		ranked.append(item["entry"])
	return ranked


# -1 when the entry does not match at all; otherwise the tier described above (0 is best).
static func match_tier(entry: Dictionary, words: PackedStringArray) -> int:
	var entry_name := fold(entry["name"])
	var where := fold(entry["where"])
	var all_in_name := true
	for word in words:
		if not entry_name.contains(word):
			all_in_name = false
			if not where.contains(word):
				return -1
	if not all_in_name:
		return 3
	if entry_name.begins_with(words[0]):
		return 0
	var tokens := _tokens(entry_name)
	for word in words:
		if not tokens.any(func(token: String) -> bool: return token.begins_with(word)):
			return 2
	return 1


# Lower case, and "colour" reads as "color": the labels are spelled the British way.
static func fold(text: String) -> String:
	return text.to_lower().replace("colour", "color")


static var _word: RegEx = null

static func _tokens(text: String) -> Array[String]:
	if _word == null:
		_word = RegEx.create_from_string("[a-z0-9]+")
	var tokens: Array[String] = []
	for found in _word.search_all(text):
		tokens.append(found.get_string())
	return tokens


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if a["tier"] != b["tier"]:
		return a["tier"] < b["tier"]
	var a_entry: Dictionary = a["entry"]
	var b_entry: Dictionary = b["entry"]
	if a_entry["kind"] != b_entry["kind"]:
		return a_entry["kind"] < b_entry["kind"]
	var a_len := String(a_entry["name"]).length()
	var b_len := String(b_entry["name"]).length()
	if a_len != b_len:
		return a_len < b_len
	return a["order"] < b["order"]
