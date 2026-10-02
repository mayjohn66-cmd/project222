extends RefCounted


const NO_CATALOG_INDEX: int = -1
const NO_QUICK_SLOT_INDEX: int = -1
const ROTATION_COUNT: int = 4


# 기존 BuildManager의 초기값과 동일하게 유지
var catalog_index: int = 0
var rotation_index: int = 0
var quick_slot_index: int = NO_QUICK_SLOT_INDEX


func select_quick_slot(
	new_catalog_index: int,
	new_quick_slot_index: int
) -> void:
	catalog_index = new_catalog_index
	rotation_index = 0
	quick_slot_index = new_quick_slot_index


func restore_selection(
	new_catalog_index: int,
	new_rotation_index: int
) -> void:
	catalog_index = new_catalog_index

	rotation_index = posmod(
		new_rotation_index,
		ROTATION_COUNT
	)

	quick_slot_index = NO_QUICK_SLOT_INDEX


func clear() -> void:
	catalog_index = NO_CATALOG_INDEX
	rotation_index = 0
	quick_slot_index = NO_QUICK_SLOT_INDEX


func rotate_clockwise() -> void:
	rotation_index = (
		rotation_index + 1
	) % ROTATION_COUNT


func detach_quick_slot() -> void:
	quick_slot_index = NO_QUICK_SLOT_INDEX


func is_quick_slot_selected(
	slot_index: int
) -> bool:
	return (
		quick_slot_index == slot_index
	)


func has_selection() -> bool:
	return catalog_index >= 0
