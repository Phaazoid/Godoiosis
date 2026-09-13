extends Object
class_name ObjectKnobs

# WHAT THE TILES PAGE AUTHORS (#272 slice 2, widened by #902) -- and it is THREE stores, which is
# why this file is a set of tables rather than one. Static and pure.
#
# The page shows ONE tile at a time and reads narrowest scope first, so what a row may move is
# visible before you move it:
#
#   FIELDS   this tile alone      -> a TileSet custom-data column   -> Save tile fields
#   (fire)   every tile of a KIND -> the ignition .tres             -> Save ground rules
#   GLOBALS  every board, forever -> the @export declaration        -> Save game-wide defaults
#
# #380 moved the middle-scope globals OUT to the Game tab and this file was purely per-type between
# then and #902, when the dev asked for them back: "I'd like the look values for objects to be on
# their individual pages, so that they are easier to find." What moved is the PAGE, not the store --
# a GLOBALS row is the same node:property row GameKnobs holds, saved the same way through the same
# KnobSource, and BoardMirror._resolved is still the only place a global and an override meet.
#
# THE COST OF THAT, STATED: one global is now reachable from every tile page that falls back to it,
# and it is one value. Grass tuft scale moved on `grass_weed`'s page moves `tall_grass` too. The
# section heading, the tooltip's GAME-WIDE line and the separate Save are what carry that; nothing
# in the storage does, because there is nothing per-tile about it to store.
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


# THE GAME-WIDE DEFAULTS the rows above fall back to (#902, out of GameKnobs.KNOBS' World group).
#
# Same node:property shape as a GameKnobs row and saved the same way, through the same KnobSource,
# into the same @export declaration -- only the page differs, so nothing here is a second answer to
# anything. They carry no `group`: a group is which SUB-TAB of the Game page a row lands on, and
# these land on none.
#
# `shapes` and `lit_only` are FIELDS' own grammar, for FIELDS' own reason -- a crate must not be
# offered a tuft density any more than it is offered a tuft scale. Six of the seven are the default
# behind a FIELDS row (a law pins that every override can see its own default on the same page);
# `tuft_density` is the odd one, a global with no per-tile twin, which is why this is its own table
# rather than a column on that one.
const GLOBALS: Array[Dictionary] = [
	{"node": "BoardMirror", "prop": "block_height_scale", "label": "Prop block height",
		"shapes": GridUtils.SOLID_SHAPES, "min": 0.2, "max": 2.5, "step": 0.01,
		"tip": "How tall a solid prop -- crate, chest, rock, pot -- stands relative to its own sprite. 1.0 is the height measured off the art; because the art is drawn in 3/4 it includes some of the object's own lid, so the honest measurement usually reads a little tall."},
	{"node": "BoardMirror", "prop": "tuft_scale", "label": "Grass tuft scale",
		"shapes": [GridUtils.PropShape.TUFT], "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How tall the plants on a grass tile stand -- the flowers and weeds that pop up off a tile which is also still painted flat. 1.0 draws each one at the size the art draws it. Only the height changes: where they sit in the cell comes off the art."},
	{"node": "BoardMirror", "prop": "tuft_density", "label": "Grass tuft density",
		"shapes": [GridUtils.PropShape.TUFT], "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How MANY of a grass tile's plants are planted, where the scale above is how tall each one stands. 1.0 plants every one the art draws; below that an even, always-the-same subset is hidden, so a tile can be drawn dense and thinned by eye. It HIDES rather than skips building -- if you settle below 1.0, the tile is better redrawn with fewer blades and this put back to 1.0."},
	# The lamp defaults (#255's light, #380's rows). Tuning one re-lights every standing lamp through
	# BoardMirror's sweep; a lamp whose tile authors its own light deliberately does not move, since
	# an authored override wins.
	{"node": "BoardMirror", "prop": "prop_light_color", "label": "Prop light colour",
		"shapes": [], "lit_only": true,
		"tip": "The colour a lit object casts by default -- the warm lamp tone. A tile that authors its own Light colour ignores this; everything else re-lights live as you drag."},
	{"node": "BoardMirror", "prop": "prop_light_energy", "label": "Prop light brightness",
		"shapes": [], "lit_only": true, "min": 0.0, "max": 8.0, "step": 0.05,
		"tip": "How bright a lit object burns by default. The per-tile Light energy field above overrides this for this one tile; this is what every other lamp in the game uses."},
	{"node": "BoardMirror", "prop": "prop_light_range", "label": "Prop light range",
		"shapes": [], "lit_only": true, "min": 0.5, "max": 12.0, "step": 0.1,
		"tip": "How far a lit object's light reaches by default, in world units (roughly cells). Range and brightness together decide whether a lamp lights a room or just its own corner."},
	{"node": "BoardMirror", "prop": "prop_light_height", "label": "Prop light height",
		"shapes": [], "lit_only": true, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "How high above the cell a lit object's light source sits by default. A wall lamp's flame is near its top; a brazier's is lower. This is where the LIGHT is, not where the art is."},
]


