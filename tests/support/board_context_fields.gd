# How a resolve pass's seal treats each of BoardContext's script variables (#1529): the table
# tests/law/test_every_board_store_says_how_the_seal_treats_it.gd checks, refusing a variable it does not
# name. A new store on the board is classified once, here, before a pass can read it live unnoticed.
extends RefCounted

# SEALED: a store whose cell reads count on PlannedTiles.seal_breaks inside a pass (PlannedTiles.open_seal),
# because a pass changes it and reads its own changes through PlannedTiles. Each read is listed with the
# arguments the law calls it with.
const SEALED := {
	"terrain_states": {
		"states_at": [Vector2i.ZERO],
		"has_state": [Vector2i.ZERO, Terrain.TileState.FROZEN],
	},
	"gas": {
		"packed_at": [Vector2i.ZERO],
		"level_at": [Vector2i.ZERO, Gas.Kind.STEAM],
	},
}

# UNSEALED, each with the reason no tile seal guards it.
const UNSEALED := {
	"grid": "the ground's kind; a pass changes none, and every write announces itself (BoardGrid, test_board_writes_announce)",
	"heights": "the ground's shape; a pass changes none, and every write announces itself",
	"zones": "painted mission zones; a pass changes none",
	"units": "bodies, sealed on the body side (Unit.state, Unit.open_seal)",
	"squad_manager": "the queue and its projection; bodies through it are sealed on the body side",
	"weather": "a value the builder hands the board for its length; a pass changes none",
	"atmosphere": "a value the builder composes from the weather; a pass changes none",
	"tiles": "the pass's own planned tiles: the door the seal points reads through",
	"mission": "a value the builder hands the board; a pass changes none",
}
