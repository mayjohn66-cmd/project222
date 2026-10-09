class_name ExpeditionBagController
extends RefCounted


# 원정 가방 화면의 선택·드래그 앤 드롭·회전과 전리품 정리(가방에 넣기, 되돌리기, 포기)를 담당한다.
# 가방과 임시 전리품은 체크포인트와 이벤트도 쓰므로 host(expedition.gd)가 가지고 있다.
# 그리드 뷰와 전리품 카드는 host를 대상으로 호출하므로, host는 같은 이름의 함수를 위임으로 남긴다.
# host는 씬 노드라서 타입을 붙이지 않는다.

const LOOT_ITEM_CARD_SCRIPT = preload(
	"res://script/ui/expedition/loot_item_card.gd"
)

var host


func setup(new_host) -> void:
	host = new_host


# 관리 인벤토리 등 외부 UI에서 현재 원정 가방을
# 조회할 때 사용하는 읽기 전용 복사본이다.
func get_active_bag_placements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	DebugLog.write(
		"[통합 인벤토리 확인] 원정 가방 모델 존재: ",
		host.expedition_bag != null
	)

	if host.expedition_bag == null:
		return result

	for placement in host.expedition_bag.placements:
		result.append(
			placement.duplicate(true)
		)

	DebugLog.write(
		"[통합 인벤토리 확인] 실시간 가방 배치: ",
		result
	)

	return result


# =========================================================
# 원정 가방과 전리품 정리
# =========================================================

func setup_grid_view() -> void:
	if host.expedition_bag == null:
		return

	if host.bag_grid_view == null:
		return

	host.bag_grid_view.setup(
		"bag",
		host.expedition_bag,
		host,
		host.expedition_bag.width,
		host.expedition_bag.height,
		52
	)


func refresh_bag_ui() -> void:
	if host.bag_grid_view == null:
		return

	if host.expedition_bag == null:
		return

	host.bag_grid_view.refresh()
	host.bag_grid_view.refresh_selection_visuals()


func select_grid_item(
	source: String,
	uid: int
) -> void:
	if source != "bag":
		return

	if uid < 0:
		return

	host.selected_bag_uid = uid

	if host.bag_grid_view != null:
		host.bag_grid_view.refresh_selection_visuals()


func toggle_grid_item(
	source: String,
	uid: int
) -> void:
	if source != "bag":
		return

	if uid < 0:
		return

	if host.selected_bag_uid == uid:
		host.selected_bag_uid = -1
	else:
		host.selected_bag_uid = uid

	if host.bag_grid_view != null:
		host.bag_grid_view.refresh_selection_visuals()


func is_grid_item_selected(
	source: String,
	uid: int
) -> bool:
	return (
		source == "bag"
		and host.selected_bag_uid == uid
	)


func clear_grid_selection(
	source: String
) -> void:
	if source != "bag":
		return

	host.selected_bag_uid = -1

	if host.bag_grid_view != null:
		host.bag_grid_view.refresh_selection_visuals()


func can_drop_grid_data(
	target_source: String,
	data: Dictionary,
	cursor_cell: Vector2i
) -> bool:
	if target_source != "bag":
		return false

	if host.expedition_bag == null:
		return false

	var source: String = str(
		data.get(
			"source",
			""
		)
	)

	var grab_offset: Vector2i = data.get(
		"grab_offset_cell",
		Vector2i.ZERO
	)

	var target_cell: Vector2i = (
		cursor_cell - grab_offset
	)

	if source == "bag":
		var uid: int = int(
			data.get(
				"uid",
				-1
			)
		)

		var placement: Dictionary = (
			host.expedition_bag.get_placement(
				uid
			)
		)

		if placement.is_empty():
			return false

		var item_id: String = str(
			placement.get(
				"item_id",
				""
			)
		)

		var rotated: bool = bool(
			placement.get(
				"rotated",
				false
			)
		)

		return host.expedition_bag.can_place(
			item_id,
			target_cell,
			rotated,
			uid
		)

	if source == "loot":
		var loot_index: int = int(
			data.get(
				"loot_index",
				-1
			)
		)

		if (
			loot_index < 0
			or loot_index >= host.temporary_loot.size()
		):
			return false

		var loot: Dictionary = (
			host.temporary_loot[loot_index]
		)

		var item_id: String = str(
			loot.get(
				"item_id",
				""
			)
		)

		if item_id.is_empty():
			return false

		return host.expedition_bag.can_place(
			item_id,
			target_cell,
			false
		)

	return false


