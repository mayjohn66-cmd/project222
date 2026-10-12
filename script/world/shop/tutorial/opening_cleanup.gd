class_name OpeningCleanup
extends RefCounted
## 새 게임 초반의 "부서진 가게 정리": 바닥의 잔해 더미(6곳)를 [E]로 치우면 쓸 만한 것이 나온다(`LOOT_TOTAL`: 빵·물·합판·계산대·간이 진열대). 아무것도 없는 더미도 있다.
## 제작은 아직 모른다(나중에 기술자를 만나 배운다). 건진 계산대·진열대를 건축 모드로 설치하는 것이 이어지는 튜토리얼이다.
## 더미 위치·얻는 자재는 집기 배치(`OpeningStoreLayout`)에서 자동으로 정해진다(`_build`). 잔해 그림은 `OpeningStoreDressing`(3D 연출)이 그리고, 치운 더미는 그림에서도 사라진다.
## 진행은 이야기 기록(`tutorial_event:cleanup:<번호>`)에 남아 저장·불러오기 뒤에도 이어진다.

const BEAT := "tutorial_event:cleanup:"
const FURNITURE_PREFIX := "furniture:"
const REACH_CELLS := 1.7           # 더미에서 이만큼(칸) 안이면 [E]로 치울 수 있다

const GROUPS := 6                   # 잔해 더미 수(집기가 6개 미만이면 그 수만큼)
# 모두 치우면 얻는 것. 식품 수량은 하루 판매량 측정(docs/콘텐츠/프롤로그와_1막/재고_소진_원정_유도안.md 8장)에서 정했다: 첫 손님·교환을 빼고 약 3영업일분(빵 14, 물 10). 키가 `furniture:` 로 시작하면 가구(보관함에 들어간다), 아니면 아이템. 합계는 더미들에 나뉜다.
const LOOT_TOTAL := {"bread": 14, "water": 10, "plywood": 4, "furniture:register": 1, "furniture:shelf_1x1": 2}
# 어울리는 더미(그 더미가 치우는 집기 종류)에 먼저 놓는다. 없으면 아무 더미나.
const LOOT_HOME := {"bread": ["cooler", "chest"], "water": ["cooler", "chest"], "plywood": ["gondola", "rack", "cabinet", "table"], "furniture:register": ["counter"], "furniture:shelf_1x1": ["gondola", "rack"]}

# 더미 목록: {stand: 서서 치우는 자리(칸 좌표), props: 이 더미가 치우는 집기 번호(`OpeningStoreLayout.props()` 순서), loot: 얻는 자재}.
# 집기 배치에서 자동으로 만든다: 집기를 위치(x, y) 순으로 6묶음으로 나누고, 묶음의 앞쪽(+y)에 서서 치운다.
# 철광석은 묶음에 고르게 흩어 놓는다(받지 못하는 더미도 있다).
static var _piles: Array = []


static func piles() -> Array:
	if _piles.is_empty():
		_piles = _build()

	return _piles


# 배치가 바뀌면(개발자 모드 저장) 다시 만들게 한다.
static func reset() -> void:
	_piles = []


static func _build() -> Array:
	var props: Array = OpeningStoreLayout.props()
	var count: int = props.size()

	if count == 0:
		return []

	var order: Array = range(count)
	order.sort_custom(func(a, b) -> bool:
		var pa: Vector2i = props[a]["anchor"]
		var pb: Vector2i = props[b]["anchor"]
		return pa.x < pb.x or (pa.x == pb.x and pa.y < pb.y))
	var groups: int = mini(GROUPS, count)
	var result: Array = []

	for g in range(groups):
		var lo: int = g * count / groups
		var hi: int = (g + 1) * count / groups
		var members: Array = []
		var bounds := Rect2()
		var first := true

		for k in range(lo, hi):
			var index: int = int(order[k])
			members.append(index)
			var rect: Rect2 = OpeningStoreLayout.rect_of(props[index])
			bounds = rect if first else bounds.merge(rect)
			first = false

		var stand := Vector2(clampf(bounds.get_center().x, 0.5, 8.5), clampf(bounds.end.y + 0.8, 0.8, 7.0))
		result.append({"stand": stand, "props": members, "loot": {}})

	_spread_loot(result, props)
	return result


# LOOT_TOTAL 을 더미들에 나눠 담는다(어울리는 더미에 돌아가며 한 개씩).
static func _spread_loot(result: Array, props: Array) -> void:
	var models: Array = []

	for pile in result:
		var set: Dictionary = {}

		for index in pile["props"]:
			set[str(props[index]["model"])] = true

		models.append(set)

	for key in LOOT_TOTAL:
		var eligible: Array = []

		for i in range(result.size()):
			for model in LOOT_HOME.get(key, []):
				if (models[i] as Dictionary).has(model):
					eligible.append(i)
					break

		if eligible.is_empty():
			eligible = range(result.size())

		for n in range(int(LOOT_TOTAL[key])):
			var loot: Dictionary = result[eligible[n % eligible.size()]]["loot"]
			loot[key] = int(loot.get(key, 0)) + 1


static func done(index: int) -> bool:
	return PlayerProgress.story_beat_days.has(BEAT + str(index))


static func cleaned_count() -> int:
	var count: int = 0

	for i in range(piles().size()):
		if done(i):
			count += 1

	return count


static func all_done() -> bool:
	return cleaned_count() >= piles().size()


# 이 더미를 치우고 얻은 자재를 인벤토리에 넣는다. 이미 치웠으면 빈 사전.
static func clean(index: int) -> Dictionary:
	if index < 0 or index >= piles().size() or done(index):
		return {}

	var loot: Dictionary = (piles()[index]["loot"] as Dictionary).duplicate()

	for id in loot:
		if str(id).begins_with(FURNITURE_PREFIX):
			GameState.add_furniture(str(id).trim_prefix(FURNITURE_PREFIX), int(loot[id]))
		else:
			GameState.add_item(str(id), int(loot[id]))

	PlayerProgress.record_story_beat(BEAT + str(index), GameState.total_day)
	return loot


# 아직 안 치운 더미 중 player_cell(칸 좌표)에서 가장 가까운 것의 번호. 없으면 -1.
static func nearest(player_cell: Vector2, max_distance: float = INF) -> int:
	var best: int = -1
	var best_distance: float = max_distance

	for i in range(piles().size()):
		if done(i):
			continue

		var d: float = player_cell.distance_to(piles()[i]["stand"])

		if d <= best_distance:
			best = i
			best_distance = d

	return best


static func loot_text(loot: Dictionary) -> String:
	var parts: Array[String] = []

	for id in loot:
		var name: String = FurnitureData.get_furniture_name(str(id).trim_prefix(FURNITURE_PREFIX)) if str(id).begins_with(FURNITURE_PREFIX) else ItemData.get_item_name(str(id))
		parts.append("%s ×%d" % [name, int(loot[id])])

	return ", ".join(parts) if not parts.is_empty() else "쓸 만한 건 없었다"
