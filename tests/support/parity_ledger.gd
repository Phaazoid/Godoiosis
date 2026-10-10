# The PARITY LEDGER (#1236): every member of every feature list the game has, and how the headless
# Play API and the AI each answer it. tests/law/test_play_parity.gd and test_ai_parity.gd read it,
# and red on a member with no row, which is the tripwire: add a ring verb, a tile state or a
# ResolvedOutcome field and CI names it, and the file to declare it in, until somebody does.
#
# PRELOADED, not class_name'd (squad_fixtures.gd's convention):
#   const Ledger := preload("res://tests/support/parity_ledger.gd")
#
# A row states a stance per COLUMN, "play" and "ai":
#   covered(file, token)  handled, and `file` contains `token` -- the law reads the file and checks.
#   never(reason)         not wanted, by design.
#   gap(issue, note)      owed. Keeps CI green on purpose: the AI is permanently behind the feature
#                         set (#117), so red-until-built would hold every feature on AI work. The flag
#                         is that the feature's own diff has to WRITE this row.
#   action_type(t)        a ring verb that queues ActionType t: its answer is that type's row (Play)
#                         or AIArchetype's tables (AI), never a second one here.
# A column that already handles a whole list for free is declared ONCE on the axis (`play_all` /
# `ai_all`), and a row may then not restate it -- a new member trips nothing, because nothing needs
# updating.
#
# `covered` proves the code MENTIONS the member, not that it handles it well: the per-mechanic suites
# stay the behaviour check. Where a claim can be asked of the code directly it is (tile-state hazards,
# gas rules, lose-condition wording, the AI's builder arms), in the law suites.
extends RefCounted

enum Stance { COVERED, NEVER, GAP, ACTION_TYPE }

const BRIDGE := "res://play/play_bridge.gd"
const SESSION := "res://play/play_session.gd"
const VIEW := "res://play/board_view.gd"
const TACTICS := "res://Classes/ai/AITactics.gd"
const CONTROLLER := "res://Classes/ai/AIController.gd"
const ARCHETYPE := "res://Classes/ai/AIArchetype.gd"
const RUSHDOWN := "res://Classes/ai/RushdownArchetype.gd"
const SENTRY := "res://Classes/ai/SentryArchetype.gd"
const RULES := "res://Classes/board/RulesService.gd"

const NOT_SCORED := "not a score term: the score prices the mission, removals, splits, saves, limbs and damage (ai-tactics.md)"
const IN_DAMAGE := "priced through the damage and states it produces"
const ANIMATION := "animation plumbing: no rule reads it and no readout shows it"
const HOVER := "a hover, which a text view has no equivalent of"
const UI_ONLY := "a UI page with nothing to play"
const KIT_AUTHORED := "an enemy fights with the kit it was authored with"
const NO_HUD := "the AI acts through queue_action, never through the HUD"


# ---- stances ----------------------------------------------------------------------------------

static func covered(file: String, token: String) -> Dictionary:
	return {"stance": Stance.COVERED, "file": file, "token": token}

# A bridge command: covered when the bridge has an arm spelled exactly this way.
static func cmd(name: String) -> Dictionary:
	return covered(BRIDGE, '"%s"' % name)

static func never(reason: String) -> Dictionary:
	return {"stance": Stance.NEVER, "reason": reason}

static func gap(issue: String, note: String) -> Dictionary:
	return {"stance": Stance.GAP, "issue": issue, "note": note}

static func action_type(type: BaseAction.ActionType) -> Dictionary:
	return {"stance": Stance.ACTION_TYPE, "type": type}

# Tile-state AI stances, checked against RulesService.occupant_damage_for -- what _is_hazard reads.
static func hazard() -> Dictionary:
	var s := covered(TACTICS, "occupant_damage_for")
	s["harms"] = true
	return s

static func harmless(reason: String) -> Dictionary:
	var s := never(reason)
	s["harms"] = false
	return s

# A gas with no rules at all: checked against GasRules.for_kind, so the day it gains some this reds.
static func inert() -> Dictionary:
	var s := never("no rules: a look only")
	s["inert"] = true
	return s


# ---- the axes ---------------------------------------------------------------------------------
# Each is {name, members: Array, label: Callable(member) -> String, rows: Dictionary} plus the
# optional `play_all` / `ai_all` axis-level stances.

static func axes() -> Array[Dictionary]:
	return [
		ring_verbs(), action_types(), gear_verbs(), hud_doors(), board_keys(),
		outcome_fields(), plan_lists(),
		tile_states(), gases(), weathers(), winds(), zone_kinds(), objectives(), lose_conditions(), lethality_rungs(),
		ground_kinds(), element_states(),
	]

