class_name ExpeditionRoomView
extends Control

const GRID = preload("res://script/world/shared/isometric_grid.gd")
@export var tile_size := Vector2(96, 48)
var tile_scale: float = 1.0

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
var region_id: String = "forest"  # 3D 무대의 지역별 꾸밈(초원·계곡 포함)
var use_3d: bool = true  # 던전 방을 3D 로 그린다(항상 3D)
var stage: ExpeditionStage3D
var weather_overlay: ExpeditionWeatherOverlay
var progress_guide: ExpeditionRoomProgressGuide
var ground_overlay := Color.TRANSPARENT
var hud: ExpeditionRoomHud

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hud = ExpeditionRoomHud.new()
	add_child(hud)
	hud.build(self)
	# 3D 무대: 이 뷰의 뒤에 깔려 바닥·벽·장애물·적·플레이어를 그린다. 체력 막대·글자·공격 표시는 이 뷰가 그 위에 2D 로 그린다.
	stage = ExpeditionStage3D.new()
	stage.view = self
	add_child(stage)
	move_child(stage, 0)
	# 버튼을 클릭하는 순간 공격하고, 누르고 있으면 기본 공격을 반복한다.
	attack_button.button_down.connect(func():
		if _can_play(): model.basic_attack())
	weather_overlay = ExpeditionWeatherOverlay.new()
	add_child(weather_overlay)
	move_child(hud, get_child_count() - 1)

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
	elif _can_play() and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_J, KEY_SPACE]:
			model.basic_attack()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_R:
			retreat_requested.emit()
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
	elif model.finished:
		model.step(delta, Vector2.ZERO, false)
	var weapon_text: String = model.attack_profile.display_name
	if model.loadout != null and not model.loadout.slots.is_empty():
		weapon_text = "%s(%s)" % [model.loadout.active_name(), model.attack_profile.display_name]
		if model.loadout.has_choice():
			weapon_text += " ⇄ " + model.loadout.other_name()
	swap_button.disabled = model.loadout == null or not model.loadout.has_choice() or not _can_play()
	attack_button.disabled = not _can_play()
	hp_bar.set_hp(model.player_hp, model.player_max_hp)
	hp_label.text = "%s   ·   남은 적 %d" % [weapon_text, model.alive_enemies()]
	var caption := model.interaction_label()
	interact_button.disabled = caption.is_empty() or not _can_play()
	interact_button.text = "상호작용" if caption.is_empty() else caption
	if model.interacting:
		hint_label.text = "채집 중 %d%%" % roundi(100.0 * model.interaction_progress / model.interaction_seconds())
	elif not notice.is_empty():
		hint_label.text = notice
	else:
		hint_label.text = "출구가 열렸습니다" if model.exit_open else "몬스터를 처치하면 출구가 열립니다"
	if progress_guide != null:
		hint_label.text = progress_guide.hint(hint_label.text)
	var unsafe_exit: bool = not model.exit_open and model.player_position.distance_to(model.exit_position) <= model.settings.interaction_reach
	if unsafe_exit: hint_label.text = UiText.t("expedition.room.unsafe_path")
	hint_label.visible = model.interacting or not notice.is_empty() or not caption.is_empty() or unsafe_exit
	hud.layout()
	queue_redraw()

func _stage_on() -> bool:
	return use_3d and stage != null and stage.is_inside_tree() and stage.active


func _layout_board() -> void:
	var available := Vector2(maxf(80, size.x - 80), maxf(80, size.y - 228))
	tile_scale = minf(available.x / (tile_size.x * 8), available.y / (tile_size.y * 8))
	var extent := tile_size * 8 * tile_scale
	board = Rect2(Vector2((size.x - extent.x) * 0.5, 96 + (available.y - extent.y) * 0.5), extent)

func _point(tile: Vector2) -> Vector2:
	if _stage_on():
		return stage.project(tile, 0.0)
	return board.position + Vector2(board.size.x * 0.5, tile_size.y * tile_scale * 0.5) \
		+ GRID.project(tile - Vector2.ONE * 0.5, tile_size) * tile_scale

func _ground_shape(center: Vector2, radius: float, from: float = 0, to: float = TAU) -> PackedVector2Array:
	var points := PackedVector2Array()
	# 면의 삼각분할에는 중복 끝점을 넣지 않고, 공격 호에는 끝점까지 넣는다.
	for i in range(32 if is_equal_approx(to - from, TAU) else 33):
		points.append(_point(center + Vector2.from_angle(lerpf(from, to, float(i) / 32)) * radius))
	return points

