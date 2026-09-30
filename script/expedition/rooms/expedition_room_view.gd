class_name ExpeditionRoomView
extends Control

signal retreat_requested
var model: ExpeditionRoomModel
var blocked: Callable
var title_label: Label
var hp_label: Label
var hp_bar: HpBar
var hint_label: Label
var attack_button: Button
var interact_button: Button
var swap_button: Button
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
	hp_bar = HpBar.new()
	hp_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(hp_bar)
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
	swap_button = _button("무기 교체 [Q]", controls)
	swap_button.pressed.connect(func():
		if _can_play(): model.swap_weapon())
	interact_button = _button("상호작용 [E]", controls)
	interact_button.pressed.connect(func():
		if _can_play(): model.interact())
	var retreat := _button("철수", controls)
	retreat.pressed.connect(func():
		if _can_play(): retreat_requested.emit())
	var help := Label.new()
	help.add_theme_font_override("font", ThemeDB.fallback_font)
	help.add_theme_color_override("font_color", Color("c9d9d1"))
	help.text = "이동 WASD / 방향키 · 기본 공격 J / Space · 무기 교체 Q · 상호작용 E"
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
	elif _can_play() and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_Q:
		model.swap_weapon()
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
		model.step(delta, direction.limit_length(), attacking)
	var weapon_text: String = model.attack_profile.display_name
	if model.loadout != null and not model.loadout.slots.is_empty():
		weapon_text = "%s(%s)" % [model.loadout.active_name(), model.attack_profile.display_name]
		if model.loadout.has_choice():
			weapon_text += " ⇄ " + model.loadout.other_name()
	swap_button.disabled = model.loadout == null or not model.loadout.has_choice() or not _can_play()
	hp_bar.set_hp(model.player_hp, model.player_max_hp)
	hp_label.text = "%s   ·   남은 적 %d" % [weapon_text, model.alive_enemies()]
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

func _draw() -> void:
	if model == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("111b20"))
	var side: float = minf(size.x - 40, size.y - 210)
	board = Rect2(Vector2((size.x - side) * 0.5, 86), Vector2(side, side))
	var cell: float = side / ExpeditionRoomSettings.GRID_SIZE
	for y in range(8):
		for x in range(8):
			var tile := Rect2(board.position + Vector2(x, y) * cell, Vector2.ONE * cell)
			draw_rect(tile, floor_color.lightened(0.035 if (x + y) % 2 == 0 else 0.0))
			draw_rect(tile, Color(0.8, 0.9, 0.8, 0.08), false)
	for obstacle in model.obstacles:
		var tile := Rect2(board.position + obstacle.position * cell, obstacle.size * cell)
		draw_rect(tile.grow(-3), Color("57675d"))
		draw_rect(tile.grow(-3), Color("89968c"), false, 2)
	var exit_rect := Rect2(_point(model.exit_position) - Vector2.ONE * cell * 0.3, Vector2.ONE * cell * 0.6)
	draw_rect(exit_rect, Color("9bd693") if model.exit_open else Color("5f676d"))
	draw_string(ThemeDB.fallback_font, exit_rect.position + Vector2(2, cell * 0.4), "↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	if not model.object_kind.is_empty() and not model.object_consumed:
		var color := Color("edd18a") if model.object_kind == "chest" else Color("81c988")
		draw_rect(Rect2(_point(model.object_position) - Vector2.ONE * cell * 0.28, Vector2.ONE * cell * 0.56), color)
		var caption: String = "채집" if model.object_kind == "gather" else ("휴식" if model.object_kind == "heal" else "상자")
		draw_string(ThemeDB.fallback_font, _point(model.object_position) + Vector2(-20, -cell * 0.4), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	for enemy in model.enemies:
		if int(enemy["hp"]) <= 0: continue
		var boss: bool = enemy["boss"]
		if float(enemy["windup"]) >= 0.0:
			var reach: float = model.settings.boss_reach if boss else model.settings.enemy_reach
			draw_circle(_point(enemy["target"]), reach * cell, Color(1.0, 0.3, 0.2, 0.25))
			draw_arc(_point(enemy["target"]), reach * cell, 0, TAU, 32, Color("f78c64"), 2)
		var at := _point(enemy["position"])
		var radius: float = cell * (0.4 if boss else 0.25)
		draw_circle(at, radius, Color("d68ab3") if boss else Color("85bad4"))
		draw_circle(at + Vector2(-radius * 0.3, -3), 2, Color("1b2534"))
		draw_circle(at + Vector2(radius * 0.3, -3), 2, Color("1b2534"))
		draw_rect(Rect2(at + Vector2(-cell * 0.4, -radius - 10), Vector2(cell * 0.8, 5)), Color("322330"))
		draw_rect(Rect2(at + Vector2(-cell * 0.4, -radius - 10), Vector2(cell * 0.8 * float(enemy["hp"]) / float(enemy["max_hp"]), 5)), Color("ea8a8a"))
	var player_at := _point(model.player_position)
	var player_texture: Texture2D
	if player_frames != null:
		var animation := "walk_up" if model.facing.y < 0 else "walk_down"
		if absf(model.facing.x) > absf(model.facing.y):
			animation = "walk_right" if model.facing.x > 0 else "walk_left"
		if player_frames.has_animation(animation):
			player_texture = player_frames.get_frame_texture(animation, int(model.elapsed * 6) % player_frames.get_frame_count(animation))
	if player_texture != null:
		draw_texture_rect(player_texture, Rect2(player_at - Vector2(cell * 0.5, cell * 0.75), Vector2.ONE * cell), false,
			Color("ffaaaa") if model.hurt_remaining > 0 else Color.WHITE)
	else:
		draw_circle(player_at, cell * model.settings.actor_radius, Color("f8e1a3"))
	draw_line(player_at, player_at + model.facing * cell * 0.5, Color("faf3d1"), 3)
	if model.attack_flash > 0:
		var angle := model.facing.angle()
		var arc := deg_to_rad(model.attack_profile.arc_degrees) * 0.5
		draw_arc(player_at, model.attack_profile.reach * cell, angle - arc, angle + arc, 24, Color("fff0b7"), 4)
	for shot in model.projectiles:
		draw_circle(_point(shot["position"]), 5, Color("f6d391"))
	for note in model.feedback:
		var note_at := _point(note["position"])
		var kind: String = str(note.get("kind", "text"))
		if kind == "hit":
			# 타격: 튀는 선 세 줄
			var life: float = clampf(float(note["life"]) / 0.35, 0.0, 1.0)
			for i in range(3):
				var angle: float = -PI * 0.5 + (i - 1) * 0.7
				draw_line(note_at + Vector2.from_angle(angle) * cell * (0.15 + 0.2 * (1.0 - life)),
					note_at + Vector2.from_angle(angle) * cell * (0.3 + 0.2 * (1.0 - life)), Color(1, 1, 0.85, life), 3)
		elif kind == "hurt":
			var hurt_life: float = clampf(float(note["life"]) / 0.45, 0.0, 1.0)
			draw_arc(note_at, cell * (0.3 + 0.35 * (1.0 - hurt_life)), 0, TAU, 24, Color(1, 0.3, 0.3, hurt_life), 4)
		else:
			draw_string(ThemeDB.fallback_font, note_at - Vector2(0, cell * 0.5), str(note["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

func _point(tile: Vector2) -> Vector2:
	return board.position + tile * board.size.x / ExpeditionRoomSettings.GRID_SIZE