static func _enum_label(keys: Array) -> Callable:
	return func(member: Variant) -> String: return String(keys[int(member)])

static func _string_label() -> Callable:
	return func(member: Variant) -> String: return String(member)


# The action ring's verbs, MainActionMenu.ACTION_DATA (the pre-mission ring offers a subset).
static func ring_verbs() -> Dictionary:
	var names := {}
	var consts: Dictionary = (MainActionMenu as Script).get_script_constant_map()
	for key: StringName in consts:
		if MainActionMenu.ACTION_DATA.has(consts[key]):
			names[consts[key]] = String(key)
	var T := BaseAction.ActionType
	return {
		"name": "ring verbs (MainActionMenu.ACTION_DATA)",
		"members": MainActionMenu.ACTION_DATA.keys(),
		"label": func(member: Variant) -> String: return String(names.get(member, str(member))),
		"rows": {
			MainActionMenu.MOVE: {"play": cmd("move"), "ai": covered(TACTICS, "queue_group_move")},
			MainActionMenu.GROUP_MOVE: {"play": cmd("group_move"), "ai": covered(TACTICS, "queue_group_move")},
			MainActionMenu.ATTACK: {"play": action_type(T.ATTACK), "ai": action_type(T.ATTACK)},
			# Its secondaries fire by name through `attack`; its weapon verbs are action-type rows.
			MainActionMenu.WEAPON_ACTION: {"play": action_type(T.ATTACK), "ai": action_type(T.ATTACK)},
			MainActionMenu.TRANSMUTATION: {"play": action_type(T.ATTACK), "ai": action_type(T.ATTACK)},
			MainActionMenu.GUARD: {"play": action_type(T.GUARD), "ai": action_type(T.GUARD)},
			MainActionMenu.RESCUE: {"play": action_type(T.RESCUE), "ai": action_type(T.RESCUE)},
			MainActionMenu.CAPTURE: {"play": action_type(T.CAPTURE), "ai": action_type(T.CAPTURE)},
			MainActionMenu.WAIT: {"play": cmd("wait"),
					"ai": never("a squad with nothing worth doing simply holds")},
			MainActionMenu.SQUADUP: {"play": cmd("join"), "ai": covered(CONTROLLER, "squads_up")},
			MainActionMenu.JOINSQUAD: {"play": cmd("join"), "ai": covered(CONTROLLER, "func regroup")},
			MainActionMenu.LEAVESQUAD: {"play": cmd("leave"),
					"ai": never("it regroups by joining (#1230); it never breaks a squad on purpose")},
			MainActionMenu.DISBAND_SQUAD: {"play": cmd("disband"),
					"ai": never("it regroups by joining (#1230); it never breaks a squad on purpose")},
			MainActionMenu.REPOSITION: {"play": cmd("reposition"),
					"ai": never("the pre-mission phase is the player's; the mission places the enemy")},
			MainActionMenu.UNDEPLOY: {"play": cmd("undeploy"),
					"ai": never("the pre-mission phase is the player's; the mission places the enemy")},
			MainActionMenu.INSPECT: {"play": cmd("focus"), "ai": never("a read; the AI reads the board directly")},
		},
	}


# Every order a unit queues: a move and the main actions. A weapon's signature verb lands here, not
# on the ring (it is a branch in MainActionMenu._weapon_children). DERIVED types (counters, tile
# hits, sinks) are nobody's order and are not members.
static func action_types() -> Dictionary:
	var members: Array = [BaseAction.ActionType.MOVE]
	members.append_array(BaseAction.MAIN_ACTION_TYPES)
	var T := BaseAction.ActionType
	return {
		"name": "queueable action types (MOVE + BaseAction.MAIN_ACTION_TYPES)",
		"members": members,
		"label": _enum_label(T.keys()),
		# Pinned already, per archetype, by test_ai_action_coverage.gd; test_ai_parity adds the
		# builder-arm check on top.
		"ai_all": covered(ARCHETYPE, "MAIN_ACTION_PRIORITY"),
		"rows": {
			T.MOVE: {"play": cmd("move")},
			T.ATTACK: {"play": cmd("attack")},
			T.RESCUE: {"play": cmd("rescue")},
			T.RELOAD: {"play": cmd("reload")},
			T.REV: {"play": cmd("rev")},
			T.BURROW: {"play": cmd("burrow")},
			T.CAPTURE: {"play": cmd("capture")},
			T.GUARD: {"play": cmd("guard")},
			T.OVERWATCH: {"play": cmd("overwatch")},
		},
	}


