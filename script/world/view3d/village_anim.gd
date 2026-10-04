class_name VillageAnim
extends RefCounted
## 마을 3D 부품 애니메이션. 건물·소품 빌더가 돌려주는 anim 목록의 각 항목이 어떻게 움직일지(mode)를 한곳에서 정한다.
## 항목: {mesh, specs, pos, mode, speed, axis, phase, amp, rise, drift}
##   rotate  : axis 둘레로 speed(rad/s) 돈다(풍차 날개)
##   flicker : 위로 길쭉했다 납작했다 일렁이고 밝기가 흔들린다(불꽃). 부품의 바닥이 pos 에 오도록 만든다
##   sway    : axis 둘레로 ±amp(rad) 흔들린다(허수아비). 흔들림의 중심(받침)이 pos 에 오도록 만든다
##   bob     : 위아래로 ±amp 출렁인다(분수 물)
##   drift   : speed(1/s)마다 한 번, pos 에서 rise 만큼 올라가며 drift 만큼 옆으로 흘러가고, 커졌다가 작아진다(연기·불똥)
##   arc     : drift 방향으로 나가며 amp 높이 포물선을 그리고 떨어진다(분수 물방울)
##   pulse   : 움직이지 않고 빛 세기(emit_strength)만 amp 만큼 깜빡인다(등불)

static func apply(node: Node3D, mats: Array, an: Dictionary, t: float, dt: float) -> void:
	var mode: String = str(an.get("mode", "rotate"))
	var speed: float = float(an.get("speed", 1.0))
	var phase: float = float(an.get("phase", 0.0))
	var amp: float = float(an.get("amp", 0.1))
	var pos: Vector3 = an.get("pos", Vector3.ZERO)

	match mode:
		"rotate":
			node.rotate(an.get("axis", Vector3(0.0, 0.0, 1.0)) as Vector3, speed * dt)
		"flicker":
			var s: float = 1.0 + amp * (0.6 * sin(t * speed + phase) + 0.4 * sin(t * speed * 2.7 + phase * 1.7))
			var w: float = 1.0 + (1.0 - s) * 0.5
			node.scale = Vector3(w, s, w)
			_emit(mats, an, 1.0 + 0.25 * sin(t * speed * 1.9 + phase))
		"sway":
			var axis: Vector3 = (an.get("axis", Vector3(0.0, 0.0, 1.0)) as Vector3).normalized()
			node.basis = Basis(axis, amp * sin(t * speed + phase))
		"bob":
			node.position = pos + Vector3(0.0, amp * sin(t * speed + phase), 0.0)
		"drift":
			var f: float = fposmod(t * speed + phase, 1.0)
			var sc: float = 0.5 + 0.9 * minf(f / 0.6, 1.0) if f < 0.6 else 1.4 - (f - 0.6) / 0.4 * 1.2
			node.position = pos + Vector3(0.0, float(an.get("rise", 0.8)) * f, 0.0) + (an.get("drift", Vector3.ZERO) as Vector3) * f
			node.scale = Vector3.ONE * maxf(sc, 0.15)
		"arc":
			var f2: float = fposmod(t * speed + phase, 1.0)
			node.position = pos + (an.get("drift", Vector3.ZERO) as Vector3) * f2 + Vector3(0.0, amp * sin(PI * f2) - 0.15 * f2, 0.0)
		"pulse":
			_emit(mats, an, 1.0 + amp * (0.6 * sin(t * speed + phase) + 0.4 * sin(t * speed * 2.3 + phase * 1.3)))


# 재질의 emit_strength 를 기준값 × k 로 바꾼다(기준값은 항목의 emit_base, 없으면 1)
static func _emit(mats: Array, an: Dictionary, k: float) -> void:
	var base: float = float(an.get("emit_base", 1.0))

	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("emit_strength", base * k)
