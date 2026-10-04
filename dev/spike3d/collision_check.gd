extends Node
## 3D 발자국 충돌 점검(개발용): 건물 몸체마다 Collision3D 가 달렸는지, 옛 모양이 꺼졌는지 출력한다.
func _ready() -> void:
	var scene = load("res://dev/spike3d/village_all.tscn").instantiate()
	add_child(scene)
	for i in 40: await get_tree().process_frame
	var n3 := 0
	var bodies := 0
	for b in get_tree().root.find_children("*", "StaticBody2D", true, false):
		bodies += 1
		var poly := b.get_node_or_null("Collision3D") as CollisionPolygon2D
		if poly == null:
			continue
		n3 += 1
		var live := 0
		for c in b.get_children():
			if c != poly and (c is CollisionPolygon2D or c is CollisionShape2D) and not c.disabled:
				live += 1
		if n3 <= 6:
			print("BODY ", b.name, " poly=", poly.polygon, " old_live=", live)
	print("RESULT bodies=", bodies, " with3d=", n3)
	get_tree().quit()
