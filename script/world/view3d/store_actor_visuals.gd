class_name StoreActorVisuals
extends RefCounted
## 역할/직원 ID로 그림을 고른다. 전용 그림이 없거나 앉는 연출이면 기존 모델을 사용한다.


static func sprite_key(actor: Node, look_key: String) -> String:
	if bool(actor.get_meta("sitting", false)):
		return ""
	if actor.has_meta("look_key"):
		return look_key if look_key in ActorSpriteFrames.KEYS else ""
	if actor.is_in_group("worker"):
		var employee_id := str(actor.get("employee_id"))
		return employee_id if employee_id in ActorSpriteFrames.KEYS else ""
	if actor.is_in_group("customer"):
		var type_id := str(actor.get("customer_type_id"))
		if ActFourCustomers.TYPES.has(type_id):
			type_id = str(ActFourCustomers.TYPES[type_id]["source"])
		var group := CustomerTypeData.get_group_id(type_id)
		return group if group in ActorSpriteFrames.KEYS else ""
	# 주인공은 새 게임에서 고른 성별의 그림을 쓴다(art/actors/player_male·player_female).
	if look_key == "player":
		var player_key := "player_" + PlayerProgress.player_gender
		return player_key if player_key in ActorSpriteFrames.KEYS else ""
	# 연출의 현대 직장인 등은 판타지 손님으로 바꾸지 않는다.
	return look_key if look_key in ActorSpriteFrames.KEYS else ""


static func create(key: String) -> BlockyFigure:
	var frames := ActorSpriteFrames.load_set(key)
	if not frames.is_empty():
		var sprite := PixelActorFigure.new()
		sprite.sprite_key = key
		sprite.frame_set = frames
		return sprite
	return BlockyFigure.new()


## spatial 셰이더에서 실제 빛을 계산한다. 시간 색조를 원본에 중복 곱하지 않는다.
static func apply_lighting(figure: BlockyFigure, _environment: Environment, _lamps: Array, _foot: Vector3) -> void:
	if figure is PixelActorFigure: (figure as PixelActorFigure).set_light_tint(Color.WHITE)
