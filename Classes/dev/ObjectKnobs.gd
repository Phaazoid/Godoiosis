extends Object
class_name ObjectKnobs

# WHAT a terrain object TYPE'S own fields are (#272 slice 2) -- the TileSet custom-data columns a
# tile may author to override the game-wide defaults. Static and pure.
#
# Purely per-TYPE since #380: the globals this table's rows fall back to (prop geometry, the fire
# block, the lamp defaults) are GameKnobs rows now, saved by the Game tab into the @export defaults
# that declare them. TWO STORES, DECLARED: a global is an @export written into source, a per-type
# field is a custom-data layer written into the tileset. They are not two answers to one question --
# they are the two halves of one layering the dev asked for ("a global default here, that the
# objects can override"), and BoardMirror._resolved is the only place the two meet.
#
# Per PLACED instance has no store at all and is a separate feature.
#
# NOT EVERY ROW FALLS BACK TO A GLOBAL. `prop_lit` never did (off is the right answer for most
# tiles), and `prop_rule_height` (#660) falls back to a per-SHAPE default instead -- a solid prop
# stands one block, a billboard stands nothing. Both carry `knob` = "", and a row like that is
# resolved by whoever OWNS its fallback (GridUtils for the shape default) rather than by BoardMirror.
#
# `prop_rule_height` is also the first RULES column in this table rather than a presentation one:
# how tall a prop stands for the sight trace is legality, not looks. It sits deliberately next to
# `prop_height_scale` -- the look correction #642 ruled can never source legality -- so the panel
# STATES that split instead of leaving it to be rediscovered.
#
# `shapes` empty means every object; otherwise only those PropShapes get the row, so a tuft is never
# offered a block height and a crate is never offered a tuft scale. `lit_only` rows appear only once
# a tile says it emits at all -- four dead sliders under an unlit crate is noise, not information.
# `knob` names the global this falls back to, "" for the two fields that have none (above).
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
	{"layer": "prop_rule_height", "type": TYPE_INT, "label": "Rules height", "shapes": [], "knob": "",
		"min": 1.0, "max": GridUtils.MAX_DRAWABLE_RULE_HEIGHT, "step": 1.0,
		"tip": "How tall this object stands FOR THE RULES, in height units (two per level) -- the column a shot has to clear (#660). Block height above is its opposite number: that one is a 3/4-perspective LOOK correction and never touches legality (#642), this one decides what a gun can shoot over. Inherit gives every solid prop one block and a billboard nothing; drop a fence to 1 and a lob clears it while a gun still dies on it. The art only draws about two levels (#642), so the slider stops at that ceiling and a law refuses a hand-edited tileset that goes past it -- a wall a shot dies on but the player can see over is worse than no wall."},
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

