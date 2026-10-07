class_name OpeningCleanup
extends RefCounted
## 새 게임 초반의 "부서진 가게 정리": 바닥의 잔해 더미(6곳)를 [E]로 치우면 쓸 만한 철광석을 얻는다(모두 4개: 간이 진열대 제작에 2개씩이라 두 개를 만들 수 있다). 쓸 만한 게 없는 더미도 있다.
## 이 자재로 나무 진열대를 제작하고(설계도), 건진 계산대·진열대와 함께 건축 모드로 설치하는 것이 이어지는 튜토리얼이다.
## 더미 위치·얻는 자재는 `PILES`에서 조정한다. 잔해 그림은 `OpeningStoreDressing`(3D 연출)이 그리고, 치운 더미는 그림에서도 사라진다.
## 진행은 이야기 기록(`tutorial_event:cleanup:<번호>`)에 남아 저장·불러오기 뒤에도 이어진다.

const BEAT := "tutorial_event:cleanup:"
const REACH_CELLS := 1.7           # 더미에서 이만큼(칸) 안이면 [E]로 치울 수 있다

# stand: 서서 치우는 자리(칸 좌표). props: 이 더미가 치우는 연출 집기 번호(`OpeningStoreDressing.PROPS`). loot: 얻는 자재.
const PILES := [
	{"stand": Vector2(4.0, 1.0), "props": [0, 1, 2], "loot": {"iron_ore": 1}},
	{"stand": Vector2(7.0, 1.0), "props": [3, 4, 5, 6], "loot": {"iron_ore": 1}},
	{"stand": Vector2(1.3, 1.6), "props": [7], "loot": {"iron_ore": 1}},
	{"stand": Vector2(1.3, 6.2), "props": [8], "loot": {}},
	{"stand": Vector2(5.0, 3.0), "props": [9, 10], "loot": {}},
	{"stand": Vector2(6.0, 5.0), "props": [11, 12, 13], "loot": {"iron_ore": 1}},
]


static func done(index: int) -> bool:
	return PlayerProgress.story_beat_days.has(BEAT + str(index))


static func cleaned_count() -> int:
	var count: int = 0

	for i in range(PILES.size()):
		if done(i):
			count += 1

	return count


static func all_done() -> bool:
	return cleaned_count() >= PILES.size()


# 이 더미를 치우고 얻은 자재를 인벤토리에 넣는다. 이미 치웠으면 빈 사전.
static func clean(index: int) -> Dictionary:
	if index < 0 or index >= PILES.size() or done(index):
		return {}

	var loot: Dictionary = (PILES[index]["loot"] as Dictionary).duplicate()

	for id in loot:
		GameState.add_item(str(id), int(loot[id]))

	PlayerProgress.record_story_beat(BEAT + str(index), GameState.total_day)
	return loot


# 아직 안 치운 더미 중 player_cell(칸 좌표)에서 가장 가까운 것의 번호. 없으면 -1.
static func nearest(player_cell: Vector2, max_distance: float = INF) -> int:
	var best: int = -1
	var best_distance: float = max_distance

	for i in range(PILES.size()):
		if done(i):
			continue

		var d: float = player_cell.distance_to(PILES[i]["stand"])

		if d <= best_distance:
			best = i
			best_distance = d

	return best


static func loot_text(loot: Dictionary) -> String:
	var parts: Array[String] = []

	for id in loot:
		parts.append("%s ×%d" % [ItemData.get_item_name(str(id)), int(loot[id])])

	return ", ".join(parts) if not parts.is_empty() else "쓸 만한 건 없었다"
