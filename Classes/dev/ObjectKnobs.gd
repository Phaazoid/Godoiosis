extends Object
class_name ObjectKnobs

# WHAT a terrain object's presentation fields are, and how a tuned one gets WRITTEN BACK to the
# place it is authored (#272). Static and pure -- LookKnobs' twin, one shelf along.
#
# It lives in Classes/dev/ rather than beside LookKnobs in presentation/ precisely because no
# shipping code reads it: a look is MISSION data (ScenarioData names a preset, battle3d applies it),
# and these are not. A block's height, a tuft's height and a cover bump's height are art conventions
# matched to the tile art ONCE and then constant for the whole game -- so there is nothing for a
# board to carry, and the only thing missing was a door to the authored value.
#
# That door is the difference from LookTool's Copy Values. A look knob's answer is "paste this line
# into Battle3D.tscn"; these are authored as @export DEFAULTS in BoardMirror.gd -- measured, the
# scene overrides none of them -- so the honest write is the declaration line itself. The transform
# that performs it moved to KnobSource when #373 gave the Game tab the same door; a law in
# tests/dev/test_object_knobs.gd still pins both halves of the claim that makes it legal (every prop
# is findable in its own script; the scene overrides none of them).
#
# Per PLACED instance has no store at all and is a separate feature.

# Same row shape as LookKnobs.KNOBS -- node = path relative to the host, prop = property name -- so
# reading and writing a live value route through LookKnobs.read/write rather than a second copy of
# get_indexed. Only the TABLE forks; the property access does not.
const KNOBS: Array[Dictionary] = [
	{"group": "Globals", "node": "BoardMirror", "prop": "block_height_scale", "label": "Prop block height", "min": 0.2, "max": 2.5, "step": 0.01,
		"tip": "How tall a solid prop -- crate, chest, rock, pot -- stands relative to its own sprite. 1.0 is the height measured off the art; because the art is drawn in 3/4 it includes some of the object's own lid, so the honest measurement usually reads a little tall."},
	{"group": "Globals", "node": "BoardMirror", "prop": "tuft_scale", "label": "Grass tuft scale", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How tall the plants on a grass tile stand -- the flowers and weeds that pop up off a tile which is also still painted flat. 1.0 draws each one at the size the art draws it. Only the height changes: where they sit in the cell comes off the art."},
	{"group": "Globals", "node": "BoardMirror", "prop": "cover_scale", "label": "Cover bump scale", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How tall the mud bumps a dug-in Cover tile pops up stand, relative to the icon that draws them. 1.0 is the drawn size. Only the height changes: how many bumps there are and where they sit in the cell both come off the art."},

	# FIRE (moved out of the Look tab 2026-08-16, dev: "those belong to the fire terrain effect,
	# which is another game value I'll want to tweak by look, same as the rest"). A terrain STATE
	# rather than an authored object, but the same KIND of value -- how the world's own furniture is
	# drawn, matched once and constant after. #253 had extrapolated these into presets; measured
	# before moving them, all twelve shipped presets carried byte-identical flame values, so nothing
	# authored was ever tuned per mission and leaving costs no content.
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_lift", "label": "Flame lift", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How high the fire billboard's centre sits above a burning tile. Raising it makes fire read as standing up off the ground rather than lying on it."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_size:x", "label": "Flame width", "min": 0.1, "max": 2.0, "step": 0.01,
		"tip": "Width of the fire billboard in world units, where 1.0 is exactly one cell across. Width and height share one declaration, so saving either writes both."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_size:y", "label": "Flame height", "min": 0.1, "max": 2.0, "step": 0.01,
		"tip": "Height of the fire billboard in world units. Taller than wide reads as a flame; square reads as a scorch. Width and height share one declaration, so saving either writes both."},
	# The only INT-backed knob here, and its range is load-bearing: a slider write is nudged by a
	# tenth of the range, so anything narrower than 10 rounds back to where it started.
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_count", "label": "Flame count", "min": 1.0, "max": 12.0, "step": 1.0,
		"tip": "How many separate flames a burning cell stands up. One is a sprite standing on a tile; three or more spread across the square is a tile that is on fire. Every flame is another quad and another draw, so this is the knob that costs something on a board with a lot of fire."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_spread", "label": "Flame spread", "min": 0.0, "max": 0.6, "step": 0.01,
		"tip": "How far off the cell's centre the smaller flames sit, in cells -- 0.5 reaches the tile's edge. At zero they stack in the middle and the fire reads as one clump again."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_fps", "label": "Flame fps", "min": 0.0, "max": 30.0, "step": 0.5,
		"tip": "How fast the flame's frames play. The art is eight looping frames, so this is the whole speed of the fire: low reads as a slow lick, high as a roar. Zero holds a frame without freezing the light."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_flicker", "label": "Flame flicker", "min": 0.0, "max": 0.6, "step": 0.01,
		"tip": "How hard the fire's LIGHT breathes, as a fraction of its energy -- 0.2 swings it a fifth either way. This is what makes a burning tile feel lit by something alive rather than by a lamp; zero is a steady lamp."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_camera_offset", "label": "Flame camera push", "min": 0.0, "max": 0.5, "step": 0.005,
		"tip": "How far each flame is pushed toward the camera, in cells. A flame and a unit sprite on one cell are the same camera-facing plane, so without this they speckle against each other wherever someone stands in fire; push too far and the fire visibly leaves its own tile. A clearance rather than a taste call -- it defends against a geometric coincidence."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_animated", "label": "Flame animated",
		"tip": "Off holds the fire on one frame at steady light -- a still flame, not a missing one. This is the photosensitivity switch in its first home; when the game grows a settings menu the PLAYER drives this rather than a second switch being grown beside it."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_ground_gap", "label": "Flame ground gap", "min": 0.0, "max": 0.5, "step": 0.005,
		"tip": "Gap between the base of the flame and the tile surface. A small gap stops the flame z-fighting the ground it stands on; too large and the fire floats."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_writes_depth", "label": "Flame writes depth",
		"tip": "Whether the flame writes into the depth buffer. On, it occludes what is behind it correctly but can cut a hard edge against overlapping sprites; off, it always draws as a soft overlay and never clips."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_light_energy", "label": "Flame light energy", "min": 0.0, "max": 8.0, "step": 0.05,
		"tip": "Brightness of the real point light each fire casts. This is what makes fire LIGHT the board -- units, walls and neighbouring tiles -- rather than merely glow on its own tile."},
	{"group": "Fire", "node": "BoardMirror", "prop": "flame_light_range", "label": "Flame light range", "min": 0.5, "max": 12.0, "step": 0.1,
		"tip": "How far a fire's light reaches, in world units (roughly cells). Range and energy together decide whether a burning tile lights a room or just its own corner."},
]

