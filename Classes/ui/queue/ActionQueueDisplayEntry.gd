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

# An INDENTED row is a DERIVED one -- an expanded volley's hits, or the watch shot a walk takes
# (#592). It is not an order anybody gave, so the panel draws it undraggable and with no X.
static func action_row(action_ref: BaseAction, indent := 0) -> ActionQueueDisplayEntry:
	var entry := ActionQueueDisplayEntry.new()
	entry.entry_type = EntryType.ACTION
	entry.action = action_ref
	entry.indent_level = indent
	return entry

# Section order: MOVE -> ATTACK -> each side-channel verb in registry order -> REACTION.
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

	_add_section(entries, "MOVE", move_actions, plan)
	_add_section(entries, "ATTACK", plan.attacks)

	# Side-channel sections in registry order — the header IS the enum name, so a newly
	# registered type gets its section for free.
	for type in BaseAction.SIDE_CHANNEL_ORDER:
		_add_section(entries, BaseAction.ActionType.keys()[type], side_channel.get(type, []))

	# Reactions last, in their own section — derived, not stored (Law #2). A skipped one (the
	# reactor went down/dead this pass) is hidden. Headed REACTION rather than COUNTER since #148:
	# the section holds both kinds, and a heal row reading "Alia heals Bern" under COUNTER lies.
	var live_reactions: Array[BaseAction] = []
	for reaction in plan.counters:
		if not reaction.resolved.skipped:
			live_reactions.append(reaction)
	_add_section(entries, "REACTION", live_reactions)

	# LAST, because it happens last (#419). Its own section rather than a row indented under MOVE:
	# the queue's order is the pass's clock, and a tile's damage lands after every order in it —
	# including for a unit that never moved at all.
	_add_section(entries, "END OF TURN", plan.tile_hits)

	return entries

# Appends a header plus its rows, preceded by a divider unless this is the first section on the
# panel. An empty batch contributes nothing at all — no header, no divider.
#
# A MOVE row is followed by a row per watch shot the walk takes (#413/#592) — see _watch_shots_for.
static func _add_section(entries: Array[ActionQueueDisplayEntry], title: String, batch: Array,
		plan: ResolvedPlan = null) -> void:
	if batch.is_empty():
		return
	if not entries.is_empty():
		entries.append(divider())
	entries.append(header(title))
	for action in batch:
		entries.append(action_row(action, 0))
		for shot: AttackAction in _watch_shots_for(plan, action):
			entries.append(action_row(shot, 1))


# What a queued walk WALKS INTO (#413), one row per hit, stacking when one route crosses several
# watches. Read off the resolve like every other row — plan.watch_shots already holds the derived
# shots with their outcomes, so nothing is recomputed here (R3/R8).
#
# They are ROWS rather than text (dev, 2026-08-27: "I'd like them to mirror the general action queue
# setup by just being another action queue row with the firing unit, the weapon icon, and the unit
# getting hit"). A watch shot IS an AttackAction, so it already answers every question a row asks --
# actor sprite, action icon, target sprite, the lethality rung -- and inherits the panel's own look,
# which is what the first attempt could not do: it appended text to `description_label`, hidden in
# ActionQueueRow.tscn since the panel's first version, and a visible label of its own then clashed
# with everything around it.
static func _watch_shots_for(plan: ResolvedPlan, action: BaseAction) -> Array[AttackAction]:
	var shots: Array[AttackAction] = []
	if plan == null or action == null or action.action_type != BaseAction.ActionType.MOVE:
		return shots
	for shot in plan.watch_shots:
		if shot.triggered_by != action.actor or shot.resolved == null or shot.resolved.skipped:
			continue
		shots.append(shot)
	return shots
