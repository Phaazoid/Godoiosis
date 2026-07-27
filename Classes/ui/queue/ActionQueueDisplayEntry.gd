extends RefCounted
class_name ActionQueueDisplayEntry

# One row of the action-queue panel — a section header, a divider, or an action. Purely a view
# model: SquadActionQueueControl renders these and nothing else, so the panel never has to know
# how a plan is shaped.
#
# build_for() is the whole panel layout, moved out of SquadManager 2026-07-26 (it was formatting
# living in the squad domain). It takes an ALREADY-RESOLVED plan: resolution stays SquadManager's
# job, and rows only ever read `.resolved` rather than recomputing anything (R3/R8, Law #2).

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

# Section order: MOVE -> ATTACK -> each side-channel verb in registry order -> COUNTER.
static func build_for(squad: Squad, plan: ResolvedPlan) -> Array[ActionQueueDisplayEntry]:
	var entries: Array[ActionQueueDisplayEntry] = []

	var move_actions: Array[BaseAction] = []
	var side_channel: Dictionary[BaseAction.ActionType, Array] = {}
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.MOVE:
			move_actions.append(action)
		elif BaseAction.SIDE_CHANNEL_ORDER.has(action.action_type):
			if not side_channel.has(action.action_type):
				side_channel[action.action_type] = []
			side_channel[action.action_type].append(action)

	_add_section(entries, "MOVE", move_actions)
	_add_section(entries, "ATTACK", plan.attacks)

	# Side-channel sections in registry order — the header IS the enum name, so a newly
	# registered type gets its section for free.
	for type in BaseAction.SIDE_CHANNEL_ORDER:
		_add_section(entries, BaseAction.ActionType.keys()[type], side_channel.get(type, []))

	# Counters last, in their own section — derived, not stored (Law #2). A skipped counter
	# (the counterer went down/dead this pass) is hidden.
	var live_counters: Array[BaseAction] = []
	for counter in plan.counters:
		if not counter.resolved.skipped:
			live_counters.append(counter)
	_add_section(entries, "COUNTER", live_counters)

	return entries

# Appends a header plus its rows, preceded by a divider unless this is the first section on the
# panel. An empty batch contributes nothing at all — no header, no divider.
static func _add_section(entries: Array[ActionQueueDisplayEntry], title: String, batch: Array) -> void:
	if batch.is_empty():
		return
	if not entries.is_empty():
		entries.append(divider())
	entries.append(header(title))
	for action in batch:
		entries.append(action_row(action, 0))
