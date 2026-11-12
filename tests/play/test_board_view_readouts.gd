# What the night-maps driver could not read off the text view (#1662): a unit's job and abilities, which
# tile a shared ground glyph is, and how far a watch's lane reaches. Every expectation is read from the
# seam the game's own readout uses (the inspect dock, the tile card, Watch.paths), never typed in.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const BoardView := preload("res://play/board_view.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


func _board(root_name: String) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 10, 8))
	return b


# Any job in the catalogue that grants an ability: the content is whatever it is today.
func _a_job_with_an_ability() -> String:
	for id: String in JobCatalog.get_jobs():
		var job := JobCatalog.get_job(id)
		if job != null and not job.ability_pool.is_empty():
			return id
	return ""


func test_an_enemys_job_and_abilities_are_on_its_line_and_its_focus() -> void:
	var b := _board("JobLineRoot")
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(4, 0))
	var plain: Unit = BoardBuilder.spawn(b, _data("Plain", PLAYER), Vector2i(0, 0))
	var sess = PlaySession.new(b)
	var plain_before: String = BoardView._unit_line(sess, plain)
	var job_id := _a_job_with_an_ability()
	if job_id == "":
		fail("precondition: no job in the catalogue grants an ability, so there is nothing to name")
		return
	foe.unit_instance.jobs.append(job_id)

	var line: String = BoardView._unit_line(sess, foe)
	assert_str(line).override_failure_message("the line does not name the job: " + line) \
			.contains("job " + UnitInfoPanelControl.jobs_text(foe))
	var focus: String = BoardView.render_focus(sess, sess.handle_for(foe))
	for ability in foe.get_live_abilities():
		assert_str(line).override_failure_message("the line does not name %s: %s" % [ability.display_name, line]) \
				.contains(ability.display_name)
		assert_str(focus).override_failure_message("focus does not describe " + ability.display_name) \
				.contains("ability %s: %s" % [ability.display_name, ability.description])
	assert_str(BoardView._unit_line(sess, plain)).override_failure_message(
			"a jobless unit's line changed").is_equal(plain_before)
	assert_str(plain_before).not_contains("job ")


# Two tiles of one kind under one glyph, read off the fixture tileset: whatever pair it holds today.
func _two_tiles_sharing_a_kind(grid: TileMapLayer) -> Array[Vector2i]:
	var source := grid.tile_set.get_source(BoardBuilder.GRASS_SOURCE) as TileSetAtlasSource
	var first_of_kind := {}
	for i in source.get_tiles_count():
		var atlas := source.get_tile_id(i)
		var data := source.get_tile_data(atlas, 0)
		var kind: Terrain.Kind = data.get_custom_data("terrain_type")
		if kind == Terrain.Kind.NONE or kind == Terrain.Kind.WATER or kind == Terrain.Kind.VOID:
			continue
		if not data.get_custom_data("walkable"):
			continue
		var title := GridUtils.authored_tile_display_name(data)
		if first_of_kind.has(kind):
			var other: Vector2i = first_of_kind[kind]
			if GridUtils.authored_tile_display_name(source.get_tile_data(other, 0)) != title:
				return [other, atlas] as Array[Vector2i]
		else:
			first_of_kind[kind] = atlas
	return []


func test_one_glyph_over_two_tiles_names_both_and_terrain_says_what_each_is_made_of() -> void:
	var b := _board("MixedGroundRoot")
	var pair := _two_tiles_sharing_a_kind(b.grid)
	if pair.is_empty():
		fail("precondition: the fixture tileset has no two named tiles of one kind")
		return
	for x in range(-2, 8):
		for y in range(-2, 6):
			BoardBuilder.paint_cell(b.grid, Vector2i(x, y), pair[0] if x < 3 else pair[1])
	BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var sess = PlaySession.new(b)
	var board: BoardContext = sess._board()
	var left := Vector2i(0, 1)
	var right := Vector2i(5, 1)

	var overview: String = BoardView.render_overview(sess)
	var terrain: String = BoardView.render_terrain(sess)
	for cell: Vector2i in [left, right]:
		var title: String = TileReadout.title_of(sess, cell)
		assert_str(overview).override_failure_message("the legend does not name %s:\n%s" % [title, overview]) \
				.contains(title)
		var names: Array[String] = []
		for substance: String in board.made_of_at(cell):
			names.append(SubstanceCatalog.name_of(substance))
		var expect := "%s (%s)" % [title, ", ".join(names) if not names.is_empty() else "nothing"]
		assert_str(terrain).override_failure_message("terrain does not say '%s':\n%s" % [expect, terrain]) \
				.contains(expect)


func test_a_one_tile_board_prints_no_made_of_block() -> void:
	var b := _board("PlainGroundRoot")
	BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var sess = PlaySession.new(b)
	assert_str(BoardView.render_terrain(sess)).not_contains("Made of")
	assert_str(BoardView.render_overview(sess)).not_contains("see `terrain`)")


func _watch_weapon() -> WeaponInstance:
	var swing := WeaponAttackData.new()
	swing.display_name = "Swing"
	swing.power = 4
	P.point(swing, 1, 1)
	var watch := WeaponAttackData.new()
	watch.display_name = "Lane"
	watch.power = 4
	watch.can_overwatch = true
	P.line(watch, 3)
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = swing
	t.extra_attacks.assign([watch])
	return WeaponInstance.make(t)


func test_a_watch_names_where_its_lane_reaches() -> void:
	var b := _board("LaneRoot")
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(6, 4))
	hero.add_item(_watch_weapon())
	var sess = PlaySession.new(b)
	var r: Dictionary = sess.overwatch(sess.handle_for(hero), Vector2i(1, 0), "Lane")
	if not r.ok:
		fail("precondition: the watch was refused: %s" % str(r))
		return
	sess.execute()
	if hero.watch == null or not hero.watch.is_armed():
		fail("precondition: the watch never armed")
		return

	var paths: Array[Array] = hero.watch.paths()
	var count := 0
	for path: Array in paths:
		count += path.size()
	var first: Vector2i = paths[0][0]
	var last: Vector2i = paths[0][paths[0].size() - 1]
	var line: String = BoardView._unit_line(sess, hero)
	assert_str(line).override_failure_message("the lane's ends are not on the line: " + line) \
			.contains("(%d,%d)-(%d,%d)" % [first.x, first.y, last.x, last.y])
	assert_str(line).contains("%d cells" % count)