# The inspect dock's verbs.
static func gear_verbs() -> Dictionary:
	var V := GearVerbs.Verb
	return {
		"name": "gear verbs (GearVerbs.Verb)",
		"members": V.values(),
		"label": _enum_label(V.keys()),
		"play_all": covered(BRIDGE, "GearVerbs.from_name"),
		"rows": {
			V.EQUIP: {"ai": never(KIT_AUTHORED)},
			V.UNEQUIP: {"ai": never(KIT_AUTHORED)},
			V.WEAR: {"ai": never(KIT_AUTHORED)},
			V.REMOVE_ARMOR: {"ai": never(KIT_AUTHORED)},
			V.USE: {"ai": gap("#117", "an enemy never uses a vial; inert while none carries one")},
			V.TOSS: {"ai": never(KIT_AUTHORED)},
		},
	}


# The HUD's doors: what a player presses that is not a unit's verb -- every signal the four surfaces
# raise, and every choice the two menus offer.
static func hud_doors() -> Dictionary:
	var members: Array = []
	var scripts: Array[Script] = [SquadActionQueueControl, EndTurnButton, PreMissionCard, MissionSelectScreen]
	for script: Script in scripts:
		for sig: Dictionary in script.get_script_signal_list():
			members.append("%s.%s" % [script.get_global_name(), sig["name"]])
	for choice: Variant in PauseMenu.Choice.keys():
		members.append("PauseMenu.%s" % choice)
	for choice: Variant in MissionEndBanner.Choice.keys():
		members.append("MissionEndBanner.%s" % choice)
	return {
		"name": "HUD doors (queue panel, End Turn, pre-mission card, title screen, pause menu, mission banner)",
		"members": members,
		"label": _string_label(),
		"ai_all": never(NO_HUD),
		"rows": {
			"SquadActionQueueControl.execute_requested": {"play": cmd("execute")},
			"SquadActionQueueControl.cancel_requested": {"play": gap("#46",
					"the row's X drops ONE order; headless `cancel` drops all of a unit's")},
			"SquadActionQueueControl.reorder_requested": {"play": gap("#46",
					"queue order is the pass clock; headless orders only by the order they were queued")},
			"SquadActionQueueControl.row_clicked": {"play": never("re-plans that row: cancel, then order again")},
			"SquadActionQueueControl.row_hover_changed": {"play": never(HOVER)},
			"EndTurnButton.end_turn_requested": {"play": cmd("endturn")},
			"PreMissionCard.deploy_toggled": {"play": cmd("deploy")},
			"PreMissionCard.gear_clicked": {"play": cmd("give")},
			"PreMissionCard.gear_hovered": {"play": never(HOVER)},
			"PreMissionCard.gear_unhovered": {"play": never(HOVER)},
			"PreMissionCard.job_picked": {"play": cmd("job")},
			"PreMissionCard.detail_requested": {"play": cmd("kit")},
			"MissionSelectScreen.mission_chosen": {"play": cmd("load")},
			"MissionSelectScreen.load_game_chosen": {"play": cmd("load")},
			"MissionSelectScreen.sandbox_chosen": {"play": cmd("new")},
			"MissionSelectScreen.glossary_chosen": {"play": never(UI_ONLY)},
			"MissionSelectScreen.settings_chosen": {"play": never(UI_ONLY)},
			"MissionSelectScreen.credits_chosen": {"play": never(UI_ONLY)},
			"MissionSelectScreen.feedback_chosen": {"play": never("a report is the player's channel to the dev")},
			"MissionSelectScreen.quit_chosen": {"play": cmd("quit")},
			"PauseMenu.RESUME": {"play": never("nothing is ever paused headlessly")},
			"PauseMenu.RESTART": {"play": cmd("restart")},
			"PauseMenu.TITLE": {"play": never("a headless run has no title screen; `load` replaces the board")},
			"PauseMenu.GLOSSARY": {"play": never(UI_ONLY)},
			"PauseMenu.REPORT": {"play": never("a report is the player's channel to the dev")},
			"PauseMenu.QUIT": {"play": cmd("quit")},
			"PauseMenu.SAVE_GAME": {"play": never("a headless run's record is its log; save slots are the player's")},
			"PauseMenu.LOAD_GAME": {"play": cmd("load")},
			"PauseMenu.SETTINGS": {"play": never(UI_ONLY)},
			"MissionEndBanner.RETRY": {"play": cmd("restart")},
			"MissionEndBanner.MISSION_SELECT": {"play": cmd("load")},
			"MissionEndBanner.STAY": {"play": never("nothing to do: the board just stays")},
		},
	}