func drop_grid_data(
	target_source: String,
	data: Dictionary,
	cursor_cell: Vector2i
) -> void:
	if not can_drop_grid_data(
		target_source,
		data,
		cursor_cell
	):
		return

	var source: String = str(
		data.get(
			"source",
			""
		)
	)

	var grab_offset: Vector2i = data.get(
		"grab_offset_cell",
		Vector2i.ZERO
	)

	var target_cell: Vector2i = (
		cursor_cell - grab_offset
	)

	# 원정 가방 내부 이동
	if source == "bag":
		var uid: int = int(
			data.get(
				"uid",
				-1
			)
		)

		if host.expedition_bag.move_item(
			uid,
			target_cell
		):
			host.selected_bag_uid = uid
			refresh_bag_ui()

		return

	# 임시 전리품 → 원정 가방
	if source == "loot":
		var loot_index: int = int(
			data.get(
				"loot_index",
				-1
			)
		)

		if (
			loot_index < 0
			or loot_index >= host.temporary_loot.size()
		):
			return

		var loot: Dictionary = (
			host.temporary_loot[loot_index]
		)

		var item_id: String = str(
			loot.get(
				"item_id",
				""
			)
		)

		var amount: int = int(
			loot.get(
				"amount",
				1
			)
		)

		var new_uid: int = (
			host.expedition_bag.add_item(
				item_id,
				target_cell,
				amount,
				false,
				{"blacksmith_ore_origin": bool(loot.get("blacksmith_ore_origin", false))}
			)
		)

		if new_uid < 0:
			return

		host.temporary_loot.remove_at(
			loot_index
		)

		host.selected_bag_uid = new_uid

		refresh_loot_ui()
		refresh_bag_ui()


func rotate_selected_bag_item() -> void:
	if host.selected_bag_uid < 0:
		return

	if host.expedition_bag == null:
		return

	if not host.expedition_bag.rotate_item(
		host.selected_bag_uid
	):
		return

	refresh_bag_ui()


func refresh_loot_ui():
	for child in host.loot_grid.get_children():
		child.queue_free()

	for index in range(
		host.temporary_loot.size()
	):
		var loot: Dictionary = (
			host.temporary_loot[index]
		)

		var item_id: String = str(
			loot.get(
				"item_id",
				""
			)
		)

		var amount: int = int(
			loot.get(
				"amount",
				1
			)
		)

		var card = LOOT_ITEM_CARD_SCRIPT.new()

		card.custom_minimum_size = Vector2(
			100,
			80
		)

		host.loot_grid.add_child(card)

		card.setup(
			index,
			item_id,
			amount,
			host
		)


func return_bag_item_to_loot(
	data: Dictionary
):
	var uid: int = int(
		data.get(
			"uid",
			-1
		)
	)

	if uid < 0:
		return

	var placement: Dictionary = (
		host.expedition_bag.remove_item(
			uid
		)
	)

	if placement.is_empty():
		return

	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	var amount: int = int(
		placement.get(
			"amount",
			1
		)
	)

	host.temporary_loot.append(
		{
			"item_id": item_id,
			"blacksmith_ore_origin": bool(placement.get("blacksmith_ore_origin", false)),
			"amount": amount
		}
	)

	host.selected_bag_uid = -1

	DebugLog.write(
		"[전리품] 가방 → 임시 보관함: ",
		ItemData.get_item_name(
			item_id
		),
		" ×",
		amount
	)

	refresh_bag_ui()
	refresh_loot_ui()


func confirm_loot_organization() -> void:
	if host.current_expedition_phase != host.ExpeditionPhase.RUN:
		return

	if not host.loot_panel.visible:
		return

	# 남은 전리품이 없다면 바로 완료
	if host.temporary_loot.is_empty():
		finish_loot_organization()
		return

	var remaining_amount: int = 0

	for loot in host.temporary_loot:
		remaining_amount += maxi(
			int(loot.get("amount", 0)),
			0
		)

	host.discard_loot_dialog.dialog_text = (
		"가방에 넣지 않은 전리품이 %d개 남아 있습니다."
		% remaining_amount
		+ "\n남은 전리품을 포기하고 진행하시겠습니까?"
	)

	host.discard_loot_dialog.popup_centered()


func finish_loot_organization() -> void:
	if host.current_expedition_phase != host.ExpeditionPhase.RUN:
		return

	if not host.loot_panel.visible:
		return

	if not host.temporary_loot.is_empty():
		DebugLog.write(
			"[전리품] 포기한 아이템: ",
			host.temporary_loot
		)

	host.temporary_loot.clear()
	host.selected_bag_uid = -1

	refresh_loot_ui()
	refresh_bag_ui()

	host.loot_panel.visible = false

	host.update_ui()

	DebugLog.write("[전리품] 정리 완료 / 가방 아이템 유지")

	host.complete_current_map_node()
