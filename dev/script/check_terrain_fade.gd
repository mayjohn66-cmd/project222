extends Node
## 낯선 땅 → 마을 지형 전환 암전 검사: 어두워진 뒤에 지형이 바뀌고, 다시 밝아지며, 끄면 바로 바뀐다.
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


func overlay() -> Node:
	return get_tree().root.get_node_or_null("TerrainFade")


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	# 1) 암전을 끄면 바로 바뀐다(시험 기본과 같은 동작)
	TerrainFade.force_for_test(false)
	var world = await make_world()
	var exterior = world.get_node("StoreExterior")
	check(exterior.is_wild(), "새 게임은 낯선 땅으로 시작")
	PlayerProgress.story_beat_days[OpeningTerrain.END_STEP] = GameState.total_day
	check(not exterior.is_wild() and overlay() == null, "암전을 끄면 기다리지 않고 바로 마을 지형")
	world.queue_free()
	await get_tree().process_frame

	# 2) 암전을 켜면: 끝나는 순간 지형은 그대로, 화면이 어두워진 뒤에 바뀌고, 다시 밝아진다
	TerrainFade.force_for_test(true)
	world = await make_world()
	exterior = world.get_node("StoreExterior")
	PlayerProgress.story_beat_days[OpeningTerrain.END_STEP] = GameState.total_day
	exterior._update_wild()
	check(exterior.is_wild() and overlay() != null, "끝나는 순간 지형은 그대로 두고 암전을 시작한다")
	var cover: ColorRect = overlay().get_child(0)
	await get_tree().create_timer(TerrainFade.FADE_OUT * 0.5).timeout
	check(exterior.is_wild() and cover.modulate.a > 0.0 and cover.modulate.a < 1.0, "어두워지는 동안에는 아직 낯선 땅")
	check(exterior.get_connected_map_cells().size() < 1000, "어두워지는 동안 지형 질의도 낯선 땅 그대로")
	await get_tree().create_timer(TerrainFade.FADE_OUT * 0.5 + TerrainFade.HOLD * 0.6).timeout
	check(not exterior.is_wild() and cover.modulate.a >= 0.99, "완전히 어두워진 뒤에 마을 지형으로 바뀐다")
	check(exterior.get_connected_map_cells().size() > 2000, "바뀐 지형은 마을 지형 칸 목록")
	await get_tree().create_timer(TerrainFade.HOLD + TerrainFade.FADE_IN + 0.4).timeout
	check(overlay() == null, "밝아진 뒤 암전 장치는 사라진다")
	check(not exterior.is_wild(), "밝아진 뒤에도 마을 지형")
	# 같은 세션에서 다시 부르면 중복 암전이 생기지 않는다
	exterior._update_wild()
	check(overlay() == null, "이미 마을 지형이면 암전하지 않는다")
	TerrainFade.force_for_test(false)
	print("CHECK_TERRAIN_FADE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
