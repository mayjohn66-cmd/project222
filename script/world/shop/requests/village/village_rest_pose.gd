class_name VillageRestPose
extends RefCounted
## 쉼터 대화 중에만 앉는다. 대화 중단/종료/장면 제거 때 자리와 기존 상태를 복원한다.
var actor: Node2D
var snapshot: Dictionary = {}
const META_KEYS := ["sitting","sit_kind","seat_direction","face_dir"]

func begin(world: Node, target: Node2D, bench: StaticBody2D) -> bool:
	if not is_instance_valid(target) or not is_instance_valid(bench): return false
	var view := world.get_node_or_null("StoreView3D") as StoreView3D
	var art := VillageSpriteArt.sprite_of(bench)
	if view == null or view.village == null or art == null: return false
	var row := VillageSpriteArt.row_for(art.art_path)
	if str(row.get("id","")) != "oak_bench": return false
	var rect: Rect2 = view.village._footprint_cell_rect(bench)
	if rect.size == Vector2.ZERO: return false
	var anchor := Vector2(float(row.anchor[0]),float(row.anchor[1]))
	# 벤치 앞에 놓인 발의 지면 점. 기존 그림의 발자국/배율과 동일하게 투영한다.
	var feet := Vector2(42,57)
	var left := INF
	var right := -INF
	for p in row.footprint:
		left = minf(left,float(p[0]))
		right = maxf(right,float(p[0]))
	var mirrored := art.scale.x < 0
	if mirrored:
		anchor.x = float(row.size[0])-anchor.x
		feet.x = float(row.size[0])-feet.x
	var scale_factor := (rect.size.x+rect.size.y)*32.0/maxf(right-left,1.0)*float(row.get("display_scale",1.0))
	var delta := (feet-anchor)*scale_factor
	var cell := rect.get_center()+Vector2(delta.x/64.0+delta.y/32.0,-delta.x/64.0+delta.y/32.0)
	actor = target
	snapshot = {"position":actor.global_position,"physics":actor.is_physics_processing(),"meta":{}}
	for key in META_KEYS:
		snapshot.meta[key] = {"exists":actor.has_meta(key),"value":actor.get_meta(key) if actor.has_meta(key) else null}
	if actor is CharacterBody2D:
		snapshot["velocity"] = actor.velocity
		actor.velocity = Vector2.ZERO
	actor.set_physics_process(false)
	actor.global_position = view.cell_to_world(cell)
	actor.set_meta("sitting",true)
	actor.set_meta("sit_kind","seat")
	actor.set_meta("seat_direction","south-west" if mirrored else "south-east")
	actor.set_meta("face_dir",Vector2(0,1) if mirrored else Vector2(1,0))
	return true

func restore() -> void:
	if is_instance_valid(actor) and not snapshot.is_empty():
		actor.global_position = snapshot.position
		for key in META_KEYS:
			var saved: Dictionary = snapshot.meta[key]
			if saved.exists: actor.set_meta(key,saved.value)
			elif actor.has_meta(key): actor.remove_meta(key)
		if actor is CharacterBody2D and snapshot.has("velocity"): actor.velocity = snapshot.velocity
		actor.set_physics_process(bool(snapshot.physics))
	actor = null
	snapshot.clear()
