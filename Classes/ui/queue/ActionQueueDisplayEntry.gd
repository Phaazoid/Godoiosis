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

# Extra lines the row carries UNDER its own description (#413). A deliberate divergence from how
# counters display, which get their own section: #412's whole payoff is dragging a move row and
# watching who eats the shot change, so the feedback has to live on the row being dragged.
var annotations: Array[String] = []

static func header(text: String) -> ActionQueueDisplayEntry:
	var entry := ActionQueueDisplayEntry.new()
	entry.entry_type = EntryType.HEADER
	entry.label = text
	return entry

static func divider() -> ActionQueueDisplayEntry:
	var entry := ActionQueueDisplayEntry.new()
	entry.entry_type = EntryType.DIVIDER
	return entry

static func action_row(action_ref: BaseAction, indent := 0, notes: Array[String] = []) -> ActionQueueDisplayEntry:
	var entry := ActionQueueDisplayEntry.new()
	entry.entry_type = EntryType.ACTION
	entry.action = action_ref
	entry.indent_level = indent
	entry.annotations = notes
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

	return entries

# Appends a header plus its rows, preceded by a divider unless this is the first section on the
# panel. An empty batch contributes nothing at all — no header, no divider.
static func _add_section(entries: Array[ActionQueueDisplayEntry], title: String, batch: Array,
		plan: ResolvedPlan = null) -> void:
	if batch.is_empty():
		return
	if not entries.is_empty():
		entries.append(divider())
	entries.append(header(title))
	for action in batch:
		entries.append(action_row(action, 0, _watch_notes(plan, action)))


# What a queued walk WALKS INTO (#413), one line per hit, stacking when one route crosses several
# watches. Read off the resolve like every other row — plan.watch_shots already holds the derived
# shots with their outcomes, so nothing is recomputed here (R3/R8).
static func _watch_notes(plan: ResolvedPlan, action: BaseAction) -> Array[String]:
	var notes: Array[String] = []
	if plan == null or action == null or action.action_type != BaseAction.ActionType.MOVE:
		return notes
	for shot in plan.watch_shots:
		if shot.triggered_by != action.actor or shot.resolved == null or shot.resolved.skipped:
			continue
		var watcher := "someone" if shot.actor == null or not is_instance_valid(shot.actor) else shot.actor.get_unit_name()
		var weapon := shot.fired_attack.display_name if shot.fired_attack != null else "a watch"
		# Who actually eats it: the crosser normally, an ally caught in the splash otherwise.
		if shot.target == null or not is_instance_valid(shot.target):
			notes.append("triggers %s's watch — %s fires" % [watcher, weapon])
		elif shot.target == action.actor:
			notes.append("triggers %s's watch — takes %d from %s" % [watcher, shot.resolved.damage, weapon])
		else:
			notes.append("triggers %s's watch — %s takes %d from %s"
					% [watcher, shot.target.get_unit_name(), shot.resolved.damage, weapon])
	return notes
