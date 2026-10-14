extends Node
## 초반 땅 → 마을 지형 "점점 밝히기" 검사: 가게에서 바깥으로 칸이 늘어나고, 줄어들지 않으며, 끝나면 마을 지형 전체가 된다.
var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func make_world() -> Node:
	GameState.initialize_new_game()
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	world.get_node("TutorialDirector").enabled = false
	for i in range(20):
		await get_tree().process_frame
	return world


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	# 1) 끄면 바로 마을 지형(시험 기본과 같은 동작)
	TerrainFade.force_for_test(false)
	var world = await make_world()
	var exterior = world.get_node("StoreExterior")
	check(exterior.is_wild(), "새 게임은 낯선 땅으로 시작")
	var wild_count: int = exterior.get_connected_map_cells().size()
	PlayerProgress.story_beat_days[OpeningTerrain.END_STEP] = GameState.total_day
	check(not exterior.is_wild() and exterior.get_connected_map_cells().size() > 2000, "끄면 기다리지 않고 바로 마을 지형")
	var village_count: int = exterior.get_connected_map_cells().size()
	world.queue_free()
	await get_tree().process_frame

	# 2) 켜면: 열리는 동안 칸이 늘기만 하고, 가까운 곳부터 마을 바닥이 되며, 끝나면 마을 지형 전체
	TerrainFade.force_for_test(true)
	world = await make_world()
	exterior = world.get_node("StoreExterior")
	var mirror = world.get_node_or_null("VillageMirror")
	PlayerProgress.story_beat_days[OpeningTerrain.END_STEP] = GameState.total_day
	exterior._update_wild()
	check(exterior.is_wild() and exterior._terrain_fading, "끝나는 순간 낯선 땅은 그대로 두고 열기를 시작한다")
	var previous: int = exterior.get_connected_map_cells().size()
	check(previous >= wild_count, "열기 시작에는 낯선 땅 칸이 모두 남아 있다(%d >= %d)" % [previous, wild_count])
	var monotonic := true
	var steps := 0
	var early_count := 0
	while exterior._terrain_fading and steps < 200:
		exterior._process_reveal(0.5)
		steps += 1
		var now_count: int = exterior.get_connected_map_cells().size()
		if now_count < previous:
			monotonic = false
		previous = now_count
		if steps == 14: early_count = now_count
	check(monotonic, "열리는 동안 걸을 수 있는 칸은 줄지 않는다")
	check(early_count > wild_count and early_count < village_count, "중간에는 낯선 땅보다 늘었고 아직 마을 전체는 아니다(%d)" % early_count)
	check(steps > 8, "한 번에 열리지 않고 여러 단계로 열린다(%d단계)" % steps)
	check(not exterior._terrain_fading and not exterior.is_wild(), "다 열리면 마을 지형")
	check(exterior.get_connected_map_cells().size() == village_count, "끝나면 칸 목록이 마을 지형 전체와 같다")
	# 열린 칸은 마을 바닥 모양을 쓴다(낯선 땅 바닥이 아니다)
	var near_kind := "?"
	if mirror != null:
		var store_rect: Rect2i = world.get_node("Floor").get_store_rect()
		near_kind = mirror._cell_kind(Vector2i(store_rect.end.x + 1, store_rect.position.y + 1))
	check(near_kind != "dirt", "끝난 뒤 바닥은 낯선 땅의 흙길이 아니다(%s)" % near_kind)
	TerrainFade.force_for_test(false)
	print("CHECK_TERRAIN_FADE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