# --- Per-TYPE fields (#272 slice 2) -------------------------------------------------------------
#
# A terrain object may carry its own light and its own size; the KNOBS above are what it falls back
# to. TWO STORES, DECLARED: a global is an @export written into source, a per-type field is a custom
# data layer written into the tileset, and this table says which a row is. They are not two answers
# to one question -- they are the two halves of one layering the dev asked for ("a global default
# here, that the objects can override").
#
# `shapes` empty means every object; otherwise only those PropShapes get the row, so a tuft is never
# offered a block height and a crate is never offered a tuft scale. `lit_only` rows appear only once
# a tile says it emits at all -- four dead sliders under an unlit crate is noise, not information.
# `knob` names the global this falls back to, "" for the one field that has none.
#
# The LAYERS THEMSELVES ARE AUTHORED IN Resources/TestTiles.tres, never added at runtime: a schema
# migration that runs once on someone's machine is a path no test ever executes again. A law pins
# every row here to a declared layer of the declared type.
const FIELDS: Array[Dictionary] = [
	{"layer": "prop_lit", "type": TYPE_BOOL, "label": "Emits light", "shapes": [], "knob": "",
		"tip": "Whether this object lights the board at all. Pure content -- it is the question the old LIT_PROPS name list answered, moved onto the tile itself. Off means the four rows below do nothing, which is why they only appear once it is on."},
	{"layer": "prop_light_energy", "type": TYPE_FLOAT, "label": "Light energy", "shapes": [], "knob": "prop_light_energy",
		"lit_only": true, "min": 0.0, "max": 8.0, "step": 0.05,
		"tip": "How bright this object's own light burns. Inherit uses the global lamp brightness; override it for a lantern that should read hotter or dimmer than every other lamp."},
	{"layer": "prop_light_range", "type": TYPE_FLOAT, "label": "Light range", "shapes": [], "knob": "prop_light_range",
		"lit_only": true, "min": 0.5, "max": 12.0, "step": 0.1,
		"tip": "How far this object's light reaches, in world units (roughly cells). Range and energy together decide whether it lights a room or just its own corner."},
	{"layer": "prop_light_height", "type": TYPE_FLOAT, "label": "Light height", "shapes": [], "knob": "prop_light_height",
		"lit_only": true, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "How high above the cell the light sits. A wall lamp's flame is near its top; a brazier's is lower. This is where the light SOURCE is, not where the art is."},
	{"layer": "prop_light_color", "type": TYPE_COLOR, "label": "Light colour", "shapes": [], "knob": "prop_light_color",
		"lit_only": true,
		"tip": "The colour this object casts. Inherit uses the global warm lamp tone; override it for anything that should not burn like a candle -- a cold rune light, a green lantern."},
	{"layer": "prop_height_scale", "type": TYPE_FLOAT, "label": "Block height", "shapes": GridUtils.SOLID_SHAPES,
		"knob": "block_height_scale", "min": 0.2, "max": 2.5, "step": 0.01,
		"tip": "How tall THIS object stands relative to its own art, overriding the global. The global exists because the art is drawn in 3/4 and reads a little tall; a single object that still looks wrong under it belongs here."},
	{"layer": "prop_tuft_scale", "type": TYPE_FLOAT, "label": "Tuft scale", "shapes": [GridUtils.PropShape.TUFT],
		"knob": "tuft_scale", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How tall THIS tile's plants stand, overriding the global. Tall grass and a low flower are drawn at the same size in the sheet and should not stand at the same height."},
]


# Which fields a tile is offered, given its shape and whether it is lit. The filter is the table's,
# not the panel's -- a row that means nothing for a shape should be impossible to draw rather than
# merely hidden by whoever remembers to.
static func fields_for(shape: GridUtils.PropShape, lit: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for field: Dictionary in FIELDS:
		var shapes: Array = field["shapes"]
		if not shapes.is_empty() and not shapes.has(shape):
			continue
		if field.get("lit_only", false) and not lit:
			continue
		out.append(field)
	return out


# Every object tile the tileset declares: a non-FLAT prop_shape IS the definition of a terrain
# object, so the list needs no second marker. Same walk the Tile Brush palette makes.
static func object_tiles(tiles: TileSet) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if tiles == null:
		return out
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			var data := source.get_tile_data(coords, 0)
			var shape := GridUtils.prop_shape_of(data)
			if shape == GridUtils.PropShape.FLAT:
				continue
			out.append({"source_id": source_id, "coords": coords, "data": data, "shape": shape,
				"source": source})
	return out


# The tileset is a real resource on disk, so this is ResourceSaver through the one door that also
# claims the path (#99's cache trap). The VALUES are already on the TileData by the time this runs --
# editing a field writes it live so the board can show it, and saving only makes that permanent.
static func save_fields(tiles: TileSet, status: Label = null) -> bool:
	if tiles == null:
		return false
	var path := tiles.resource_path
	if path.is_empty():
		push_error("ObjectKnobs: the board's tileset has no file to save to")
		return false
	return DevWidgets.save_over(tiles, path, status)


# Writing a tuned value back into the script that declares it is KnobSource's, not this file's --
# the Game tab (#373) saves the same way, and two copies of that transform would agree only until
# one of them was taught something the other was not. What stays here is the TABLE.
static func save_to_source(host: Node3D, indices: PackedInt32Array) -> Dictionary:
	return KnobSource.save_to_source(host, KNOBS, indices)
