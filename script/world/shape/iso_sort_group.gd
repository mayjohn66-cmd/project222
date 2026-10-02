class_name IsoSortGroup
extends Node2D
## 자식들의 그리는 순서를 IsoSorter(상자 관계)로 정하는 묶음. 이 노드는 y_sort 를 쓰지 않고, 자식 순서를 직접 바꾼다.
##
## 정렬에 들어가는 자식:
##   - IsoBox: 바닥 발자국과 높이에서 상자를 만든다.
##   - IsoObject: 부품 상자들을 합친 큰 상자 하나로 본다.
##   - 움직이는 물체(캐릭터 등): 자식에 메타 "iso_actor" = Vector3(발자국 x, 발자국 y, 높이 px)를 달면
##     그 노드의 위치(발끝)를 중심으로 한 작은 상자로 본다.
## 상자가 없는 자식(글자, 효과 등)은 건드리지 않는다.
##
## 사용: 자식을 넣은 뒤 refresh() 를 부른다. auto_refresh 가 켜져 있으면 자식의 위치가 바뀔 때마다 알아서 다시 정렬한다.

const TILE: Vector2 = Vector2(96.0, 48.0)

@export var auto_refresh: bool = true

var _last_signature: String = ""


func _ready() -> void:
	y_sort_enabled = false
	refresh()


func _process(_delta: float) -> void:
	if auto_refresh:
		refresh()


# 화면(전역) 좌표 → 아이소 칸 좌표. IsoSorter 와 같은 규칙: 화면 x = (x-y)*반폭, 화면 y = (x+y)*반높이.
static func screen_to_iso(p: Vector2, tile: Vector2 = TILE) -> Vector2:
	var a: float = p.x / (tile.x * 0.5)
	var b: float = p.y / (tile.y * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


# 노드 하나의 정렬 상자. 정렬 대상이 아니면 빈 Dictionary.
static func box_of(node: Node) -> Dictionary:
	if node is IsoBox:
		return _box_from_iso_box(node)

	if node is IsoObject:
		var union: Dictionary = {}

		for part in node.get_parts():
			var b: Dictionary = _box_from_iso_box(part)

			if b.is_empty():
				continue

			union = b if union.is_empty() else {
				"min": Vector3(minf(union["min"].x, b["min"].x), minf(union["min"].y, b["min"].y), minf(union["min"].z, b["min"].z)),
				"max": Vector3(maxf(union["max"].x, b["max"].x), maxf(union["max"].y, b["max"].y), maxf(union["max"].z, b["max"].z)),
			}

		return union

	if node is Node2D and node.has_meta("iso_actor"):
		var size: Vector3 = node.get_meta("iso_actor")
		var c: Vector2 = screen_to_iso(node.global_position)
		return {
			"min": Vector3(c.x - size.x * 0.5, c.y - size.y * 0.5, 0.0),
			"max": Vector3(c.x + size.x * 0.5, c.y + size.y * 0.5, size.z),
		}

	return {}


static func _box_from_iso_box(box: IsoBox) -> Dictionary:
	var corners: PackedVector2Array = box.get_ground_polygon()

	if corners.is_empty():
		return {}

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)

	for p in corners:
		var c: Vector2 = screen_to_iso(box.global_position + p)
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.y))

	return {"min": Vector3(lo.x, lo.y, box.elevation), "max": Vector3(hi.x, hi.y, box.elevation + box.height)}


# 정렬해서 자식 순서를 바꾼다. 결과(IsoSorter.sort_items 반환값)를 돌려준다. 바뀐 게 없으면 {}.
func refresh() -> Dictionary:
	var items: Array = []
	var nodes: Dictionary = {}
	var slots: Array = []

	for i in range(get_child_count()):
		var child: Node = get_child(i)
		var b: Dictionary = box_of(child)

		if b.is_empty():
			continue

		var id: int = child.get_instance_id()
		items.append({"id": id, "min": b["min"], "max": b["max"]})
		nodes[id] = child
		slots.append(i)

	if items.size() < 2:
		return {}

	var signature: String = _signature(items)

	if signature == _last_signature:
		return {}

	_last_signature = signature
	var result: Dictionary = IsoSorter.sort_items(items)

	# 정렬 대상이 차지하던 자리(slots)에 새 순서대로 다시 놓는다. 대상이 아닌 자식은 제자리에 둔다.
	for k in range(result["order"].size()):
		move_child(nodes[result["order"][k]], slots[k])

	return result


func _signature(items: Array) -> String:
	var parts: PackedStringArray = []

	for item in items:
		parts.append("%d:%s:%s" % [item["id"], str(item["min"]), str(item["max"])])

	parts.sort()  # 자식 순서가 바뀌어도 같은 배치는 같은 서명
	return "|".join(parts)
