class_name ExpeditionPixelPlayer
extends PixelActorFigure
## Original eight-direction movement plus a one-shot basic sword animation.
var attack_direction := ""
var weapon_kind := ""

func set_weapon(kind: String) -> void:
	# 관절 모델의 손목에 무기를 붙이는 기본 구현은 도트 인물에 사용하지 않는다.
	if kind != weapon_kind: cancel_attack()
	weapon_kind = kind

func play_attack(duration: float, ranged: bool = false, _arc_degrees: float = 80.0) -> void:
	cancel_attack()
	# Projectile equipment keeps its existing projectile feedback, with no sword.
	if ranged: return
	attack_direction = ActorSpriteFrames.direction_for(facing_yaw_deg, _camera_yaw)
	_atk_dur = maxf(0.001, duration)
	_atk_t = 0.0
	set_work_pose(ExpeditionPlayerAttackArt.pose(sprite_key,attack_direction,0.0),attack_direction)


func cancel_attack() -> void:
	_atk_t = -1.0
	attack_direction = ""
	set_work_pose({}, "")

func animate(delta: float) -> void:
	if _atk_t >= 0.0:
		_atk_t += maxf(delta,0.0)
		if _atk_t >= _atk_dur:
			cancel_attack()
		else:
			set_work_pose(ExpeditionPlayerAttackArt.pose(sprite_key,attack_direction,_atk_t/_atk_dur),attack_direction)
	super.animate(delta)
	if _hurt_t >= 0.0:
		_hurt_t += delta
		if _hurt_t >= _hurt_dur: _hurt_t = -1.0

func set_tint(color: Color) -> void:
	set_light_tint(color)
