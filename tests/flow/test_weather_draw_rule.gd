# The weather draw's RULE (#1509), pure: WeatherDraw on sets this suite authors itself, so nothing here
# reads a shipped board (the content razor). The wires -- the game's fresh-start doors, the restore
# doors, the Play API's store -- are test_weather_draw.gd's.
extends GdUnitTestSuite

const K := Weather.Kind
const SEEDS := 200


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


static func _odds(pairs: Array) -> Dictionary[Weather.Kind, int]:
	var odds: Dictionary[Weather.Kind, int] = {}
	for pair: Array in pairs:
		odds[pair[0]] = pair[1]
	return odds


# A locked board: nothing is offered, so the mission starts under the weather the board stands under,
# and the roll is never touched -- every board saved before #1509 takes this path.
func test_an_empty_set_draws_nothing() -> void:
	var none := _odds([])
	for standing: Weather.Kind in [K.CLEAR, K.RAIN, K.ASHFALL]:
		var rng := _rng(7)
		var state := rng.state
		assert_int(WeatherDraw.draw(none, standing, rng)).is_equal(standing)
		assert_int(WeatherDraw.at_start(none, standing, rng, K.SNOW)).override_failure_message(
				"a restart on a locked board kept a weather the board does not stand under").is_equal(standing)
		assert_int(rng.state).override_failure_message("a locked board spent the roll").is_equal(state)
	assert_bool(WeatherDraw.draws(none)).is_false()


# Every draw lands on an offered weather, each offered weather is reachable, and a zero weight offers
# nothing. No frequency is asserted: the weights only have to order the pick, not hit a number.
func test_a_draw_lands_only_on_offered_weathers_and_reaches_each() -> void:
	var odds := _odds([[K.RAIN, 1], [K.SNOW, 3], [K.FOG, 0]])
	var seen := {}
	for s in range(SEEDS):
		var drawn := WeatherDraw.draw(odds, K.CLEAR, _rng(s))
		assert_bool(drawn == K.RAIN or drawn == K.SNOW).override_failure_message(
				"seed %d drew %s, which the set does not offer" % [s, Weather.name_of(drawn)]).is_true()
		seen[drawn] = true
	assert_bool(seen.has(K.RAIN) and seen.has(K.SNOW)).override_failure_message(
			"%d seeds never reached every offered weather: %s" % [SEEDS, str(seen.keys())]).is_true()
	assert_array(WeatherDraw.offered(odds)).is_equal([K.RAIN, K.SNOW])


# A seed means one weather however the set was written down: a resave may reorder a Dictionary.
func test_a_seed_means_one_weather_whatever_order_the_set_was_written() -> void:
	var forward := _odds([[K.MIST, 2], [K.RAIN, 1], [K.THUNDERSTORM, 1]])
	var backward := _odds([[K.THUNDERSTORM, 1], [K.RAIN, 1], [K.MIST, 2]])
	for s in range(SEEDS):
		assert_int(WeatherDraw.draw(forward, K.CLEAR, _rng(s))).is_equal(
				WeatherDraw.draw(backward, K.CLEAR, _rng(s)))


# Ruling 2: a restart keeps the weather it is leaving -- unless the board, edited between, no longer
# offers it, and then it draws again. A fresh start keeps nothing.
func test_a_restart_keeps_an_offered_weather_and_redraws_one_no_longer_offered() -> void:
	var odds := _odds([[K.RAIN, 1], [K.SNOW, 1]])
	for s in range(SEEDS):
		assert_int(WeatherDraw.at_start(odds, K.CLEAR, _rng(s), K.SNOW)).is_equal(K.SNOW)
		var redrawn := WeatherDraw.at_start(odds, K.CLEAR, _rng(s), K.FOG)
		assert_int(redrawn).override_failure_message(
				"a kept weather the board no longer offers was kept anyway").is_equal(
				WeatherDraw.draw(odds, K.CLEAR, _rng(s)))
		assert_int(WeatherDraw.at_start(odds, K.CLEAR, _rng(s))).is_equal(WeatherDraw.draw(odds, K.CLEAR, _rng(s)))


# The Play API's pick: a drawing board takes what it offers, a locked board only its own weather.
func test_a_pick_is_refused_unless_the_board_could_have_drawn_it() -> void:
	var odds := _odds([[K.RAIN, 1], [K.SNOW, 1]])
	assert_str(WeatherDraw.pick_block_reason(odds, K.CLEAR, K.RAIN)).is_empty()
	assert_str(WeatherDraw.pick_block_reason(odds, K.CLEAR, K.CLEAR)).is_not_empty()
	var none := _odds([])
	assert_str(WeatherDraw.pick_block_reason(none, K.ASHFALL, K.ASHFALL)).is_empty()
	assert_str(WeatherDraw.pick_block_reason(none, K.ASHFALL, K.RAIN)).is_not_empty()


# One wording for the set, shared by the screen, the dev page and the Play API; names by kind for the
# telemetry record, which a later build reads.
func test_the_set_reads_in_enum_order_with_its_odds() -> void:
	var odds := _odds([[K.RAIN, 1], [K.CLEAR, 3], [K.FOG, 0]])
	assert_str(WeatherDraw.odds_text(odds)).is_equal("Clear 75%, Rain 25%")
	assert_dict(WeatherDraw.odds_by_name(odds)).is_equal({"CLEAR": 3, "RAIN": 1})
