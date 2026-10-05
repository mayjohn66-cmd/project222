class_name ActFourDecor3D
extends RefCounted
## 이미 배치된 등불·쉼터의 자리 안에 진행 표시를 더한다. 충돌/동선은 바꾸지 않는다.
static func sync(view: Node) -> void:
	var board: Node2D = VillageSettlement.find_site(view.world,CommunityRequestFlow.SETTINGS.board_path)
	if board == null: return
	var anchor: Vector2 = view.world_to_cell(board.global_position)
	_part(view,"act4_sign_post",anchor + Vector2(0.35,0.35),Vector2(0.12,0.12),1.2,0.0,Color("775331"),"a1_road_sign")
	_part(view,"act4_sign_face",anchor + Vector2(0.35,0.35),Vector2(0.75,0.12),0.35,0.8,Color("c3a16c"),"a1_road_sign")
	var rest: Node2D = VillageRestFlow.site(view.world)
	if rest == null: return
	anchor = view.world_to_cell(rest.global_position)
	_part(view,"act4_rest_rack",anchor,Vector2(0.65,0.35),0.4,0.0,Color("937047"),"a3_traveler_rest")
	_part(view,"act4_market_marker",anchor + Vector2(0.3,0.3),Vector2(0.18,0.18),0.5,0.0,Color("c5a256"),"a6_crossroad_market")
static func _part(view: Node, key: String, center: Vector2, size: Vector2, height: float, base: float, color: Color, event: String) -> void:
	if not PlayerProgress.story_beat_days.has("act4:" + event + ":last_done"):
		view._remove_item(key)
		return
	var signature := str(center)
	if view._items.has(key) and str(view._items[key]["signature"]) == signature: return
	view._remove_item(key)
	view._set_item(key,center - size * 0.5,center + size * 0.5,height,"wood",color,signature,base)
