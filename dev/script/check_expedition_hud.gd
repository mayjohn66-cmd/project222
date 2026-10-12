extends Node
const SETTINGS := preload("res://scenes/expedition/rooms/default_room_settings.tres")
var checks := 0
var failures := 0
var view: ExpeditionRoomView

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	# 실제 창 크기와 같은 픽셀 좌표로 검사한다. 게임의 기본 확대 설정은 수정하지 않는다.
	get_window().content_scale_size = Vector2i.ZERO
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(2))
	run.call_deferred()

func frames(count := 3) -> void:
	for i in count: await get_tree().process_frame

func room(method := ExpeditionAttackProfile.Method.MELEE) -> ExpeditionRoomModel:
	var result := ExpeditionRoomModel.new()
	var enemy := EnemyData.get_enemy("field_slime").duplicate(true)
	enemy.id = "field_slime"
	var attack := ExpeditionAttackProfile.new()
	attack.method = method
	attack.reach = 3.0
	result.setup(SETTINGS, attack, 50, 100, 12, 3, enemy, 1, false, "")
	result.obstacles.clear()
	result.player_position = Vector2(2.5, 3.0)
	result.facing = Vector2.UP
	result.enemies[0].position = Vector2(2.5, 2.2)
	result.enemies[1].position = Vector2(6.0, 6.0)
	return result

func damage_notes(model: ExpeditionRoomModel) -> Array[Dictionary]:
	return model.feedback.filter(func(note): return str(note.get("kind", "")) == "damage")

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://" + name + ".png")

func check_text(node: Node) -> void:
	if node is Label or node is Button:
		var content: String = node.text
		check(not content.contains("[E]") and not content.contains("[Q]") and not content.contains("[J") and not content.contains("WASD") and not content.contains("Space"), "no keyboard instructions: " + content)
	for child in node.get_children(): check_text(child)

func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/art/damage_digit_assets.json"))
	check(manifest.assets.size() == 10, "ten individual digit drawings")
	for row in manifest.assets:
		var texture := ExpeditionDamageDigits.textures()[int(row.id)]
		check(texture != null and texture.get_size() == Vector2(12,16), "native digit size " + row.id)
		check(FileAccess.get_sha256(row.path) == row.sha256, "installed digit SHA " + row.id)
		check(FileAccess.get_sha256("res://" + row.source) == row.source_sha256, "received digit unchanged " + row.id)
		var image := texture.get_image()
		var binary := true
		for y in image.get_height():
			for x in image.get_width():
				var alpha := image.get_pixel(x,y).a
				if alpha != 0 and alpha != 1: binary = false
		check(binary, "crisp alpha " + row.id)
	check(ExpeditionDamageDigits.digits(1209) == [1,2,0,9], "multi-digit amount uses separate textures in order")
	check(ExpeditionDamageDigits.digits(0) == [0], "zero glyph supported")
	for method in [ExpeditionAttackProfile.Method.MELEE, ExpeditionAttackProfile.Method.PROJECTILE]:
		var model := room(method)
		var before: int = model.enemies[0].hp
		model.basic_attack()
		if method == ExpeditionAttackProfile.Method.PROJECTILE: model.step(0.1, Vector2.ZERO, false)
		var notes := damage_notes(model)
		check(notes.size() == 1 and notes[0].amount == before - int(model.enemies[0].hp), "actual melee/projectile HP loss is shown")
		model.step(1.0, Vector2.ZERO, false)
		check(damage_notes(model).is_empty(), "expired damage is removed")
	var missed := room()
	missed.facing = Vector2.DOWN
	missed.basic_attack()
	check(damage_notes(missed).is_empty(), "miss produces no damage number")
	var lethal := room()
	lethal.enemies[0].hp = 3
	lethal.player_attack = 999
	lethal.basic_attack()
	check(damage_notes(lethal).size() == 1 and damage_notes(lethal)[0].amount == 3, "lethal hit reports actual remaining HP")
	var multiple := room()
	multiple.attack_profile.max_targets = 2
	multiple.enemies[1].position = Vector2(2.8, 2.2)
	multiple.basic_attack()
	check(damage_notes(multiple).size() == 2, "each struck enemy gets its own number")
	view = load("res://scenes/expedition/rooms/expedition_room.tscn").instantiate()
	add_child(view)
	await frames()
	view.set_physics_process(false)
	view.stage.set_process(false)
	for screen_size in [Vector2(1152,648),Vector2(593,523)]:
		view.size = screen_size
		view.model = room()
		view.title_label.text = "숲 · 전투"
		view._physics_process(0)
		view.stage.rebuild(view.model,"forest")
		await frames()
		view.hud.layout()
		view.stage._layout()
		view.stage._sync(view.model,0)
		var hp_rect := view.hp_bar.get_global_rect()
		check(hp_rect.position.x < 30 and hp_rect.position.y > screen_size.y - 90, "HP lower left at " + str(screen_size))
		check(is_equal_approx(view.hp_bar.ratio,0.5), "HP fill still reflects actual health")
		for button in view.hud.buttons:
			check(not button.is_visible_in_tree(), "no bottom action button: " + button.text)
		check(not view.hp_label.is_visible_in_tree(), "no weapon/enemy footer text")
		check(not view.hint_label.is_visible_in_tree(), "no idle guidance text")
		var retreat_count := [0]
		var on_retreat := func(): retreat_count[0] += 1
		view.retreat_requested.connect(on_retreat)
		var retreat_key := InputEventKey.new()
		retreat_key.pressed = true
		retreat_key.physical_keycode = KEY_R
		view._unhandled_key_input(retreat_key)
		check(retreat_count[0] == 1, "keyboard withdrawal remains available")
		view.blocked = func(): return true
		view._unhandled_key_input(retreat_key)
		check(retreat_count[0] == 1, "menu blocks withdrawal key")
		view.blocked = Callable()
		view.retreat_requested.disconnect(on_retreat)
		check_text(view.hud)
		view.model.basic_attack()
		view.queue_redraw()
		await capture("damage_hud_%d" % int(screen_size.x))
		view.model.finished = true
		view.model.step(1.0, Vector2.ZERO, false)
		check(damage_notes(view.model).is_empty(), "finished room also ages damage visuals")
	view.queue_free()
	await frames()
	print("[원정 HUD·피해 숫자] 검사 ", checks, " / 실패 ", failures)
	get_tree().quit(1 if failures > 0 else 0)
