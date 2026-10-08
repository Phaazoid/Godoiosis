extends RefCounted
class_name CameraRecording

# THE DEV'S CAMERA, AS A SPEC (#705 slice 2). Key poses dropped while a pass is paused (N), each
# beside the director's own frame at that same moment, so the bug report can say exactly what the
# camera did and what the dev wants instead -- in numbers that replay, and a picture of each.
#
# Plain data plus its renderers: battle3d fills it (it owns the rig, the shot table and the pass
# clock), BugReporter prints it. Never saved as a resource -- a recording lives for the board it
# was made on and leaves inside a report, which is why it is not a CameraPose (no pitch, and a
# saved type would drag the embedded-content sweep in for a value nobody keeps).

const MAX_KEYFRAMES := 12
# The contact sheet's tile: one screenshot per keyframe, K1 first, three across.
const THUMB_SIZE := Vector2i(480, 270)
const SHEET_COLUMNS := 3
const SHEET_GAP := 8
const SHEET_BACKGROUND := Color(0.08, 0.08, 0.1, 1.0)


class Keyframe:
	var index := 0
	var pass_time := 0.0          # scaled seconds since the pass began -- frozen while paused
	var shot := ""                # ShotDirector.Shot name
	var trained := ""             # who the shot is trained on, or ""
	var line: Array[String] = []  # the beat's aim line, attacker then target
	var yours: Dictionary = {}    # CameraRig3D.snapshot_view() when N was pressed
	var director: Dictionary = {} # the director's frame the pause is holding
	var image: Image = null       # what the dev framed, or null headless


var keyframes: Array[Keyframe] = []


func is_empty() -> bool:
	return keyframes.is_empty()


func is_full() -> bool:
	return keyframes.size() >= MAX_KEYFRAMES


# Null when full. The caller attaches the screenshot once it has one -- it costs a frame.
func add(pass_time: float, shot: String, trained: String, line: Array[String], yours: Dictionary,
		director: Dictionary) -> Keyframe:
	if is_full():
		return null
	var key := Keyframe.new()
	key.index = keyframes.size() + 1
	key.pass_time = pass_time
	key.shot = shot
	key.trained = trained
	key.line = line.duplicate()
	key.yours = yours.duplicate()
	key.director = director.duplicate()
	keyframes.append(key)
	return key


func clear() -> void:
	keyframes.clear()


# --- the report -----------------------------------------------------------------------------------

# The `## Camera recording` section body, or "" with nothing recorded. A table to read, then the
# same numbers as JSON to replay.
func render() -> String:
	if keyframes.is_empty():
		return ""
	var out := "The dev paused the pass (P), moved the camera, and dropped a key pose (N) for each "
	out += "row: **yours** is the framing wanted, **director** is what the automatic camera had at "
	out += "that moment. `camera.png` holds a screenshot of each, K1 first, three across.\n\n"
	out += "| K | pass t | shot | line | yours: yaw / pitch / dist / aim | director: yaw / pitch / dist / aim |\n"
	out += "|---|---|---|---|---|---|\n"
	for key in keyframes:
		out += "| K%d | %.2fs | %s | %s | %s | %s |\n" % [key.index, key.pass_time,
				key.shot + ("" if key.trained == "" else " (%s)" % key.trained),
				_line_text(key.line), _pose_text(key.yours), _pose_text(key.director)]
	out += "\n```json\n%s\n```\n" % to_json()
	return out


func to_json() -> String:
	var rows: Array = []
	for key in keyframes:
		rows.append({
			"k": key.index,
			"pass_time": snappedf(key.pass_time, 0.001),
			"shot": key.shot,
			"trained": key.trained,
			"line": key.line,
			"yours": _pose_data(key.yours),
			"director": _pose_data(key.director),
		})
	return JSON.stringify(rows, "  ", false)


# Every keyframe's screenshot in one image, in K order, three across -- a slot stays empty rather
# than closing up when a keyframe has no picture, so "the third tile" is always K3. Null when no
# keyframe has a picture at all.
func contact_sheet() -> Image:
	var any := false
	for key in keyframes:
		if key.image != null and not key.image.is_empty():
			any = true
	if not any:
		return null
	var columns := mini(keyframes.size(), SHEET_COLUMNS)
	var rows := ceili(float(keyframes.size()) / float(SHEET_COLUMNS))
	var size := Vector2i(columns * THUMB_SIZE.x + (columns + 1) * SHEET_GAP,
			rows * THUMB_SIZE.y + (rows + 1) * SHEET_GAP)
	var sheet := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	sheet.fill(SHEET_BACKGROUND)
	for i in keyframes.size():
		var image := keyframes[i].image
		if image == null or image.is_empty():
			continue
		var thumb := image.duplicate() as Image
		thumb.convert(Image.FORMAT_RGBA8)
		thumb.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_BILINEAR)
		var at := Vector2i(SHEET_GAP + (i % SHEET_COLUMNS) * (THUMB_SIZE.x + SHEET_GAP),
				SHEET_GAP + (i / SHEET_COLUMNS) * (THUMB_SIZE.y + SHEET_GAP))
		sheet.blit_rect(thumb, Rect2i(Vector2i.ZERO, THUMB_SIZE), at)
	return sheet


static func _line_text(line: Array[String]) -> String:
	if line.is_empty():
		return "-"
	return " → ".join(line)


static func _pose_text(pose: Dictionary) -> String:
	if pose.is_empty():
		return "-"
	var aim: Vector3 = pose.get("aim", Vector3.ZERO)
	return "%.1f° / %.1f° / %.2f / (%.2f, %.2f, %.2f)" % [pose.get("yaw", 0.0), pose.get("pitch", 0.0),
			pose.get("distance", 0.0), aim.x, aim.y, aim.z]


# What a pose is for replaying it: where the rig aims, from which yaw and pitch, how far out, and the
# three channels laid over the aim (lift, drop, dolly) so the camera's height and push-in rebuild too.
static func _pose_data(pose: Dictionary) -> Dictionary:
	if pose.is_empty():
		return {}
	return {
		"aim": _vec(pose.get("aim", Vector3.ZERO)),
		"yaw": snappedf(pose.get("yaw", 0.0), 0.01),
		"pitch": snappedf(pose.get("pitch", 0.0), 0.01),
		"distance": snappedf(pose.get("distance", 0.0), 0.001),
		"lift": _vec(pose.get("lift", Vector3.ZERO)),
		"drop": snappedf(pose.get("drop", 0.0), 0.001),
		"dolly": snappedf(pose.get("dolly", 0.0), 0.001),
	}


static func _vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
