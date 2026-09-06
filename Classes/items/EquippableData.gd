class_name EquippableData
extends Item

# Shared base for anything a unit slots into its single equip slot — today WeaponInstance and
# RuneData. Its job is to be the slot's TYPE, so the equip slot, inventory, and save entry can
# hold "an equippable" without caring which kind (docs/design/alchemy-kit.md) — AND to answer
# what that equippable can fire (the attack-source surface) or DO (the weapon-verb surface),
# both declared below as inert defaults.
#
# NOTE (2026-07-26) — this REPLACES the older rule that EquippableData deliberately had no combat
# surface and that "combat sites cast as WeaponInstance; a rune yields null -> inert path". That
# held while there was one cast site. There were eventually four fork methods on Unit restating
# the same two-kind dispatch. The outcome is unchanged — a rune still does nothing in melee — but
# it is now declared ONCE, as inert defaults each kind overrides. This mirrors the pattern
# WeaponInstance already uses a level down, where the base declares the readiness surface as
# no-op virtuals so families with no signature mechanic pay nothing (#73).

# Which side of the world an attack affects (#50). Shared vocabulary: both WeaponData.targets
# and TransmutationData.targets are this enum. APPEND-ONLY (serializes as an int in .tres).
enum TargetMode { UNIT, MAP, BOTH }

# WHY this unit may not equip this — "" means they may (#744). Each kind states its own
# disqualifier here: armor reads the wearer's BODY stats, a rune reads aura+affinity (#157).
#
# THE REASON IS THE RULE AND THE BOOLEAN IS DERIVED FROM IT, which is what stops a refusal and its
# explanation from drifting apart — TransmutationData.channel_block_reason's shape, one class family
# down, and #108's lesson that a seam unable to say what content needs grows a second one. It had
# grown three: armor's wielder-free requirement_text, a hardcoded "can't channel" on the equip
# button, and a generic "cannot equip it" on the pre-mission card.
#
# SO A KIND OVERRIDES THIS, NEVER can_equip. Overriding the boolean puts the two answers back in
# separate places, which is the state this replaced; tests/items/test_equip_reason.gd refuses it.
#
# Build the sentence only on the way OUT, the way channel_block_reason does: can_equip runs inside
# Unit._enforce_gear_gates on every stat settle, so the success path must allocate nothing.
#
# Deliberately NOT the two-handed wield lock — that is a firing question (Unit.can_wield_equipped),
# and #776 owns saying so.
func can_equip_reason(_wielder: Unit) -> String:
	return ""

# Enforced at the equip doors and re-enforced at Unit._enforce_gear_gates, so "no" here also means
# "comes off when it becomes no".
func can_equip(wielder: Unit) -> bool:
	return can_equip_reason(wielder).is_empty()

# --- Attack-source surface ---
# Every default here is the INERT answer, so a kind that can't fire (armor) needs no override.

# Everything the wielder could choose to fire right now — the attack pick-menu's contents. A
# watch-only attack is never here; the overwatch fork below is what keeps the two views apart.
func selectable_attacks(_wielder: Unit) -> Array[AttackData]:
	return []

# What fires when the player hasn't picked anything specific.
func default_attack(_wielder: Unit) -> AttackData:
	return null

# What a COUNTER fires. Separate from default_attack because the two kinds genuinely diverge on
# whether a live pick counts — see each override.
func counter_attack(wielder: Unit) -> AttackData:
	return default_attack(wielder)

# Non-default attacks, surfaced under the Weapon Action submenu. Weapons only.
func secondary_attacks(_wielder: Unit) -> Array[AttackData]:
	return []

# Attacks this source offers as a flat menu of EQUALS — the Transmutation category (#88). A rune
# has no authored main_attack: its carvings are interchangeable, so all of them belong in one
# picker. A weapon does have an authored main, so its extras go under Weapon Action instead and
# this stays empty. Exactly the split secondary_attacks() makes, from the other side.
func choice_attacks(_wielder: Unit) -> Array[AttackData]:
	return []

# --- The overwatch fork (#590) ---
# THE exclusivity rule, and its only spelling. `can_overwatch` does not ADD a verb to a fireable
# attack -- it IS what the attack is (dev, 2026-08-27: "when I check the 'can overwatch' box, I
# expect to get an attack that is an overwatch, and only an overwatch. It isn't an either or
# thing."). So whatever a source carries splits into two DISJOINT views -- what can be fired, and
# what can be watched with -- and nothing sits in both.
#
# Asked through effective_can_overwatch rather than the raw flag, so a mod that grants or revokes
# the capability MOVES an attack between the views instead of leaving it in one and claiming the
# other. One question, one answer: #590 happened because the two views were the SAME list, so a
# watch attack kept a firing twin whose name ate its row in the menu's duplicate guard.

# Everything this source carries, fireable or watch-only -- the ONE list the views come off. A
# weapon's is its available attacks (main + extras + mod grants), a rune's is every carving.
func repertoire(_wielder: Unit) -> Array[AttackData]:
	return []

