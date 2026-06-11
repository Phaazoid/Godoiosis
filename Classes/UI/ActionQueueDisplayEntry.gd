extends RefCounted
class_name ActionQueueDisplayEntry

enum EntryType {
	HEADER, 
	DIVIDER, 
	ACTION
}

var entry_type: EntryType
var label := ""
var action: BaseAction = null
var indent_level = 0

static func header(text: String) -> ActionQueueDisplayEntry:
	var entry := ActionQueueDisplayEntry.new()
	entry.entry_type = EntryType.HEADER
	entry.label = text
	return entry

static func divider() -> ActionQueueDisplayEntry:
	var entry := ActionQueueDisplayEntry.new()
	entry.entry_type = EntryType.DIVIDER
	return entry

static func action_row(action_ref: BaseAction, indent := 0) -> ActionQueueDisplayEntry:
	var entry := ActionQueueDisplayEntry.new()
	entry.entry_type = EntryType.ACTION
	entry.action = action_ref
	entry.indent_level = indent
	return entry
