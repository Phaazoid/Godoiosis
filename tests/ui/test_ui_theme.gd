# The project theme (#384): Resources/UiTheme.tres, wired as gui/theme/custom, exists to make
# tooltips OPAQUE -- the engine default draws the tooltip panel at half-alpha black, so a tooltip
# hovering over other controls smears into the text underneath. Worst in the dev tools, where
# every knob and tree leaf explains itself in a tooltip over a dense window (dev, 2026-08-19).
#
# The theme overrides exactly ONE style, TooltipPanel/panel; everything else falls through to the
# engine default as before. The assertion reads through a live Control's theme-fallback chain --
# the same lookup the tooltip popup itself performs -- not through the .tres file, so a theme that
# exists but is not wired into project.godot cannot pass it.
extends GdUnitTestSuite


func test_the_tooltip_panel_is_fully_opaque() -> void:
	var probe: Control = auto_free(Control.new())
	add_child(probe)
	var panel := probe.get_theme_stylebox("panel", "TooltipPanel") as StyleBoxFlat
	assert_object(panel).is_not_null()
	assert_float(panel.bg_color.a).is_equal(1.0)
