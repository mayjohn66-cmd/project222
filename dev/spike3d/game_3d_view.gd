extends Node
## 실제 매장(main.tscn)에 3D 도트 방식 보이는 층(StoreView3D)을 붙여서 **직접 플레이해 볼 수 있는** 시험 장면(종료하지 않음).
## 실행: Godot 에서 이 장면(dev/spike3d/game_3d_view.tscn)을 열고 F6(현재 장면 실행).
##   F8 = 마을 건물·소품 다시 만들기(art/world3d/ 의 새 그림 반영)   [ ] = 시각 1시간 앞뒤(시험용 고정)   \ = 게임 시계로 되돌림
## 게임 그대로 플레이 가능(이동 WASD/방향키, 건축 등). 건축 모드에서 가구를 놓으면 3D 에도 바로 반영된다.
## 기존 게임 파일은 수정하지 않는다(이 장면이 노드를 붙임).

var mirror: StoreView3D
var label: Label


func _ready() -> void:
	var scene: Node = load("res://scenes/shop/main.tscn").instantiate()
	add_child(scene)
	mirror = StoreView3D.new()
	scene.add_child(mirror)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	label = Label.new()
	label.position = Vector2(12, 620)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	_start_3d.call_deferred()


func _start_3d() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_update_label()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match event.keycode:
		KEY_BRACKETLEFT:
			mirror.forced_hour = fposmod((mirror.forced_hour if mirror.forced_hour >= 0.0 else mirror._current_hour()) - 1.0, 24.0)
			_update_label()
		KEY_BRACKETRIGHT:
			mirror.forced_hour = fposmod((mirror.forced_hour if mirror.forced_hour >= 0.0 else mirror._current_hour()) + 1.0, 24.0)
			_update_label()
		KEY_BACKSLASH:
			mirror.forced_hour = -1.0
			_update_label()


func _update_label() -> void:
	var hour_text: String = "게임 시계" if mirror.forced_hour < 0.0 else "%d시 고정" % int(mirror.forced_hour)
	label.text = "3D 보기 / 시각: %s ([ ] 1시간, \\ 게임 시계)" % hour_text