# The board's hotkeys (Controls.ENTRIES, Context.BOARD). Camera keys have nothing to play.
static func board_keys() -> Dictionary:
	var members: Array = []
	for entry: Dictionary in Controls.ENTRIES:
		if entry["context"] == Controls.Context.BOARD:
			members.append(_key_label(entry))
	return {
		"name": "board hotkeys (Controls.ENTRIES, Context.BOARD)",
		"members": members,
		"label": _string_label(),
		"ai_all": never(NO_HUD),
		"rows": {
			"Left-click": {"play": never("opens the ring or picks a cell; what it picks are their own rows")},
			"Right-click": {"play": gap("#46", "undoes the last gesture; headless `cancel` drops a unit's whole plan")},
			"Escape": {"play": never("opens the pause menu; its choices are their own rows")},
			"V": {"play": cmd("ranges")},
			# #1038: which unit's ring is up; headless names the unit in every verb and has no selection.
			"F": {"play": never("selects the next squadmate; headless names units directly")},
			"Shift+F": {"play": never("selects the previous squadmate; headless names units directly")},
			"Alt (hold)": {"play": cmd("terrain")},
			"F3": {"play": never("a report is the player's channel to the dev")},
			"Shift+click | On an enemy": {"play": cmd("ranges")},
			"Right-click | After a move order": {"play": never("re-plans the move: cancel, then move again")},
			# #929: which attack the aim shows; headless names the attack, and equips through its gear verb.
			"F | Aiming": {"play": never("cycles the attack being aimed; headless names the attack directly")},
			"Shift+F | Aiming": {"play": never("cycles the attack being aimed; headless names the attack directly")},
			"Tab | Deploying": {"play": never("swaps the loadout screen and the board; headless reads both")},
			"Enter | Deploying": {"play": cmd("begin")},
			"Left-click | Deploying": {"play": cmd("deploy")},
			# #545: playback speed, nothing a rule reads. Headless resolves a pass with no playback at all.
			"Shift (hold) | During playback": {"play": never("speeds up playback, which headless does not have")},
			"Space | During playback": {"play": never("skips playback, which headless does not have")},
			"Click / Space / Enter | In dialog": {"play": never("dialog never plays headlessly")},
		},
	}

static func _key_label(entry: Dictionary) -> String:
	var when: String = entry["when"]
	return String(entry["key"]) if when == "" else "%s | %s" % [entry["key"], when]


