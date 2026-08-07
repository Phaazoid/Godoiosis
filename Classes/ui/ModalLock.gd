extends Object
class_name ModalLock

# One answer to "is a modal up, and is the game therefore frozen?" (#131).
#
# WHY A LOCK AT ALL, AND WHY NOT A PREDICATE: CameraController._process reads
# Input.is_action_pressed("cam_*") -- bound to WASD -- and a global Input poll does not travel
# through the scene tree. No focus, mouse_filter or set_input_as_handled can stop it, which is why
# typing "was" into the report card panned the board behind it. Gating that one loop would have
# left HoverPresenter._process, and the next _process anyone writes, with the same bug.
#
# WHY THE GAME SUBTREE AND NOT get_tree().paused -- measured 2026-08-05, and the tree-pause version
# SHIPPED BROKEN for one round. The modal lives inside a SubViewport, so a click travels
#   root viewport -> GameContainer (SubViewportContainer) -> GameView (SubViewport) -> ui_layer -> modal
# and GameContainer only forwards input into the viewport while IT can process. Pausing the tree
# froze that link, so PROCESS_MODE_ALWAYS made the modal processable and it still could not be
# clicked -- the pause menu drew, ate the board, and had no working way out. Disabling the Game
# node alone stops every loop under it while leaving the forwarding chain above it alive. Probed
# both ways: identical on "game stopped", opposite on "click path alive".
#
# GROUP MEMBERSHIP IS THE STATE; the lock is DERIVED from it, never set independently. That is what
# makes the pause-menu -> report card -> pause-menu handoff gapless: no modal releases on the
# strength of its own departure while another is opening.
#
# Anything under Game that must survive the freeze sets process_mode = ALWAYS -- the modals
# themselves, and BugReporter + ReportUploader, since an upload is in flight WHILE the card is up
# and HTTPRequest emits request_completed from its own internal process. DevOverlay needs nothing:
# it is a sibling of GameContainer, outside Game entirely.
#
# DEV CONTROLS ARE A LAYER ABOVE THIS LOCK (#154), and DevController is the in-Game exemption: it holds
# every dev key (F1/F2/F3) and is ALWAYS, so they still fire behind a card. A dev key added to
# game.gd instead would die silently whenever a modal is up. Board manipulation (dev spawn, tile
# brush) deliberately stays frozen -- it is not worth editing what the card is covering.

const GROUP := "modal"

static func any_open(tree: SceneTree) -> bool:
	return not tree.get_nodes_in_group(GROUP).is_empty()

# Call from a modal's _build. It registers its own release, so a modal cannot forget to unfreeze.
static func claim(modal: Control, game_root: Node) -> void:
	modal.process_mode = Node.PROCESS_MODE_ALWAYS
	modal.add_to_group(GROUP)

	var tree := modal.get_tree()
	_apply(tree, game_root)
	# Both captured rather than re-fetched: by the time this fires the modal has left the tree, so
	# its own get_tree() is null. It is out of GROUP by then too, which is what makes the count right.
	modal.tree_exited.connect(func() -> void: _apply(tree, game_root))

static func _apply(tree: SceneTree, game_root: Node) -> void:
	if not is_instance_valid(tree) or not is_instance_valid(game_root):
		return
	if any_open(tree):
		game_root.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		game_root.process_mode = Node.PROCESS_MODE_INHERIT
