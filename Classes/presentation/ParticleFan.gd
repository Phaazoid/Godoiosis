class_name ParticleFan
extends Object

# HOW A BURST OF PARTICLES IS SCATTERED (#887, split out of StagingDust's #656 original when the
# shock arc needed a second one). Pure, static, and the ONE spelling of it: a burst is a fan of
# points around an origin, thrown outward with a rise, derived from a key rather than rolled.
#
# WHY IT IS SHARED RATHER THAN COPIED. Two emitters that both mean "throw N particles from a point"
# are two answers to one question the moment either is tuned -- and the parts that genuinely differ
# between the slam dust and a shock's sparks are the MATERIAL and the numbers, neither of which is
# in here. Each caller keeps its own knobs and hands them in; nothing about dust or lightning is
# knowable from this file.
#
# DERIVED, NEVER randf(). A GPU particle is simulated on the card and can never be read back, so
# this function is the only part of any burst a headless case can see -- which is also what makes a
# scatter assertable rather than merely deterministic, and what makes a replay of the same orders
# draw the same sparks. HealthBlockDebris's doctrine, kept on a GPU system.

# The golden angle spreads consecutive particles evenly around the circle instead of clumping.
# HealthBlockDebris carries its own copy for a fan that takes no phase and no jitter; this is the
# jittered form's home.
const GOLDEN_ANGLE := 2.39996323


# One burst, as data. `lift` is a clearance off the surface the burst is born on -- half a particle,
# so the quad sits ON the ground rather than half inside it -- and every other parameter is the
# caller's own knob.
static func scatter(origin: Vector3, key: int, count: int, spread: float, speed: float,
		upward: float, lift: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var total := maxi(count, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = key
	# ONE rotation for the whole burst, so two bursts of the same origin are not the same fan
	# turned -- the fan itself is even by construction and only its phase and per-particle jitter
	# vary.
	var phase := rng.randf() * TAU
	for i in total:
		var angle := phase + GOLDEN_ANGLE * float(i)
		# sqrt spaces the ring evenly by AREA rather than by radius, so a fan does not pile up in
		# the middle.
		var reach := spread * sqrt((float(i) + 0.5) / float(total)) * rng.randfn(1.0, 0.18)
		var thrown := speed * rng.randfn(1.0, 0.25)
		out.append({
			"position": origin + Vector3(cos(angle) * reach, lift, sin(angle) * reach),
			# Outward, with a rise: the horizontal term carries the speed and the lift is a
			# fraction of it, so `upward` reads as "how much of this fountains" at every speed.
			"velocity": Vector3(cos(angle) * thrown, thrown * upward * rng.randfn(1.0, 0.3),
					sin(angle) * thrown),
		})
	return out
