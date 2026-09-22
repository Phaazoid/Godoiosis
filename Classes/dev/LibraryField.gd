class_name LibraryField
extends RefCounted

# Picking, naming, forking and deleting the SHARED LIBRARY RESOURCE one field of an authored
# resource points at (#900) -- the flow #808 built for an attack's stamp, extracted when the second
# library wanted every line of it.
#
# WHY IT IS ONE ANSWER RATHER THAN TWO COPIES. Six decisions live in here, none of them obvious and
# every one already paid for once: (none) must be row ZERO because add_item silently selects
# whatever it is handed; a HELD resource the library cannot name needs a row of its own, since it
# may be unsaved OR saved-and-since-deleted and the picker has to SHOW either; the editor edits a
# COPY of a named resource and the ORIGINAL of an unnamed one; Save As forks THIS holder and leaves
# every other one alone; a delete is REFUSED while anything still references it, a dangling
# ext_resource being a hard PARSE error that takes the whole referring file down; and the commit
# point is Update, so a shared edit reaches the board and the other holders together or not at all.
# A second copy of that would agree until one of them was taught something.
#
# THE CALLER KEEPS ITS OWN BODY. This draws the picker, the used-by caption and the save row; what
# sits between them -- a stamp grid, a page of knob rows -- is the caller's, which is the whole
# reason the flow splits into three draws rather than one.
#
# BOUND TO ONE FIELD, not to a property NAME: an attack's shape is a property and a look is a slot
# in a dictionary, and neither should be the other's special case, so the host hands over callables
# for reading and writing rather than a string.

# The three non-file rows, worded by the caller because a shape's "(none)" explains a different
# thing from a look's. Their ORDER is fixed here rather than by the caller, for the reason above.
var none_key := "(none)"
var new_key := "(new)"
var unnamed_key := "(unnamed -- Save as... to name it)"

# What this field is called in a sentence: "shape", "look". Every message and button reads it.
var noun := "resource"
# Where saved files of this kind live, for Save As.
var library_dir := ""

# The seams onto the host. `list` answers what the picker may offer (a look filters by element, so
# it is a callable rather than a catalog reference); `held`/`assign` read and write the one field;
# `make` builds a fresh unsaved one; `refresh` redraws the form after anything commits.
var list := Callable()
var held := Callable()
var assign := Callable()
var make := Callable()
var refresh := Callable()

var host: Control = null
var status: Label = null

# What the form edits: a COPY of a named library resource, or the held object itself when it is
# unnamed. Never the library object -- editing that would reach every other holder before Update
# and make Save As impossible, take_over_path moving the object they are all still holding.
var staged: Resource = null


func _init(p_host: Control, p_status: Label) -> void:
	host = p_host
	status = p_status


# Re-derive what the form edits from what is held. Called after every pick, every fork and every
# load; the one place the copy-vs-in-place rule is spelled.
#
# The copy is SHALLOW, and its Array fields are the held resource's own objects (measured, #1056):
# an editor must REPLACE an array on the copy, never clear or append to it, or the edit reaches the
# library file before Update. Every grid write already replaces.
func stage() -> void:
	staged = null
	var current := _held()
	if current == null:
		return
	staged = current.duplicate() as Resource if current.resource_path != "" else current


# The picker row. It returns nothing the caller needs: a selection commits through `assign` and the
# form is redrawn, so there is no widget state for anyone to hold.
func draw_picker(container: Node, label_text: String, tooltip := "") -> void:
	var library: Dictionary = list.call()
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	row.add_child(label)

	var keys := _keys(library)
	var picker := OptionButton.new()
	for k in keys:
		picker.add_item(k)
	picker.select(_row_index(keys, library))
	picker.item_selected.connect(func(idx: int) -> void: _pick(keys[idx], library))
	row.add_child(picker)
	container.add_child(row)
	DevWidgets.apply_tooltip(row, tooltip)


# Every FILE that names what is held, so an edit says out loud how far it reaches. Read off the repo
# rather than off a catalog: a referrer embedded in a mission or a rune is in no catalog, and those
# are exactly the ones a caption listing saved files alone would hide.
func draw_users(container: Node, alone_text: String) -> void:
	var path := _held_path()
	if path == "":
		DevWidgets.add_label(container, alone_text)
		return
	var users := ResourceCatalog.users_of(path)
	if users.is_empty():
		DevWidgets.add_label(container, "Used by nothing else yet.")
		return
	DevWidgets.add_label(container, "Used by %d file(s): %s -- editing this %s changes all of them."
		% [users.size(), ", ".join(users), noun])