# The watch view. Unit.overwatch_attacks is its only caller, so the menu's Overwatch rows and the
# kit-slice gate reach it through one door and can never disagree. Reads the FULL repertoire, not
# the affordable subset -- #166's law, an unusable row lists and greys with its own reason.
func watch_attacks(wielder: Unit) -> Array[AttackData]:
	var result: Array[AttackData] = []
	for attack: AttackData in repertoire(wielder):
		if effective_can_overwatch(wielder, attack):
			result.append(attack)
	return result

# The fire view's filter, applied by every surface that offers something to FIRE: the pick menu,
# the Weapon Action rows, the Transmutation rows, the AI's candidate list. Takes the list rather
# than deriving it, because each of those answers a different question first (channelable,
# non-main, affordable) and only the overwatch clause is shared between them.
func fireable_only(wielder: Unit, attacks: Array[AttackData]) -> Array[AttackData]:
	var result: Array[AttackData] = []
	for attack: AttackData in attacks:
		if not effective_can_overwatch(wielder, attack):
			result.append(attack)
	return result

# What an attack's SHOVE and ALLY-SPLASH actually are once the firing source has had its say
# (#529). Two fields a fitted mod may edit, and the pair is deliberately small: an override may
# only touch what is read AFTER the attack is chosen. Anything that changes how an attack is
# AIMED -- its pattern, its reach -- arrives as a whole replacement attack instead, because Reach
# answers those with no wielder in hand.
#
# The default is the attack's own authored value, so a rune carving and a bare fist need neither
# override and armor needs no opinion at all.
func effective_knockback(_wielder: Unit, attack: AttackData) -> int:
	return attack.knockback if attack != null else 0

func effective_hits_allies(_wielder: Unit, attack: AttackData) -> bool:
	return attack != null and attack.hits_allies

func effective_can_overwatch(_wielder: Unit, attack: AttackData) -> bool:
	return attack != null and attack.can_overwatch

# --- Explaining an attack (#166) ---
# Why a menu row is greyed, and what the row does — both asked of the SOURCE, because only it knows
# its own economy (a weapon's readiness, a rune's aura). Keeping them here is what lets the menu
# LIST everything a unit owns and disable what it can't use, instead of hiding it: a menu can only
# grey what it can explain. Inert defaults, so a kind with no economy needs no override.

# "" = fireable. Unit.is_attack_fireable is DERIVED from this, so the refusal and its explanation
# are one answer — never a boolean here and a reason string somewhere else (Law #4).
func attack_block_reason(_wielder: Unit, _attack: AttackData) -> String:
	return ""

# What this attack does for this wielder, for the hover readout. Per-kind because the payload
# number is (a carving scales off aura, a weapon attack off its weapon — #72).
func attack_detail(_wielder: Unit, _attack: AttackData) -> String:
	return ""

# --- Weapon-verb surface (#73/#84, promoted here from WeaponInstance 2026-07-27) ---
# The self-abilities the Weapon Action menu can offer. Same shape and same reasoning as the
# attack surface above: every default is the INERT answer, so Unit asks whatever is in the slot
# without knowing its kind, and a rune or an armour piece answers "no" for free.
#
# Where the line falls: what UNIT delegates lives here; what a deliberate `as WeaponInstance`
# cast reads stays down on WeaponInstance. That is not a style call — `is_attack_fireable` and
# `consume_readiness_for` take a `WeaponAttackData`, so widening them to `AttackData` for this
# base would break every family override's signature. Real bodies (and per-family overrides) live
# on WeaponInstance.
#
# The reload trio TAKES A WIELDER as of #97, and reload_block_reason is the rule the boolean is
# derived from — can_equip_reason's shape (#744), for the same reason: the Chemical Spitter's rearm
# consumes a vial out of the wielder's inventory, so "may I rearm" stopped being answerable by the
# weapon alone, and a menu can only grey what it can explain. Deliberately NOT defaulted to null:
# a wielder-less call would answer "no matching vial" for a weapon nobody is holding, which is a
# refusal wearing the wrong reason.

# "" = may rearm. The one rule; can_reload is derived from it and never disagrees.
func reload_block_reason(_wielder: Unit) -> String:
	return "This cannot be reloaded."

func can_reload(wielder: Unit) -> bool:
	return reload_block_reason(wielder) == ""

func reload(_wielder: Unit) -> void:
	pass

# What the Weapon Action menu CALLS this rearm. The ORDER is always ActionType.RELOAD — only the
# word changes, so Springspear keeps "Spring Load" while the queue, the AI, and the Play API all
# see one verb (#84).
func reload_label() -> String:
	return "Reload"

# Does this kind of gear own a rearm verb AT ALL, full or not? Separate from can_reload because the
# Weapon Action slice opens on this (#97) — a spitter with an empty tank and no vial has no
# actionable verb, and hiding the slice would hide the greyed row that explains exactly that.
func has_reload_verb() -> bool:
	return false

func can_rev() -> bool:
	return false

func rev() -> void:
	pass

func tick_rev() -> void:
	pass

func can_burrow() -> bool:
	return false
