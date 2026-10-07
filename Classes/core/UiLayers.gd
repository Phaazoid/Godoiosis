extends Object
class_name UiLayers

# One declared answer to "what does this UI surface stack above?" -- the whole UI stacking order in
# one place, replacing four scattered magic numbers that only agreed with each other by luck. The
# RELATIONSHIP between them was previously recorded in prose comments ("this can open on top of
# MissionSelectScreen, so it has to out-rank that screen's MENU_Z") -- which is not a thing the
# code could check, and it had already gone wrong: PauseMenu/MissionEndBanner/CrisisPrompt set no
# z_index at all, so HoverInfoPanelControl (2) drew ON TOP of the pause menu and the Crisis prompt.
#
# TWO AXES, NAMED APART (#1034). A CanvasLayer's `layer` orders whole layers; a z_index orders
# siblings INSIDE one layer and never crosses into another -- for the eye or for the mouse (GUI
# picking sorts by layer first). This table once held both as one list, so the pause menu's 200
# lost to the radial's 20 and the dialogue's 1: the smaller numbers were CanvasLayers. So the layer
# values carry a LAYER_ prefix and every z value sits under the layer it orders within;
# tests/law/test_ui_layers_one_axis_each.gd refuses a write that reads the wrong group. Inside one
# layer the mouse follows TREE order, not z (probed on 4.7.1): a later sibling is picked first even
# where an earlier one draws above it, which is why a card is always the last thing added.
#
# THIS IS THE UI AXIS ONLY. Board sprite and overlay ordering is a DIFFERENT axis and does not
# belong here: Unit.BASE_SPRITE_INDEX, MoveAction.ARROW_BASE_Z_INDEX,
# OverlayManager.TERRAIN_Z_INDEX, and every z_index authored in Game.tscn are all Sprite2D /
# TileMapLayer in-world sorting, sharing nothing but the property name. Merging the two lists would
# be Law #4 run in reverse -- one answer covering two genuinely different questions.

# --- CanvasLayer.layer: the order BETWEEN layers ---------------------------------------------------
# The order is forced, not chosen: the Prolog's UNIT_SELECTED line plays while the wheel is open, so
# the wheel must sit over the dialogue or the dialogue's full-rect catcher eats its first click.
const LAYER_HUD := 0            # UILayer (Game.tscn): the always-on panels; TurnBanner shares it
const LAYER_DIALOGUE := 1       # Dialogic's layout, set by ScenarioDirector._start
const LAYER_ACTION_MENU := 20   # the unit's radial action menu -- over the HUD and the dialogue
const LAYER_CARDS := 100        # game.card_layer: every ModalCard, over everything above

# --- z_index inside LAYER_HUD --------------------------------------------------------------------
const MISSION_STATUS := 1     # the always-on objectives/version corner (Scenes/MissionStatusPanel.tscn)
const HOVER_PANEL := 2        # the info card (Scenes/HoverInfoPanelControl.tscn), opened by a click since #1105
const INVENTORY_POPUP := 10   # the in-panel item action popup (inventory_panel.gd)
# The skip's fade to black (#545): over every HUD panel, and on THIS layer so the dialogue, the wheel
# and every card stay above it -- a pause menu opened mid-skip must not open under the black.
const PLAYBACK_FADE := 50

# --- z_index inside LAYER_CARDS ------------------------------------------------------------------
const MENU_SCREEN := 100      # a full-screen takeover -- MissionSelectScreen, PreMissionScreen
const MODAL_CARD := 200       # a modal card; out-ranks a menu screen it can open over
# A drag preview is the one thing that must out-rank whatever surface it was picked up FROM, and it
# needs stating here because Godot makes the preview TOP-LEVEL: that breaks the relative-z chain, so
# it inherits nothing from the surface it came from and draws at 0 unless told otherwise -- under an
# opaque menu, i.e. invisible, which is exactly what shipped (#798). It is parented to the source
# card's root control, so it rides that card's layer.
const DRAG_PREVIEW := 300