# Every consequence the resolver predicts for one hit: does the Play API print it, does the AI's
# score price it. A new mechanic almost always arrives as a field here.
static func outcome_fields() -> Dictionary:
	return {
		"name": "ResolvedOutcome fields",
		"members": script_vars(ResolvedOutcome.new()),
		"label": _string_label(),
		"rows": {
			"base_damage": {"play": never("the row prints the damage dealt"), "ai": never(NOT_SCORED)},
			"damage": {"play": covered(SESSION, "r.damage"), "ai": covered(TACTICS, ".damage")},
			"heal_amount": {"play": covered(SESSION, "hp_restored"),
					"ai": never("a heal is priced off hp_before and target_hp_after")},
			"states_added": {"play": covered(SESSION, ".states_added"), "ai": covered(TACTICS, ".states_added")},
			"states_removed": {"play": covered(SESSION, ".states_removed"), "ai": never(NOT_SCORED)},
			"state_turns": {"play": never("the game's row shows the state, not its clock"), "ai": never(NOT_SCORED)},
			"popups": {"play": never("each popup has its own event line (insulated, holds, falls, drowns, void)"),
					"ai": never(ANIMATION)},
			"fired_reactions": {"play": covered(SESSION, ".fired_reactions"), "ai": never(IN_DAMAGE)},
			"elements": {"play": gap("#46", "the queue row's element rail is not printed"), "ai": never(IN_DAMAGE)},
			"target_hp_after": {"play": covered(SESSION, ".target_hp_after"), "ai": covered(TACTICS, ".target_hp_after")},
			"knockback_applied": {"play": covered(SESSION, ".knockback_applied"),
					"ai": never("a shove is priced by what it does: the counter it denies, the fall, the drowning")},
			"knockback_from": {"play": never(ANIMATION), "ai": never(ANIMATION)},
			"knockback_to": {"play": covered(SESSION, ".knockback_to"),
					"ai": never("a shove is priced by what it does: the counter it denies, the fall, the drowning")},
			"knockback_path": {"play": never(ANIMATION), "ai": never(ANIMATION)},
			"knockback_landing_index": {"play": never(ANIMATION), "ai": never(ANIMATION)},
			"knockback_held": {"play": covered(SESSION, ".knockback_held"), "ai": never(NOT_SCORED)},
			"burned_vial": {"play": covered(SESSION, ".burned_vial"), "ai": never(NOT_SCORED)},
			"charge_spent": {"play": covered(SESSION, ".charge_spent"), "ai": never(NOT_SCORED)},
			"cancels_watch": {"play": never("the game shows it as the watch going away, which the unit line mirrors"),
					"ai": never(NOT_SCORED)},
			"brace_bonus": {"play": never("no live game surface shows it: get_outcome_summary has no caller"),
					"ai": never(IN_DAMAGE)},
			"kind": {"play": gap("#46", "the queue row's damage-kind line is not printed"), "ai": never(IN_DAMAGE)},
			"mitigation": {"play": gap("#46", "the queue row's 'DEF n subtracted' line is not printed"),
					"ai": never(IN_DAMAGE)},
			"fall_damage": {"play": never("folded into the damage; the fall prints as 'falls N'"), "ai": never(IN_DAMAGE)},
			"fall_levels": {"play": covered(SESSION, ".fall_levels"), "ai": never(IN_DAMAGE)},
			"insulated": {"play": covered(SESSION, ".insulated"), "ai": never(IN_DAMAGE)},
			"drown_damage": {"play": covered(SESSION, ".drown_damage"), "ai": never(IN_DAMAGE)},
			"removed": {"play": covered(SESSION, ".removed"), "ai": never("a void removal reads as KILLED through lethality")},
			"splits": {"play": covered(SESSION, ".splits"), "ai": covered(TACTICS, ".splits")},
			"relinks": {"play": never("the tether animation; the split it follows prints"), "ai": never(ANIMATION)},
			"lethality": {"play": covered(SESSION, ".lethality"), "ai": covered(TACTICS, ".lethality")},
			"severed_limb": {"play": covered(SESSION, ".severed_limb"), "ai": covered(TACTICS, ".severed_limb")},
			"skipped": {"play": covered(SESSION, ".skipped"), "ai": covered(CONTROLLER, ".skipped")},
			"iron_will_held": {"play": never("a presentation beat; the HP it leaves prints"), "ai": never(IN_DAMAGE)},
			"hp_before": {"play": covered(SESSION, ".hp_before"), "ai": covered(TACTICS, ".hp_before")},
			"reads_hp": {"play": covered(SESSION, ".reads_hp"), "ai": never("a display flag")},
			"elevation_delta": {"play": never("no live game surface shows it: get_outcome_summary has no caller"),
					"ai": never("no rule reads it yet")},
		},
	}


# The plan's lists: the resolver's whole answer for a pass.
static func plan_lists() -> Dictionary:
	return {
		"name": "ResolvedPlan lists",
		"members": script_vars(ResolvedPlan.new()),
		"label": _string_label(),
		"rows": {
			"attacks": {"play": covered(SESSION, ".attacks"), "ai": covered(TACTICS, ".attacks")},
			"counters": {"play": covered(SESSION, ".counters"), "ai": covered(TACTICS, ".counters")},
			"cell_effects": {"play": covered(SESSION, ".cell_effects"), "ai": gap("#117", "lingering deposits are not priced")},
			"tile_hits": {"play": covered(SESSION, ".tile_hits"),
					"ai": gap("#117", "the end-of-turn burn and steam's soak are not scored (ending on burning ground is avoided through _is_hazard)")},
			"sinks": {"play": covered(SESSION, ".sinks"), "ai": covered(TACTICS, ".sinks")},
			# A ward's substitution prints on the row it redirects.
			"guards": {"play": covered(SESSION, "blocked_for"), "ai": never("a ward's substitution is already in the outcomes the score reads")},
			"watches": {"play": gap("#46", "a queued watch's footprint is drawn by the game, not by the preview"),
					"ai": never("a watch's shots are in watch_shots, which the score reads")},
			# The preview's rows nest each watch shot under the order that sets it off.
			"watch_shots": {"play": covered(SESSION, "ActionQueueDisplayEntry.build_for"), "ai": covered(TACTICS, ".watch_shots")},
			"hypo": {"play": never("the resolver's working state, not a consequence"), "ai": covered(TACTICS, ".hypo")},
		},
	}


