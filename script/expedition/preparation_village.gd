extends Node2D
## First expedition-world step: walk along the road and leave from its far end.
const ORIGIN := Vector2(576,98)
const EXIT_CELL := Vector2(8,1)
const START_CELL := Vector2(8,10)
const EXIT_RADIUS := 54.0
var host: Node
var player: CharacterBody2D
var hud: Control
var prompt: Label
var clock_hud: Control
var camera: Camera2D
var exit_marker: Node2D
var departing := false

static func grid(point: Vector2) -> Vector2:
 return ORIGIN+Vector2((point.x-point.y)*48,(point.x+point.y)*24)

static func cell_at(point: Vector2) -> Vector2:
 var relative := point-ORIGIN
 return Vector2(relative.x/96.0+relative.y/48.0,relative.y/48.0-relative.x/96.0)

static func on_road(point: Vector2) -> bool:
 var cell := cell_at(point)
 return cell.x >= 6.65 and cell.x <= 9.35 and cell.y >= -0.3 and cell.y <= 14.3

func _ready() -> void:
 host = get_parent()
 texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 # 바닥·나무·출구 문·플레이어 몸은 3D(PreparationRoad3D)가 그린다. 이 노드는 이동·출구 판정과 글자만 맡는다.
 var view3d := PreparationRoad3D.new()
 view3d.village = self
 add_child(view3d)
 exit_marker = ExitMark.new()
 exit_marker.position = grid(EXIT_CELL)
 add_child(exit_marker)
 player = CharacterBody2D.new()
 player.name = "VillagePlayer"
 player.position = grid(START_CELL)
 add_child(player)
 camera = Camera2D.new()
 camera.position_smoothing_enabled = true
 camera.position_smoothing_speed = 6
 player.add_child(camera)
 camera.make_current()
 _setup_hud()
 _setup_clock()

func _setup_hud() -> void:
 hud = Control.new()
 hud.name = "RoadHUD"
 hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
 host.get_node("UI").add_child(hud)
 hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var title := Label.new()
 title.text = "원정으로 가는 길"
 title.position = Vector2(28,22)
 title.add_theme_font_size_override("font_size",24)
 hud.add_child(title)
 var guide := Label.new()
 guide.text = "WASD 이동 · 출구에서 E"
 guide.position = Vector2(28,58)
 guide.add_theme_font_size_override("font_size",16)
 hud.add_child(guide)
 prompt = Label.new()
 prompt.position = Vector2(260,583)
 prompt.size = Vector2(620,36)
 prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 prompt.add_theme_font_size_override("font_size",20)
 hud.add_child(prompt)
 for label in [title,guide,prompt]:
  label.mouse_filter = Control.MOUSE_FILTER_IGNORE
  label.add_theme_color_override("font_color",Color("fff0d0"))
  label.add_theme_color_override("font_outline_color",Color("3a392c"))
  label.add_theme_constant_override("outline_size",4)

func sync_phase() -> void:
 var active: bool = host.current_expedition_phase == host.ExpeditionPhase.PREP
 visible = active
 hud.visible = active
 camera.enabled = active
 host.prep_panel.hide()
 player.velocity = Vector2.ZERO
 departing = false
 if active:
  player.position = grid(START_CELL)
  camera.reset_smoothing()
  host.game_menu.show()

func _blocked() -> bool:
 return departing or host.prep_panel.visible or host.management_menu.visible or host.game_menu.menu_open or host.game_menu.settings_panel.visible or host.game_menu.save_slot_panel.visible or host.game_menu.quit_game_dialog.visible or host.game_menu.return_title_dialog.visible

func near_exit() -> bool:
 return player.position.distance_to(grid(EXIT_CELL)) <= EXIT_RADIUS

func _physics_process(delta: float) -> void:
 if not visible: return
 if _blocked():
  player.velocity = Vector2.ZERO
  return
 var movement := Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
 player.velocity = movement.normalized()*150.0
 var next := player.position+player.velocity*delta
 if on_road(next): player.position = next
 else: player.velocity = Vector2.ZERO
 prompt.text = "[E]  숲으로 원정 출발" if near_exit() else "도로를 따라 오른쪽 위 출구로 이동하세요  ↗"
 exit_marker.active = near_exit()

func _unhandled_input(event: InputEvent) -> void:
 if not visible or _blocked(): return
 if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
  try_departure()
  get_viewport().set_input_as_handled()

func try_departure() -> void:
 if not visible or _blocked() or not near_exit(): return
 departing = true
 player.velocity = Vector2.ZERO
 # Keep the real expedition service as the single authority for starting a run.
 host.start_expedition_run()
 if host.current_expedition_phase == host.ExpeditionPhase.PREP:
  departing = false
  prompt.text = "출발하지 못했습니다. 잠시 후 다시 시도해주세요."

class ExitMark extends Node2D:
 var active := false
 func _ready() -> void:
  var label := Label.new()
  label.text = "숲으로 나가는 길"
  label.position = Vector2(-85,-84)
  label.size.x = 170
  label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  label.add_theme_font_size_override("font_size",18)
  label.add_theme_color_override("font_color",Color("fff0d0"))
  label.add_theme_color_override("font_outline_color",Color("334b3d"))
  label.add_theme_constant_override("outline_size",4)
  add_child(label)

func _setup_clock() -> void:
 clock_hud = preload("res://script/expedition/village_clock_hud.gd").new()
 clock_hud.name = "ExpeditionClockHUD"
 for label_name in ["DayLabel","TimeLabel","MoneyLabel"]:
  var label := Label.new()
  label.name = label_name
  clock_hud.add_child(label)
 host.get_node("UI").add_child(clock_hud)
 clock_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 clock_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
 clock_hud.z_index = 1200
