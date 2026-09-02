extends SubViewportContainer
class_name GameSurface

# The 2D game's UI SURFACE: what design space its Controls lay out in, given the window (#659).
#
# The whole battle UI -- every panel, menu, modal and screen -- lives on Controls under
# GameView/Game/UILayer. Stretch is ON, so GameView's SIZE has always tracked the window, which
# means those Controls were laid out in PHYSICAL pixels: anchors moved with the window, authored
# sizes did not. The inspect panel is 300px wide, which is 23% of a 720p screen and 8% of a 4K one.
#
# The fix is Godot's own 2D content scale, applied one level DOWN from where it usually lives.
# `size_2d_override` + `size_2d_override_stretch` is the exact machinery a Window's
# `content_scale_mode = canvas_items` runs on; the root window is the wrong place to set it here,
# because the root's base size would clamp OUR container to 1280x720 and the whole game would
# become a 720p texture blown up to the window. Set on GameView instead, `size` stays the physical
# window (so 2D still RENDERS at full resolution) and only the layout space is scaled -- a canvas
# transform, not an upscaled blit. Fonts follow it: Viewport.oversampling reads the same transform,
# so glyphs re-rasterize at the effective scale rather than being magnified.
#
# It rides on the CONTAINER rather than on Battle3D because both hosts must get it. Battle3D's
# three views all work by setting this node's anchors or size, and a bare Main.tscn launch sets
# neither -- `resized` covers all four without battle3d.gd knowing this exists. CORNER falls out
# for free: it pins the container to the native size, so the factor is exactly 1 there.
#
# The scale can never go BELOW 1: custom_minimum_size floors this container at the native
# resolution even in a smaller window (Control clamps to its minimum), so a small window clips
# exactly as it always has rather than shrinking the UI into nothing.


# The design resolution is NOT declared here. `custom_minimum_size` already IS that fact -- see
# battle3d.gd's _pip_native, which calls it "the one source" and reads the same property for the
# PiP's native size. A second reader, not a second answer.
@onready var _view: SubViewport = $GameView


func _ready() -> void:
	resized.connect(_apply_scale)
	_apply_scale()


# EXPAND, not fit: the smaller ratio wins, so a window wider than 16:9 gets extra design-space
# WIDTH (the board breathes; panels stay put against their anchors) instead of a squeeze, and a
# taller-than-16:9 window is bounded by its width instead of crowding the panels off the sides.
#
# READS `size`, NEVER `_view.size` -- MEASURED, and the difference is a permanent one-resize lag.
# SubViewportContainer updates its viewport's size AFTER emitting `resized`, so at the moment this
# runs `_view.size` is still the PREVIOUS window. Deriving from our own size is not merely fresher,
# it is order-INDEPENDENT: it cannot care when the container gets round to its child.
func _apply_scale() -> void:
	if _view == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var native: Vector2 = custom_minimum_size
	if native.x <= 0.0 or native.y <= 0.0:
		return
	var factor: float = minf(size.x / native.x, size.y / native.y)
	if factor <= 0.0:
		return
	var design := Vector2i(roundi(size.x / factor), roundi(size.y / factor))
	# Guarded because assigning the override re-emits size_changed; an identical assignment is a
	# no-op inside Godot, so the equality check is what keeps that from being a live wire.
	if _view.size_2d_override != design:
		_view.size_2d_override = design
	_view.size_2d_override_stretch = true
