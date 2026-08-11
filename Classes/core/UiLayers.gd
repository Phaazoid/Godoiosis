extends Object
class_name UiLayers

# One declared answer to "what does this UI surface stack above?" -- the whole UI stacking order in
# one place, replacing four scattered magic numbers that only agreed with each other by luck. The
# RELATIONSHIP between them was previously recorded in prose comments ("this can open on top of
# MissionSelectScreen, so it has to out-rank that screen's MENU_Z") -- which is not a thing the
# code could check, and it had already gone wrong: PauseMenu/MissionEndBanner/CrisisPrompt set no
# z_index at all, so HoverInfoPanelControl (2) drew ON TOP of the pause menu and the Crisis prompt.
#
# THIS IS THE UI/CanvasLayer AXIS ONLY. Board sprite and overlay ordering is a DIFFERENT axis and
# does not belong here: Unit.BASE_SPRITE_INDEX, MoveAction.ARROW_BASE_Z_INDEX,
# OverlayManager.TERRAIN_Z_INDEX, and every z_index authored in Game.tscn are all Sprite2D /
# TileMapLayer in-world sorting, sharing nothing but the property name. Merging the two lists would
# be Law #4 run in reverse -- one answer covering two genuinely different questions.

const MISSION_STATUS := 1     # the always-on objectives/version corner (Scenes/MissionStatusPanel.tscn)
const HOVER_PANEL := 2        # the compact hover card (Scenes/HoverInfoPanelControl.tscn)
const INVENTORY_POPUP := 10   # the in-panel item action popup (inventory_panel.gd)
const MENU_SCREEN := 100      # a full-screen takeover -- MissionSelectScreen
const MODAL_CARD := 200       # a modal card; out-ranks everything, including a menu screen
