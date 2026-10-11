class_name ExpeditionPixelPlayer
extends PixelActorFigure
## 기존 남녀 8방향 그림을 재사용한다. 별도 공격 그림은 후속이며 공격 표시/투사체는 무대가 그린다.

func set_weapon(_kind: String) -> void:
	# 관절 모델의 손목에 무기를 붙이는 기본 구현은 도트 인물에 사용하지 않는다.
	pass

func play_attack(_duration: float, _ranged: bool = false, _arc_degrees: float = 80.0) -> void:
	pass

func animate(delta: float) -> void:
	super.animate(delta)
	if _hurt_t >= 0.0:
		_hurt_t += delta
		if _hurt_t >= _hurt_dur: _hurt_t = -1.0

func set_tint(color: Color) -> void:
	set_light_tint(color)
