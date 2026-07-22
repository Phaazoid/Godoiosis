class_name ProstheticWeaponInstance
extends WeaponInstance

# Pure pass-through — limb_kind/built_in_stat (per-instance identity, not
# readiness state) stay on base WeaponInstance. Exists so weapon_type dispatch (#82)
# has a real class to build.
