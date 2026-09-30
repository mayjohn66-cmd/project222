class_name ExpeditionRoomView
extends Control

const TILE_ART = preload("res://script/world/shop/world_tile_art.gd")
const GRID = preload("res://script/world/shared/isometric_grid.gd")
@export var tile_size := Vector2(96, 48)
var floor_texture: Texture2D = TILE_ART.GRASS
var tile_scale: float = 1.0

signal retreat_requested
var model: ExpeditionRoomModel
var blocked: Callable
var title_label: Label
var hp_label: Label
var hint_label: Label
var attack_button: Button
var interact_button: Button
var move_buttons: Dictionary = {}
var board: Rect2
var notice: String = ""
var player_frames: SpriteFrames
var floor_color := Color("253e32")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var column := VBoxContainer.new()
	add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	column.offset_left = 16
	column.offset_right = -16
	column.offset_top = 12
	column.offset_bottom = -12
	title_label = Label.new()
	title_label.add_theme_color_override("font_color", Color("f4eddb"))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title_label)
	hp_label = Label.new()
	hp_label.add_theme_color_override("font_color", Color("f4eddb"))
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hp_label)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	hint_label = Label.new()
	hint_label.add_theme_color_override("font_color", Color("f4eddb"))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint_label)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(controls)
	for entry in [["←", Vector2.LEFT], ["↑", Vector2.UP], ["↓", Vector2.DOWN], ["→", Vector2.RIGHT]]:
		var button := _button(str(entry[0]), controls)
		move_buttons[button] = entry[1]
	attack_button = _button("공격 [J / Space]", controls)
	interact_button = _button("상호작용 [E]", controls)
	interact_button.pressed.connect(func():
		if _can_play(): model.interact())
	var retreat := _button("철수", controls)
	retreat.pressed.connect(func():
		if _can_play(): retreat_requested.emit())
	var help := Label.new()
	help.add_theme_font_override("font", ThemeDB.fallback_font)
	help.add_theme_color_override("font_color", Color("c9d9d1"))
	help.text = "이동 WASD / 방향키 · 기본 공격 J / Space · 상호작용 E"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(help)
	if ResourceLoader.exists("res://art/characters/cozy_v1/player/frames.tres"):
		player_frames = load("res://art/characters/cozy_v1/player/frames.tres")
	# 버튼을 클릭하는 순간 공격하고, 누르고 있으면 기본 공격을 반복한다.
	attack_button.button_down.connect(func():
		if _can_play(): model.basic_attack())

func _button(caption: String, parent: Control) -> Button:
	var button := Button.new()
	button.add_theme_font_override("font", ThemeDB.fallback_font)
	button.add_theme_font_size_override("font_size", 18)
	button.text = caption
	button.custom_minimum_size = Vector2(42, 40)
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button

func _can_play() -> bool:
	return visible and model != null and not model.finished and (not blocked.is_valid() or not blocked.call())

func _unhandled_key_input(event: InputEvent) -> void:
	if _can_play() and event.is_action_pressed("interact"):
		model.interact()
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if not visible or model == null:
		return
	if _can_play():
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		direction += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		for button in move_buttons:
			if button.is_pressed(): direction += move_buttons[button]
		var attacking: bool = attack_button.is_pressed() or Input.is_physical_key_pressed(KEY_J) \
			or Input.is_physical_key_pressed(KEY_SPACE)
		model.step(delta, GRID.screen_direction(direction.limit_length(), tile_size), attacking)
	hp_label.text = "HP %d / %d   ·   %s   ·   남은 적 %d" % [model.player_hp,
		model.player_max_hp, model.attack_profile.display_name, model.alive_enemies()]
	var caption := model.interaction_label()
	interact_button.disabled = caption.is_empty() or not _can_play()
	interact_button.text = "%s [E]" % ("상호작용" if caption.is_empty() else caption)
	if model.interacting:
		hint_label.text = "채집 중 %d%%" % roundi(100.0 * model.interaction_progress / model.settings.gathering_seconds)
	elif not notice.is_empty():
		hint_label.text = notice
	else:
		hint_label.text = "출구가 열렸습니다" if model.exit_open else "몬스터를 처치하면 출구가 열립니다"
	queue_redraw()

