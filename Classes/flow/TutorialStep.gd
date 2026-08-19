class_name TutorialStep
extends Resource

# One step of a scenario's tutorial lesson (#182): instruction text shown on the mission-status
# HUD until `done_when` fires, then the next step activates. Steps are SEQUENTIAL -- a lesson is
# a straight line, and only the active step listens. Authored on ScenarioData.tutorial_steps;
# ScenarioDirector runs them. Shares DialogBeat.Trigger, the one trigger vocabulary.
#
# MISSION_START is not a meaningful done_when (the lesson starts armed); use board triggers.

@export var text := ""
@export var done_when := DialogBeat.Trigger.SQUAD_FORMED
@export var unit_name := ""   # UNIT_SELECTED: which unit (UnitData.display_name); SQUAD_FORMED:
                              # required leader. Empty = any unit / any leader.
@export var squad_size := 0   # SQUAD_MEMBER_ADDED: done when the squad reaches this many members
                              # (leader included). 0 = any join completes the step.
@export var turn := 1         # TURN_START: which player turn (1-based)