func _footprint(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([_point(rect.position), _point(rect.position + Vector2(rect.size.x, 0)),
		_point(rect.end), _point(rect.position + Vector2(0, rect.size.y))])

func _draw() -> void:
	if model == null: return
	if stage != null:
		stage.active = use_3d
		stage.visible = use_3d
	_layout_board()
	for enemy in model.enemies:
		if int(enemy["hp"]) > 0 and float(enemy["windup"]) >= 0.0:
			var reach: float = model.settings.boss_reach if enemy["boss"] else model.settings.enemy_reach
			var warning := _ground_shape(enemy["target"], reach)
			draw_colored_polygon(warning, Color(1.0, 0.3, 0.2, 0.25))
			warning.append(warning[0])
			draw_polyline(warning, Color("f78c64"), 2)
	if model.attack_flash > 0:
		var angle := model.facing.angle()
		var arc := deg_to_rad(model.attack_profile.arc_degrees) * 0.5
		draw_polyline(_ground_shape(model.player_position, model.attack_profile.reach, angle - arc, angle + arc), Color("fff0b7"), 4)
	# 몸·장애물·바닥은 3D 무대가 그린다. 여기서는 채집 이름표와 적 체력 막대·이름만 위에 얹는다.
	if not model.object_kind.is_empty() and not model.object_consumed:
		if model.gathering_sites.is_empty():
			_draw_object({})
		else:
			for site in model.gathering_sites:
				_draw_object(site)
	for enemy in model.enemies:
		if int(enemy["hp"]) > 0: _draw_enemy(enemy)
	for note in model.feedback:
		var cell: float = tile_size.x * tile_scale
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
		elif kind == "damage":
			var damage_at := stage.project(note["position"], float(note.get("height", 0.9)))
			ExpeditionDamageDigits.draw_number(self, damage_at, int(note["amount"]), float(note["life"]))
		else:
			draw_string(ThemeDB.fallback_font, note_at - Vector2(0, cell * 0.5), str(note["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	# 피격: 화면 가장자리가 붉게 번쩍인다(무적 시간 동안 서서히 사라짐). 네 변을 대각선으로 맞닿는 사다리꼴 그라데이션으로 그려
	# 모서리에서 겹쳐 더 진해지지 않게 한다(바깥 = 붉음, 안쪽 = 투명).
	if model.hurt_remaining > 0.0:
		var hv: float = clampf(model.hurt_remaining / maxf(0.01, model.settings.hurt_grace), 0.0, 1.0)
		var e: float = 110.0
		var outer := Color(0.9, 0.1, 0.1, 0.34 * hv)
		var inner := Color(0.9, 0.1, 0.1, 0.0)
		var w: float = size.x
		var h2: float = size.y
		var quads: Array = [
			[Vector2(0, 0), Vector2(w, 0), Vector2(w - e, e), Vector2(e, e)],
			[Vector2(w, 0), Vector2(w, h2), Vector2(w - e, h2 - e), Vector2(w - e, e)],
			[Vector2(w, h2), Vector2(0, h2), Vector2(e, h2 - e), Vector2(w - e, h2 - e)],
			[Vector2(0, h2), Vector2(0, 0), Vector2(e, e), Vector2(e, h2 - e)],
		]

		for q in quads:
			draw_polygon(PackedVector2Array([q[0], q[1], q[2], q[3]]), PackedColorArray([outer, outer, inner, inner]))


func _draw_object(site: Dictionary = {}) -> void:
	var at := model.object_position if site.is_empty() else Vector2(float(site["x"]),float(site["y"]))
	var caption: String = "채집" if model.object_kind == "gather" else ("휴식" if model.object_kind == "heal" else "상자")
	if not site.is_empty(): caption = str(site["label"])
	draw_string(ThemeDB.fallback_font, _point(at) + Vector2(-20, -36 * tile_scale), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)

func _draw_enemy(enemy: Dictionary) -> void:
	var at := _point(enemy["position"])
	var radius: float = (28 if enemy["boss"] else 18) * tile_scale
	# 3D 로 그려진 몸 위에, 체력 막대와 이름만 2D 로(머리 위 높이를 3D 에서 투영)
	at = stage.project(enemy["position"], 1.15 if enemy["boss"] else 0.7)
	at.y += radius * 0.8
	var bar := Rect2(at + Vector2(-radius, -radius - 10), Vector2(radius * 2, 5))
	draw_rect(bar, Color("322330"))
	bar.size.x *= float(enemy["hp"]) / float(enemy["max_hp"])
	draw_rect(bar, Color("ea8a8a"))
	draw_string(ThemeDB.fallback_font, at + Vector2(-48, -radius - 17), str(enemy["name"]), HORIZONTAL_ALIGNMENT_CENTER, 96, 12, Color("f4eddb"))
