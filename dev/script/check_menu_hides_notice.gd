extends Node
## 관리 메뉴를 열면 안내 패널(튜토리얼 목표)이 숨고, 닫은 뒤 다시 보이는지 확인한다.

var checks := 0
var failures := 0

func expect(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", name)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in 10: await get_tree().process_frame
	var director = world.get_node("TutorialDirector")
	var mm = world.find_child("ManagementMenu", true, false)
	director.panel.root.show()
	expect(director.panel.root.visible, "패널을 보이게 둔다")
	mm.open_menu(0)
	expect(not director.panel.root.visible, "메뉴를 열면 안내 패널이 숨는다")
	mm.close_menu()
	print("CHECK_MENU_HIDES_NOTICE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(failures)