# Which fields a tile is offered, given its shape and whether it is lit. The filter is the table's,
# not the panel's -- a row that means nothing for a shape should be impossible to draw rather than
# merely hidden by whoever remembers to.
#
# A FLAT TILE IS OFFERED NOTHING, and that guard is #902's, not a restatement of `shapes`. Empty
# `shapes` means "every object", and every object was non-FLAT until the page widened to ground
# tiles -- so re-reading `[]` as "flat ground too" would hand `grass_basic` a Rules height, which
# Reach honours for ANY cell (Reach.gd's column_top asks prop_rule_height_at). That is flat ground
# that blocks a shot: a capability change smuggled in by a picker filter. Every one of these rows
# describes a thing STANDING on a cell, and a flat tile has nothing standing on it.
static func fields_for(shape: GridUtils.PropShape, lit: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if shape == GridUtils.PropShape.FLAT:
		return out
	for field: Dictionary in FIELDS:
		if _offered(field, shape, lit):
			out.append(field)
	return out


# The same filter over the globals, and deliberately the same one function: which rows a tile is
# offered is one question whichever table is being asked, and two copies of it would drift the first
# time a shape was added to either side.
static func globals_for(shape: GridUtils.PropShape, lit: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if shape == GridUtils.PropShape.FLAT:
		return out
	for knob: Dictionary in GLOBALS:
		if _offered(knob, shape, lit):
			out.append(knob)
	return out


static func _offered(row: Dictionary, shape: GridUtils.PropShape, lit: bool) -> bool:
	var shapes: Array = row["shapes"]
	if not shapes.is_empty() and not shapes.has(shape):
		return false
	return lit or not row.get("lit_only", false)


# Every object tile the tileset declares: a non-FLAT prop_shape IS the definition of a terrain
# object, so the list needs no second marker. Same walk the Tile Brush palette makes.
#
# STILL THE NARROW LIST after #902 widened the PAGE, and deliberately: this answers "which tiles
# stand something up", which BoardMirror's light coverage and the prop_lit content law both ask.
# Widening it in place would have left test_board_mirror picking a FLAT tile as its unlit example,
# prop_at returning null, and its "an unlit object casts light" assertion passing VACUOUSLY -- a
# test going blind, which is worse than one going red. Two questions, two functions.
static func object_tiles(tiles: TileSet) -> Array[Dictionary]:
	return _tiles_where(tiles, func(data: TileData, shape: GridUtils.PropShape) -> bool:
		return shape != GridUtils.PropShape.FLAT)


# Every tile the Tiles page offers a page for (#902): a prop, OR anything the sheet has bothered to
# NAME. Named is what makes flat ground reachable -- `grass_basic` and `grass_clover` are FLAT, so
# half the grass in the game had no page at all while its ground's burn rules needed one.
#
# The union rather than "named" alone, though every prop happens to be named today: `_object_label`
# still falls back to shape-and-coords for an unnamed one, so a prop must not become unpickable for
# being unnamed. 25 props, 36 named tiles, 36 pages.
static func authorable_tiles(tiles: TileSet) -> Array[Dictionary]:
	return _tiles_where(tiles, func(data: TileData, shape: GridUtils.PropShape) -> bool:
		return shape != GridUtils.PropShape.FLAT \
			or GridUtils.authored_tile_display_name(data) != "")


# The one walk, in atlas order -- which is also roughly material order, since the sheet is laid out
# that way, and is the order the tile brush's palette shows.
static func _tiles_where(tiles: TileSet, include: Callable) -> Array[Dictionary]:
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
			if not include.call(data, shape):
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


# The seven globals' Save, into the @export declarations that author them. Three lines over
# KnobSource because that file was built to take a table -- its own header says so: "the next table
# that wants a Save gets this one rather than a copy that agrees right up until one of them is
# taught something the other is not." This is that table.
static func save_globals_to_source(host: Node3D, indices: PackedInt32Array) -> Dictionary:
	return KnobSource.apply_edits(KnobSource.declaration_edits(host, GLOBALS, indices))


# --- The ground's burn rules (#902) -------------------------------------------------------------
#
# The dev's ask while ruling on tall grass (#891, 2026-09-10): "let's put a knob for this somewhere
# in the dev tools, a tick if something is burnable, and if it is, a dial for how many turns."
#
# A PROJECTION of the reaction catalog, never a second store. Flammability has exactly one answer --
# TerrainReactionCatalog.fuel_for_kind, asked of the authored .tres -- and a `burnable` column beside
# it would be worse than the usual duplicate seam: a reaction is per-KIND and a custom-data column is
# per-TILE, so the sheet's four grass tiles could disagree about whether grass burns, which
# fuel_for_kind takes a Kind and has no way to represent. So the row is REACHED from a tile and
# SCOPED to its kind, and the page says which.

const REACTION_SCRIPT := "res://Classes/terrain/TerrainReaction.gd"

# THE DIAL'S FLOOR IS ONE (dev, 2026-09-12: "let's keep floor at 1"). An absent clock is legal and
# means "burns forever" -- but tests/terrain/test_fire_clock.gd refuses a SHIPPED fuel that authors
# none, because a grass field that never goes out would ship silently. Burning forever is already
# spelled, and better: ground that is not fuel never runs out, which is what Prolog's braziers on
# flagstone have always been. So the TICK is how you say forever, and the dial cannot author a file
# CI will red.
const MIN_BURN_TURNS := 1
const MAX_BURN_TURNS := 12
# What a newly ticked ground starts at -- the number every shipped ignition happens to carry. A SEED
# for a new file, not a rule: the dial is right beside it.
const DEFAULT_BURN_TURNS := 3


# Whether this ground can be asked the question at all. NONE means the tile declares no terrain_type
# (`crate` is one) and VOID is a hole -- neither is ground a fire could take.
static func ground_rules_apply_to(kind: Terrain.Kind) -> bool:
	return kind != Terrain.Kind.NONE and kind != Terrain.Kind.VOID


# WHICH FILE the tick acts on: the one the catalog actually FOUND, never a name composed from the
# kind. TREE's ignition reaction is `Burning.tres` -- named before it had a kind to be named after --
# so a composed `TreeIgnites.tres` would miss it, and ticking TREE off would report success while
# every fence on the board went on burning. A composed name is only ever for a file that does not
# exist yet.
static func ignition_path_for(kind: Terrain.Kind, reactions: Array[TerrainReaction]) -> String:
	var found := TerrainReactionCatalog.fuel_for_kind(kind, reactions)
	if found != null and not found.resource_path.is_empty():
		return found.resource_path
	return "%s%sIgnites.tres" % [TerrainReactionCatalog.REACTION_DIR,
		String(Terrain.Kind.keys()[kind]).to_lower().to_pascal_case()]


# A new ignition reaction, built to the shape fuel_for_kind will FIND -- the pairing a law pins,
# because a constructor that drifts from that predicate makes a file the tick creates and then
# cannot see.
#
# Three things here are not decoration. `required_kind` must be SET: NONE means "don't care" on that
# gate, so a bare reaction would make every ground on the board catch. `forbidden_tile_state` is
# #890's terminator -- without SCORCHED refusing it, fire re-crosses what it has already burnt and
# the field never settles. And the custom-type metadata is written HERE rather than left to Godot:
# all six shipped reactions carry it, so a file saved without it is one the editor rewrites on its
# next save, dirtying the tree for an edit nobody made (#111's shape).
#
# CONSTRUCTED, not duplicated from a sibling. A duplicate needs a sibling to exist, and the case
# where none does -- every ignition file ticked off -- is exactly when one has to be made.
static func make_ignition(kind: Terrain.Kind) -> TerrainReaction:
	var reaction := TerrainReaction.new()
	reaction.incoming_element = Elemental.Element.FIRE
	reaction.required_kind = kind
	reaction.forbidden_tile_state = Terrain.TileState.SCORCHED
	var added: Array[Terrain.TileState] = [Terrain.TileState.BURNING]
	reaction.add_tile_states = added
	var turns: Dictionary[Terrain.TileState, int] = {}
	turns[Terrain.TileState.BURNING] = DEFAULT_BURN_TURNS
	reaction.add_state_turns = turns
	reaction.popup = "Ignites!"
	var script_uid := ResourceLoader.get_resource_uid(REACTION_SCRIPT)
	if script_uid != ResourceUID.INVALID_ID:
		reaction.set_meta("_custom_type_script", ResourceUID.id_to_text(script_uid))
	return reaction


# How long fire lasts on this ground. Absent reads as 0, which the panel shows as the floor rather
# than as a value -- an absent clock is unreachable from the dial by construction.
static func burn_turns_of(reaction: TerrainReaction) -> int:
	if reaction == null:
		return 0
	return reaction.add_state_turns.get(Terrain.TileState.BURNING, 0)