# A tile's standing state. NONE is the sentinel and a RETIRED state never appears on a board.
static func tile_states() -> Dictionary:
	var members: Array = []
	for state: int in Terrain.TileState.values():
		if state != Terrain.TileState.NONE and not Terrain.RETIRED_STATES.has(state):
			members.append(state)
	var S := Terrain.TileState
	return {
		"name": "tile states (Terrain.TileState)",
		"members": members,
		"label": _enum_label(S.keys()),
		"rows": {
			S.BURNING: {"play": covered(VIEW, "is_burning"), "ai": hazard()},
			S.FROZEN: {"play": covered(VIEW, "TileState.FROZEN"), "ai": harmless("ice is ground: movement reads it through can_traverse")},
			S.COVER: {"play": covered(VIEW, "TileState.COVER"), "ai": harmless("its DEF is in the outcomes the score reads")},
			S.SCORCHED: {"play": covered(VIEW, "TileState.SCORCHED"), "ai": harmless("spent fuel: nothing left to burn")},
		},
	}


static func gases() -> Dictionary:
	var K := Gas.Kind
	return {
		"name": "gases (Gas.Kind)",
		"members": K.values(),
		"label": _enum_label(K.keys()),
		"play_all": covered(SESSION, "Gas.kinds_in"),
		"rows": {
			K.STEAM: {"ai": gap("#117", "the AI is blind to steam's soak (terrain.md)")},
			K.SMOKE: {"ai": inert()},
			K.POISON: {"ai": inert()},
			K.FROST: {"ai": inert()},
			K.THUNDER: {"ai": inert()},
			K.SULFUR: {"ai": inert()},
		},
	}


# The winds a board may name (#1286). CALM is left out the way CLEAR is: it blows nothing. A look only --
# nothing a rule reads, so neither the Play API nor the AI has anything to answer. The day a wind gains
# a rule (#277's Tempest row), these two lines are what has to change.
static func winds() -> Dictionary:
	var members: Array = []
	for kind: int in Wind.Kind.values():
		if kind != Wind.Kind.CALM:
			members.append(kind)
	return {
		"name": "winds (Wind.Kind)",
		"members": members,
		"label": _enum_label(Wind.Kind.keys()),
		"play_all": never("a look only: nothing headless draws the wind"),
		"ai_all": never("a look only: no rule reads the wind"),
		"rows": {},
	}


# The weathers a board may name (#1260). CLEAR is left out the way a NONE is: it does nothing.
static func weathers() -> Dictionary:
	var members: Array = []
	for kind: int in Weather.Kind.values():
		if kind != Weather.Kind.CLEAR:
			members.append(kind)
	var K := Weather.Kind
	var blind := gap("#117", "the AI is blind to rain's soak, as it is to steam's (terrain.md)")
	return {
		"name": "weathers (Weather.Kind)",
		"members": members,
		"label": _enum_label(K.keys()),
		"play_all": covered(SESSION, "scenario_data.weather"),
		"rows": {
			K.LIGHT_RAIN: {"ai": blind},
			K.RAIN: {"ai": blind},
			K.HEAVY_RAIN: {"ai": blind},
			K.THUNDERSTORM: {"ai": blind},
			K.LIGHT_SNOW: {"ai": inert()},
			K.SNOW: {"ai": inert()},
			K.BLIZZARD: {"ai": inert()},
			K.MIST: {"ai": inert()},
			K.FOG: {"ai": inert()},
			K.THICK_FOG: {"ai": inert()},
			K.FAINT_AURORA: {"ai": inert()},
			K.AURORA: {"ai": inert()},
			K.AETHERIC_STORM: {"ai": inert()},
			K.DUST: {"ai": inert()},
			K.SANDSTORM: {"ai": inert()},
			K.DUST_WALL: {"ai": inert()},
			K.LIGHT_ASHFALL: {"ai": inert()},
			K.ASHFALL: {"ai": inert()},
			K.ASH_STORM: {"ai": inert()},
		},
	}


static func zone_kinds() -> Dictionary:
	var K := ZoneManager.Kind
	return {
		"name": "zone kinds (ZoneManager.Kind)",
		"members": K.values(),
		"label": _enum_label(K.keys()),
		"rows": {
			K.PATROL: {"play": never("drawn only while authoring, or on hovering a sentry"),
					"ai": covered(SENTRY, "_zone_set")},
			K.CAPTURE: {"play": covered(VIEW, "Kind.CAPTURE"),
					"ai": never("ruling 6 (#117, 2026-10-04): capture points are the player's goals")},
			K.EXTRACTION: {"play": covered(VIEW, "Kind.EXTRACTION"), "ai": never("the player's goal, as ruling 6 rules a capture point")},
			K.DEPLOYMENT: {"play": covered(VIEW, "Kind.DEPLOYMENT"), "ai": never("the player's placement, before the battle")},
			K.DEFEND: {"play": covered(VIEW, "Kind.DEFEND"), "ai": covered(RUSHDOWN, "Kind.DEFEND")},
		},
	}


