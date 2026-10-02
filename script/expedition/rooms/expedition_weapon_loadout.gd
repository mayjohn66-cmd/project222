class_name ExpeditionWeaponLoadout
extends RefCounted


# 원정 가방의 무기(최대 2개)를 방 안에서 골라 쓰는 "무기 교체" 묶음.
#   - 교체하면 공격 방식(공격 프로필)과 그 무기의 공격 보너스가 함께 바뀐다.
#   - 화면에는 공격력 숫자를 보이지 않고 무기 이름과 공격 방식만 보인다(사용자 결정).
# 무기 순서는 가방에 놓인 순서이고, 처음에는 첫 번째 무기를 든다.
# 무기가 하나도 없으면 맨손(기본 공격)이다.

var slots: Array[Dictionary] = []
var active_index: int = 0
var default_profile: ExpeditionAttackProfile


# settings: ExpeditionRoomSettings. bag: ExpeditionBag(없어도 됨).
func build(
	settings: ExpeditionRoomSettings,
	bag
) -> void:
	slots.clear()
	active_index = 0
	default_profile = settings.default_attack

	if bag == null:
		return

	for placement in bag.placements:
		var item_id: String = str(placement.get("item_id", ""))

		if not ExpeditionEquipmentData.has_equipment(item_id):
			continue

		if ExpeditionEquipmentData.get_equipment_type(item_id) != ExpeditionEquipmentData.TYPE_WEAPON:
			continue

		slots.append({
			"item_id": item_id,
			"profile": profile_for(settings, item_id),
			"bonus": int(EquipmentEnhancementService.get_effective_value(placement))
		})

		if slots.size() >= 2:
			break


static func profile_for(
	settings: ExpeditionRoomSettings,
	item_id: String
) -> ExpeditionAttackProfile:
	for profile in settings.equipment_attacks:
		if profile.equipment_id == item_id:
			return profile

	return settings.default_attack


func has_choice() -> bool:
	return slots.size() >= 2


func active_profile() -> ExpeditionAttackProfile:
	if slots.is_empty():
		return default_profile

	return slots[active_index]["profile"]


# 들고 있는 무기의 공격 보너스(무기가 없으면 0).
func active_bonus() -> int:
	if slots.is_empty():
		return 0

	return int(slots[active_index]["bonus"])


func active_name() -> String:
	if slots.is_empty():
		return "맨손"

	return ItemData.get_item_name(str(slots[active_index]["item_id"]))


# 교체하면 들고 있지 않은 다음 무기를 든다. 바꿀 무기가 없으면 false.
func swap() -> bool:
	if not has_choice():
		return false

	active_index = (active_index + 1) % slots.size()
	return true


func other_name() -> String:
	if not has_choice():
		return ""

	return ItemData.get_item_name(
		str(slots[(active_index + 1) % slots.size()]["item_id"])
	)


# 화면에 보이는 공격 방식 설명(숫자 없이). settings가 없으면 tres를 불러온다.
static func get_style_text(
	item_id: String
) -> String:
	var settings: ExpeditionRoomSettings = load(
		"res://scenes/expedition/rooms/default_room_settings.tres"
	) as ExpeditionRoomSettings

	if settings == null:
		return ""

	var profile: ExpeditionAttackProfile = profile_for(settings, item_id)
	var parts: Array[String] = [profile.display_name]

	parts.append(
		"원거리" if profile.method == ExpeditionAttackProfile.Method.PROJECTILE else "근접"
	)

	if profile.cooldown <= 0.3:
		parts.append("매우 빠름")
	elif profile.cooldown >= 0.6:
		parts.append("느림")

	if profile.max_targets >= 2:
		parts.append("여러 적 동시 타격")

	if profile.knockback >= 0.3:
		parts.append("밀어냄")

	if profile.heal_fraction > 0.0:
		parts.append("체력 회복")

	return " · ".join(parts)