func _layout_board() -> void:
	var available := Vector2(maxf(80, size.x - 80), maxf(80, size.y - 228))
	tile_scale = minf(available.x / (tile_size.x * 8), available.y / (tile_size.y * 8))
	var extent := tile_size * 8 * tile_scale
	board = Rect2(Vector2((size.x - extent.x) * 0.5, 96 + (available.y - extent.y) * 0.5), extent)

func _point(tile: Vector2) -> Vector2:
	return board.position + Vector2(board.size.x * 0.5, tile_size.y * tile_scale * 0.5) \
		+ GRID.project(tile - Vector2.ONE * 0.5, tile_size) * tile_scale

func _ground_shape(center: Vector2, radius: float, from: float = 0, to: float = TAU) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(33):
		points.append(_point(center + Vector2.from_angle(lerpf(from, to, float(i) / 32)) * radius))
	return points

func _footprint(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([_point(rect.position), _point(rect.position + Vector2(rect.size.x, 0)),
		_point(rect.end), _point(rect.position + Vector2(0, rect.size.y))])

func _draw() -> void:
	if model == null: return
	_layout_board()
	draw_rect(Rect2(Vector2.ZERO, size), Color("111b20"))
	# 상점과 동일한 타일 그림, 좌표식, 2:1 시점을 사용한다.
	var origin := _point(Vector2.ONE * 0.5)
	draw_set_transform(origin)
	for y in range(8):
		for x in range(8):
			var center := GRID.project(Vector2(x, y), tile_size) * tile_scale
			TILE_ART.draw_cell(self, center, tile_size.x * tile_scale, tile_size.y * tile_scale, floor_texture)
			var half := tile_size * tile_scale * 0.5
			draw_polyline(PackedVector2Array([center + Vector2(0, -half.y), center + Vector2(half.x, 0),
				center + Vector2(0, half.y), center + Vector2(-half.x, 0), center + Vector2(0, -half.y)]), Color(0.85, 0.9, 0.65, 0.22), 1)
	draw_set_transform(Vector2.ZERO)
	var edge := _footprint(Rect2(0, 0, 8, 8))
	var depth := Vector2(0, 12 * tile_scale)
	for pair in [[1, 2], [2, 3]]:
		draw_colored_polygon(PackedVector2Array([edge[pair[0]], edge[pair[1]],
			edge[pair[1]] + depth, edge[pair[0]] + depth]), floor_color.darkened(0.3))
	draw_polyline(PackedVector2Array([edge[0], edge[1], edge[2], edge[3], edge[0]]), Color("9d9271"), 2)
	var exit_shape := _footprint(Rect2(model.exit_position - Vector2.ONE * 0.28, Vector2.ONE * 0.56))
	draw_colored_polygon(exit_shape, Color("9bd693") if model.exit_open else Color("5f676d"))
	draw_string(ThemeDB.fallback_font, _point(model.exit_position) + Vector2(-18, -12), "출구", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	for enemy in model.enemies:
		if int(enemy["hp"]) > 0 and float(enemy["windup"]) >= 0.0:
			var reach: float = model.settings.boss_reach if enemy["boss"] else model.settings.enemy_reach
			var warning := _ground_shape(enemy["target"], reach)
			draw_colored_polygon(warning, Color(1.0, 0.3, 0.2, 0.25))
			draw_polyline(warning, Color("f78c64"), 2)
	if model.attack_flash > 0:
		var angle := model.facing.angle()
		var arc := deg_to_rad(model.attack_profile.arc_degrees) * 0.5
		draw_polyline(_ground_shape(model.player_position, model.attack_profile.reach, angle - arc, angle + arc), Color("fff0b7"), 4)
	# 발밑의 화면 Y 순서로 그려 장애물 뒤에 선 캐릭터를 가린다.
	var actors: Array[Dictionary] = []
	for obstacle in model.obstacles:
		actors.append({"kind": "obstacle", "at": obstacle.get_center(), "rect": obstacle})
	if not model.object_kind.is_empty() and not model.object_consumed:
		actors.append({"kind": "object", "at": model.object_position})
	for enemy in model.enemies:
		if int(enemy["hp"]) > 0: actors.append({"kind": "enemy", "at": enemy["position"], "enemy": enemy})
	actors.append({"kind": "player", "at": model.player_position})
	actors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _point(a["at"]).y < _point(b["at"]).y)
	for actor in actors:
		match actor["kind"]:
			"obstacle": _draw_block(actor["rect"], 30 * tile_scale, Color("8c9483"))
			"object": _draw_object()
			"enemy": _draw_enemy(actor["enemy"])
			"player": _draw_player()
	for shot in model.projectiles:
		draw_circle(_point(shot["position"]) - Vector2(0, 12 * tile_scale), 4 * tile_scale, Color("f6d391"))
	for note in model.feedback:
		draw_string(ThemeDB.fallback_font, _point(note["position"]) - Vector2(0, 52 * tile_scale),
			str(note["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

func _draw_block(rect: Rect2, height: float, color: Color) -> void:
	var base := _footprint(rect)
	var top := PackedVector2Array()
	for point in base: top.append(point - Vector2(0, height))
	for pair in [[1, 2], [2, 3]]:
		draw_colored_polygon(PackedVector2Array([base[pair[0]], base[pair[1]], top[pair[1]], top[pair[0]]]), color.darkened(0.3 if pair[0] == 1 else 0.15))
	draw_colored_polygon(top, color)
	draw_polyline(PackedVector2Array([top[0], top[1], top[2], top[3], top[0]]), color.lightened(0.2), 1)

func _draw_object() -> void:
	var color := Color("edd18a") if model.object_kind == "chest" else Color("81c988")
	_draw_block(Rect2(model.object_position - Vector2.ONE * 0.24, Vector2.ONE * 0.48), 24 * tile_scale, color)
	var caption: String = "채집" if model.object_kind == "gather" else ("휴식" if model.object_kind == "heal" else "상자")
	draw_string(ThemeDB.fallback_font, _point(model.object_position) + Vector2(-20, -36 * tile_scale), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)

func _draw_enemy(enemy: Dictionary) -> void:
	var at := _point(enemy["position"])
	var radius: float = (28 if enemy["boss"] else 18) * tile_scale
	draw_colored_polygon(_ground_shape(enemy["position"], 0.3), Color(0, 0, 0, 0.22))
	at.y -= radius * 0.8
	draw_circle(at, radius, Color("d68ab3") if enemy["boss"] else Color("85bad4"))
	for side in [-1, 1]: draw_circle(at + Vector2(side * radius * 0.3, -3), 2 * tile_scale, Color("1b2534"))
	var bar := Rect2(at + Vector2(-radius, -radius - 10), Vector2(radius * 2, 5))
	draw_rect(bar, Color("322330"))
	bar.size.x *= float(enemy["hp"]) / float(enemy["max_hp"])
	draw_rect(bar, Color("ea8a8a"))

func _draw_player() -> void:
	var at := _point(model.player_position)
	var texture: Texture2D
	var screen_facing := GRID.project(model.facing, tile_size).normalized()
	if player_frames != null:
		var animation := "walk_up" if screen_facing.y < 0 else "walk_down"
		if absf(screen_facing.x) > absf(screen_facing.y):
			animation = "walk_right" if screen_facing.x > 0 else "walk_left"
		if player_frames.has_animation(animation):
			texture = player_frames.get_frame_texture(animation, int(model.elapsed * 6) % player_frames.get_frame_count(animation))
	draw_colored_polygon(_ground_shape(model.player_position, model.settings.actor_radius), Color(0, 0, 0, 0.25))
	if texture != null:
		var sprite_size := Vector2(64, 64) * tile_scale
		draw_texture_rect(texture, Rect2(at - Vector2(sprite_size.x * 0.5, sprite_size.y * 0.85), sprite_size), false,
			Color("ffaaaa") if model.hurt_remaining > 0 else Color.WHITE)
	else: draw_circle(at - Vector2(0, 14 * tile_scale), 14 * tile_scale, Color("f8e1a3"))
	draw_line(at, _point(model.player_position + model.facing * 0.45), Color("faf3d1"), 2)
