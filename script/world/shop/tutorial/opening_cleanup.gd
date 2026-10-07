class_name OpeningCleanup
extends RefCounted
## 새 게임 초반의 "부서진 가게 정리": 바닥의 잔해 더미(6곳)를 [E]로 치우면 쓸 만한 철광석을 얻는다(모두 4개: 간이 진열대 제작에 2개씩이라 두 개를 만들 수 있다). 쓸 만한 게 없는 더미도 있다.
## 이 자재로 나무 진열대를 제작하고(설계도), 건진 계산대·진열대와 함께 건축 모드로 설치하는 것이 이어지는 튜토리얼이다.
## 더미 위치·얻는 자재는 집기 배치(`OpeningStoreLayout`)에서 자동으로 정해진다(`_build`). 잔해 그림은 `OpeningStoreDressing`(3D 연출)이 그리고, 치운 더미는 그림에서도 사라진다.
## 진행은 이야기 기록(`tutorial_event:cleanup:<번호>`)에 남아 저장·불러오기 뒤에도 이어진다.

const BEAT := "tutorial_event:cleanup:"
const REACH_CELLS := 1.7           # 더미에서 이만큼(칸) 안이면 [E]로 치울 수 있다

const GROUPS := 6                   # 잔해 더미 수(집기가 6개 미만이면 그 수만큼)
const ORE_TOTAL := 4                # 모두 치우면 얻는 철광석(간이 진열대 두 개분)

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

	# 철광석 ORE_TOTAL 개를 묶음에 고르게
	if groups >= ORE_TOTAL:
		for i in range(ORE_TOTAL):
			result[roundi(float(i) * float(groups - 1) / float(ORE_TOTAL - 1))]["loot"] = {"iron_ore": 1}
	else:
		for i in range(ORE_TOTAL):
			var target: Dictionary = result[i % groups]["loot"]
			target["iron_ore"] = int(target.get("iron_ore", 0)) + 1

	return result


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
		parts.append("%s ×%d" % [ItemData.get_item_name(str(id)), int(loot[id])])

	return ", ".join(parts) if not parts.is_empty() else "쓸 만한 건 없었다"