# Name-and-fork, plus delete when there is a file to delete.
func draw_save_row(container: Node) -> void:
	if staged == null:
		return
	var row := HBoxContainer.new()
	var name_field := LineEdit.new()
	name_field.placeholder_text = "%s name" % noun
	name_field.custom_minimum_size = Vector2(160, 0)
	row.add_child(name_field)
	var save_as := Button.new()
	save_as.text = "Save %s as..." % noun
	save_as.pressed.connect(func() -> void: _save_as(name_field.text.strip_edges()))
	row.add_child(save_as)
	if _held_path() != "":
		var delete := Button.new()
		delete.text = "Delete %s" % noun
		delete.pressed.connect(_delete)
		row.add_child(delete)
	container.add_child(row)


# The clause an overwrite confirm appends when a NAMED library file is going to be written alongside
# whatever the panel is saving. An unnamed one rides inside the holder's own file and is not a
# second victim.
func victim_clause() -> String:
	var path := _held_path()
	if path == "":
		return ""
	var users := ResourceCatalog.users_of(path)
	var clause := " and the shared %s '%s'" % [noun, path.get_file()]
	if users.size() > 1:
		clause += " (used by %d files)" % users.size()
	return clause


# Write the staged copy back over the library file it came from, at the COMMIT point rather than at
# every keystroke. save_over adopts onto the object every other holder is still pointing at, so the
# shared edit lands for all of them at once. True when there was nothing to write.
func save_named() -> bool:
	var path := _held_path()
	if staged == null or path == "":
		return true
	return DevWidgets.save_over(staged, path, status)


func _held() -> Resource:
	return null if not held.is_valid() else held.call() as Resource


func _held_path() -> String:
	var current := _held()
	return "" if current == null else current.resource_path


# The rows, in the order they are added, so the index the picker reports maps straight back.
func _keys(library: Dictionary) -> Array[String]:
	var keys: Array[String] = [none_key, new_key]
	var named: Array[String] = []
	for k in library:
		named.append(k)
	named.sort()
	keys.append_array(named)
	if _is_unnamed(library):
		keys.append(unnamed_key)
	return keys


# Held, but not something the library can name: never saved, or saved and since deleted. Both are
# held resources, and the picker has to be able to SHOW one whatever its provenance.
func _is_unnamed(library: Dictionary) -> bool:
	return _held() != null and _library_key_for(library) == ""


func _row_index(keys: Array[String], library: Dictionary) -> int:
	if _held() == null:
		return 0
	if _is_unnamed(library):
		return keys.find(unnamed_key)
	return keys.find(_library_key_for(library))


# The library's name for what is held, "" if the library does not have it. Matched on resource_path
# rather than on identity: the catalog scan and the holder's own load are the same cached object
# today, but a path compare cannot be broken by a cache miss.
func _library_key_for(library: Dictionary) -> String:
	var path := _held_path()
	if path == "":
		return ""
	for k in library:
		var candidate: Resource = library[k]
		if candidate.resource_path == path:
			return k
	return ""


func _pick(key: String, library: Dictionary) -> void:
	match key:
		none_key:
			assign.call(null)
		new_key:
			# Unnamed, so the holder points straight at the staged object: there is no shared object
			# to protect yet, and it saves embedded until Save as... names it.
			assign.call(make.call())
		unnamed_key:
			pass   # already what is held; re-picking it is a no-op rather than a re-fork
		_:
			if library.has(key):
				assign.call(library[key])
	stage()
	refresh.call()


func _save_as(chosen_name: String) -> void:
	if staged == null:
		return
	if chosen_name == "":
		var msg := "Needs a name to save the %s" % noun
		push_warning(msg)
		status.text = msg
		return
	if DevWidgets.refuse_illegal_name(chosen_name, noun, status):
		return
	var path := library_dir + chosen_name + ".tres"
	if DevWidgets.refuse_existing_file(path, noun, status):
		return
	staged.set("display_name", chosen_name)
	if not DevWidgets.save_over(staged, path, status):
		return
	# save_over take_over_path'd it, so the staged object IS the library file now -- the holder adopts
	# it and the form moves onto a fresh copy of it. Only THIS holder re-points; every other user of
	# what it came from is untouched, which is what makes Save As a fork.
	assign.call(staged)
	stage()
	status.text = "Saved %s %s" % [noun, chosen_name]
	refresh.call()


func _delete() -> void:
	var path := _held_path()
	if path == "":
		return
	# A dangling ext_resource is a hard PARSE error that takes the whole referring file down, so a
	# file in use is refused rather than warned about (CLAUDE.md's ContentRepair edge).
	var users := ResourceCatalog.users_of(path)
	if not users.is_empty():
		var msg := "%s is used by %s -- re-point them first" % [path.get_file(), ", ".join(users)]
		push_warning(msg)
		status.text = msg
		return
	DevWidgets.confirm_delete(host, "%s '%s'" % [noun, path.get_file()], func() -> void:
		if DevWidgets.delete_saved_file(path, noun, status):
			assign.call(null)
			stage()
			refresh.call())
