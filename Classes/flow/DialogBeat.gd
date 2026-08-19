class_name DialogBeat
extends Resource

# One authored dialog moment in a scenario (#182): WHEN it fires (trigger) and WHAT plays (a
# Dialogic timeline). Authored on ScenarioData.dialog_beats -- board content, not code, the
# ai_factions precedent (#150). Fired-state lives in ScenarioDirector, never here: beats are
# shared resources and must stay replayable across restarts.

# The ONE trigger vocabulary, shared with TutorialStep's done_when (a lesson step and a dialog
# beat answer to the same board events; two enums would be the duplicate seam).
enum Trigger {
	MISSION_START,        # a fresh mission begins -- never a resume (see ScenarioDirector.disarm)
	TURN_START,           # the player's Nth turn begins; N is `turn` below
	SQUAD_FORMED,         # the player forms any squad
	UNIT_SELECTED,        # the player selects a unit (game.unit_selected)
	SQUAD_MEMBER_ADDED,   # a unit joins a player squad (SquadManager.squad_member_joined)
	STEP_COMPLETED,       # the lesson advanced past step N (`step` below) -- beats only, the
	                      # payoff voice for tutorial progress (a board event fires at its FIRST
	                      # occurrence; "the squad is COMPLETE" is a lesson fact, not a board one)
}

@export var trigger := Trigger.MISSION_START
@export var turn := 1   # TURN_START only: which player turn fires this (1-based)
@export var step := 1   # STEP_COMPLETED only: which lesson step (1-based)
@export var timeline: DialogicTimeline