static func objectives() -> Dictionary:
	var O := MissionRules.Objective
	return {
		"name": "objectives (MissionRules.Objective)",
		"members": O.values(),
		"label": _enum_label(O.keys()),
		"rows": {
			O.ROUT: {"play": covered(VIEW, "Objective.ROUT"), "ai": never("the player's goal; the AI fights whatever the objective")},
			O.CAPTURE: {"play": covered(VIEW, "Objective.CAPTURE"),
					"ai": never("ruling 6 (#117, 2026-10-04): capture points are the player's goals")},
			O.EXTRACT: {"play": covered(VIEW, "Objective.EXTRACT"), "ai": never("the player's goal, as ruling 6 rules a capture point")},
		},
	}


# Play's column is asked of the code in the law: every member has defeat_reason wording, which is
# what the board view's FAIL IF lines print.
static func lose_conditions() -> Dictionary:
	var L := MissionRules.LoseCondition
	var members: Array = L.values()
	members.erase(L.NONE)
	return {
		"name": "lose conditions (MissionRules.LoseCondition)",
		"members": members,
		"label": _enum_label(L.keys()),
		"play_all": covered(VIEW, "MissionRules.defeat_reason"),
		"rows": {
			L.SQUAD_LOST: {"ai": covered(TACTICS, "func _plan_removes")},
			L.ROUND_LIMIT: {"ai": never("the clock is the player's pressure; the predictability law keeps the AI from stalling for it")},
			L.POINT_LOST: {"ai": covered(RUSHDOWN, "Kind.DEFEND")},
			L.PROTECTED_UNIT_LOST: {"ai": covered(TACTICS, "PROTECTED_UNIT_LOST")},
		},
	}


static func lethality_rungs() -> Dictionary:
	var L := ResolvedOutcome.Lethality
	var members: Array = L.values()
	members.erase(L.NONE)
	return {
		"name": "lethality rungs (ResolvedOutcome.Lethality)",
		"members": members,
		"label": _enum_label(L.keys()),
		"rows": {
			L.DOWNED: {"play": covered(SESSION, "Lethality.DOWNED"), "ai": covered(TACTICS, "func _plan_removes")},
			L.KILLED: {"play": covered(SESSION, "Lethality.KILLED"), "ai": covered(TACTICS, "func _plan_removes")},
			L.CRISIS: {"play": covered(SESSION, "Lethality.CRISIS"), "ai": covered(TACTICS, "Lethality.CRISIS")},
		},
	}


# What a cell's ground IS. Water draws as shallow or deep by walkability.
static func ground_kinds() -> Dictionary:
	var K := Terrain.Kind
	return {
		"name": "ground kinds (Terrain.Kind)",
		"members": K.values(),
		"label": _enum_label(K.keys()),
		"ai_all": covered(RULES, "static func movement_cost"),
		"rows": {
			K.NONE: {"play": covered(VIEW, '"none":')},
			K.GRASS: {"play": covered(VIEW, '"grass":')},
			K.MUD: {"play": covered(VIEW, '"mud":')},
			K.ROCK: {"play": covered(VIEW, '"rock":')},
			K.TREE: {"play": covered(VIEW, '"tree":')},
			K.WATER: {"play": covered(VIEW, '"shallow":')},
			K.DIRT: {"play": covered(VIEW, '"dirt":')},
			K.VOID: {"play": covered(VIEW, '"void":')},
			K.TALL_GRASS: {"play": covered(VIEW, '"tall_grass":')},
		},
	}


static func element_states() -> Dictionary:
	var S := Elemental.State
	var members: Array = S.values()
	members.erase(S.NONE)
	return {
		"name": "element states (Elemental.State)",
		"members": members,
		"label": _enum_label(S.keys()),
		"play_all": covered(VIEW, "unit.element_states"),
		"ai_all": covered(TACTICS, ".states_added"),
		"rows": {},
	}


# ---- the checks the two law suites share ------------------------------------------------------
# Each takes an optional axis list, so a suite can hand one a made-up axis and watch it fire. Empty
# means the real ledger.

static func _or_all(list: Array[Dictionary]) -> Array[Dictionary]:
	return axes() if list.is_empty() else list

