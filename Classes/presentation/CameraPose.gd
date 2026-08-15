extends Resource
class_name CameraPose

# An AUTHORED camera start (#234): where a mission opens, as a pose rather than a derived volume.
# Stored on ScenarioData, captured off the live rig by the Scenario tab, applied by battle3d.
#
# ONE resource rather than three loose floats on ScenarioData, so the flythrough idea #234 defers
# (a slow orbit-and-descend that LANDS on the start) extends this into a keyframe instead of
# re-homing three fields that had already grown callers.
#
# `aim` is the rig's own position -- what frame()'s _aim_at() produces, i.e. the box centre lifted
# to the top of what is being looked at. Yaw is free: the rig rests wherever you leave it (#176
# stage 4d), so an authored start may sit off-detent on purpose. Distance is the camera's z offset
# from the rig.

@export var aim := Vector3.ZERO
@export var yaw_degrees := 0.0
@export var distance := 14.0
