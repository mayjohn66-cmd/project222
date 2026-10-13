class_name EmployeeRestockAnimation
extends RefCounted
## Read the real worker job; this renderer never consumes inventory or completes work.
const WORKER = preload("res://script/actor/worker.gd")
const DIRECTIONS := ["south-east", "south-west", "north-west", "north-east"]
const EMPLOYEES := ["worker_001", "worker_002", "worker_003"]
const PHASE_ENDS := [0.15, 0.45, 0.80, 1.0]
static var _cache: Dictionary = {}

var shelf_id := 0
var elapsed := 0.0
var duration := 0.8


static func frames(employee: String, direction: String) -> Array[Dictionary]:
	var key := employee + "/" + direction
	if _cache.has(key): return _cache[key]
	var result: Array[Dictionary] = []
	if employee not in EMPLOYEES or direction not in DIRECTIONS: return result
	for index in range(4):
		var path := "res://art/actors/%s/animations/restock/%s/frame_%03d.png" % [employee, direction, index]
		if not ResourceLoader.exists(path): return []
		var texture := load(path) as Texture2D
		if texture == null: return []
		result.append({"path":path, "texture":texture, "bounds":texture.get_image().get_used_rect()})
	_cache[key] = result
	return result


static func direction_for(face: Vector2, camera_yaw: float) -> String:
	var toward := Vector2(sin(deg_to_rad(camera_yaw)), cos(deg_to_rad(camera_yaw)))
	var right := Vector2(toward.y, -toward.x)
	var sx := face.dot(right)
	var sy := face.dot(toward)
	if sy >= 0.0: return "south-east" if sx >= 0.0 else "south-west"
	return "north-east" if sx >= 0.0 else "north-west"


func sync(actor: Node2D, figure: PixelActorFigure, view: StoreView3D, delta: float) -> void:
	if not actor.is_in_group("worker") or not actor.has_method("get_effective_restock_time"):
		clear(figure)
		return
	var job_state = actor.get("state")
	if not job_state is int or job_state != WORKER.WorkerState.RESTOCK or bool(actor.get("moving")):
		clear(figure)
		return
	var shelf = actor.get("pending_shelf")
	if not is_instance_valid(shelf) or shelf.is_queued_for_deletion():
		clear(figure)
		return
	var id: int = shelf.get_instance_id()
	if shelf_id != id:
		shelf_id = id
		elapsed = 0.0
		duration = maxf(float(actor.get_effective_restock_time()), 0.001)
	elif not actor.get_tree().paused:
		elapsed += maxf(delta, 0.0)
	var target: Vector2 = view.world_to_cell(shelf.global_position)
	var visual: Node = shelf.get_node_or_null("Visual")
	if visual != null:
		target += Vector2(float(visual.get("footprint_x"))-1.0, float(visual.get("footprint_y"))-1.0)*0.5
	var face: Vector2 = target - view.world_to_cell(actor.global_position)
	var direction := direction_for(face, view._camera.global_rotation_degrees.y)
	var poses := frames(str(actor.get("employee_id")), direction)
	if poses.is_empty():
		clear(figure)
		return
	var phase := clampf(elapsed/duration, 0.0, 1.0)
	var index := 3
	for i in range(PHASE_ENDS.size()):
		if phase < PHASE_ENDS[i]:
			index = i
			break
	figure.walking = false
	figure.facing_yaw_deg = rad_to_deg(atan2(face.x, face.y))
	figure.set_work_pose(poses[index], direction)


func clear(figure: PixelActorFigure) -> void:
	shelf_id = 0
	elapsed = 0.0
	figure.set_work_pose({}, "")