# The text of one function in a source file: from its signature to the next top-level func.
static func function_body(path: String, signature: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	var start := text.find(signature)
	if start < 0:
		return ""
	var stop := text.find("\nstatic func ", start + signature.length())
	var stop_inst := text.find("\nfunc ", start + signature.length())
	if stop < 0 or (stop_inst >= 0 and stop_inst < stop):
		stop = stop_inst
	return text.substr(start, stop - start) if stop >= 0 else text.substr(start)

# The script's own vars, by reflection -- what a new field on the resolver's records arrives as.
static func script_vars(object: Object) -> Array:
	var names: Array = []
	for prop: Dictionary in object.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(prop["name"])
	return names

# Every member with no stance for this column, named with where to declare it. The tripwire.
static func undeclared(column: String, list: Array[Dictionary] = []) -> Array[String]:
	var out: Array[String] = []
	for axis: Dictionary in _or_all(list):
		if axis.has(column + "_all"):
			continue
		var rows: Dictionary = axis["rows"]
		var label: Callable = axis["label"]
		for member: Variant in axis["members"]:
			var row: Dictionary = rows.get(member, {})
			if not row.has(column):
				out.append("%s: %s" % [axis["name"], label.call(member)])
	return out

# Rows naming a member the game no longer has, and rows restating a column the axis declares whole.
static func stale_rows(column: String, list: Array[Dictionary] = []) -> Array[String]:
	var out: Array[String] = []
	for axis: Dictionary in _or_all(list):
		var members: Array = axis["members"]
		var label: Callable = axis["label"]
		for member: Variant in axis["rows"]:
			var row: Dictionary = axis["rows"][member]
			if not members.has(member):
				out.append("%s: a row for '%s', which is no longer a member" % [axis["name"], label.call(member)])
			elif axis.has(column + "_all") and row.has(column):
				out.append("%s: %s restates the %s stance the axis declares for every member"
						% [axis["name"], label.call(member), column])
	return out

# Every stance this column states, axis-level ones included, as [where, stance] pairs.
static func stances(column: String, list: Array[Dictionary] = []) -> Array:
	var out: Array = []
	for axis: Dictionary in _or_all(list):
		if axis.has(column + "_all"):
			out.append(["%s (every member)" % axis["name"], axis[column + "_all"]])
		var label: Callable = axis["label"]
		for member: Variant in axis["rows"]:
			var row: Dictionary = axis["rows"][member]
			if row.has(column):
				out.append(["%s: %s" % [axis["name"], label.call(member)], row[column]])
	return out

# A claim that does not hold: a covered file missing its token, a gap with no issue, a never with no
# reason.
static func false_claims(column: String, list: Array[Dictionary] = []) -> Array[String]:
	var texts := {}
	var out: Array[String] = []
	for pair: Array in stances(column, list):
		var where: String = pair[0]
		var s: Dictionary = pair[1]
		match s["stance"]:
			Stance.COVERED:
				var file: String = s["file"]
				if not texts.has(file):
					texts[file] = FileAccess.get_file_as_string(file)
				var text: String = texts[file]
				if text.is_empty():
					out.append("%s: names %s, which could not be read" % [where, file])
				elif not text.contains(s["token"]):
					out.append("%s: claims %s handles it, and %s no longer contains %s"
							% [where, file.get_file(), file.get_file(), s["token"]])
			Stance.NEVER:
				if String(s["reason"]).strip_edges().is_empty():
					out.append("%s: a never with no reason" % where)
			Stance.GAP:
				if not RegEx.create_from_string("^#\\d+$").search(String(s["issue"])):
					out.append("%s: a gap must name the issue that owes it (#N), not '%s'" % [where, s["issue"]])
				if String(s["note"]).strip_edges().is_empty():
					out.append("%s: a gap with no note" % where)
	return out

# Axes that state no stance at all for this column, whole or per row: a rotted member source or a
# rows table nothing reads would leave every check above passing over nothing.
static func axes_stating_nothing(column: String) -> Array[String]:
	var out: Array[String] = []
	for axis: Dictionary in axes():
		if (axis["members"] as Array).is_empty():
			out.append("%s enumerates no members" % axis["name"])
		var one: Array[Dictionary] = [axis]
		if not (axis["members"] as Array).is_empty() and not axis.has(column + "_all") \
				and stances(column, one).is_empty():
			out.append("%s states no %s stance" % [axis["name"], column])
	return out

# Every gap this column declares, for a reader who wants the to-do list.
static func gaps(column: String, list: Array[Dictionary] = []) -> Array[String]:
	var out: Array[String] = []
	for pair: Array in stances(column, list):
		var s: Dictionary = pair[1]
		if s["stance"] == Stance.GAP:
			out.append("%s  %s: %s" % [s["issue"], pair[0], s["note"]])
	return out
