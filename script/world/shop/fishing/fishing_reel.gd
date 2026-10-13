class_name FishingReel
extends RefCounted
## 낚시 당기기 규칙(화면 없음). 막대 위에서 물고기 표시가 움직이고, 플레이어는 [E]를 누르고 있으면 낚싯줄 구역이 올라가고
## 놓으면 내려간다. 물고기를 구역 안에 붙여 두면 게이지가 차고, 벗어나면 줄어든다. 가득 차면 건지고, 0이 되거나 시간이 다 되면 도망간다.
## 수치는 `data/fishing/fishing_content.json`의 `settings.reel`(희귀도별)에 있다. 희귀할수록 구역이 좁고 물고기가 빠르다.

const FALLBACK := {"bite_window": 1.5, "zone_size": 0.30, "fish_speed": 0.38, "zone_speed": 0.95, "response": 7.0, "gain": 0.30,
		"drain": 0.18, "start": 0.35, "time_limit": 14.0, "retarget_min": 0.7, "retarget_max": 1.5}
const RESULT_LANDED := "landed"
const RESULT_ESCAPED := "escaped"

var params: Dictionary = FALLBACK
var rng: RandomNumberGenerator
var fish: float = 0.5            # 물고기 위치(0~1)
var zone: float = 0.5            # 낚싯줄 구역 중심(0~1)
var zone_velocity: float = 0.0
var progress: float = 0.35       # 게이지(0~1)
var elapsed: float = 0.0
var target: float = 0.5
var retarget_in: float = 0.0
var inside: bool = true
var result: String = ""


static func params_for(rarity: String) -> Dictionary:
	var table: Dictionary = FishingData.data().get("settings", {}).get("reel", {})
	var value: Variant = table.get(rarity, table.get("common", FALLBACK))
	var merged: Dictionary = FALLBACK.duplicate()
	if value is Dictionary:
		merged.merge(value, true)
	return merged


# 입질이 오고 챔질할 수 있는 시간(초).
static func bite_window(rarity: String) -> float:
	return float(params_for(rarity)["bite_window"])


func start(rarity: String, random: RandomNumberGenerator) -> void:
	params = FishingReel.params_for(rarity)
	rng = random
	fish = 0.5
	zone = 0.5
	zone_velocity = 0.0
	progress = float(params["start"])
	elapsed = 0.0
	retarget_in = 0.0
	inside = true
	result = ""


# 한 프레임 진행. 끝나면 "landed" 또는 "escaped", 계속이면 "".
func step(delta: float, holding: bool) -> String:
	if result != "":
		return result
	retarget_in -= delta
	if retarget_in <= 0.0:
		target = rng.randf_range(0.08, 0.92)
		retarget_in = rng.randf_range(float(params["retarget_min"]), float(params["retarget_max"]))
	fish = move_toward(fish, target, float(params["fish_speed"]) * delta)
	var wanted: float = (1.0 if holding else -1.0) * float(params["zone_speed"])
	zone_velocity = lerpf(zone_velocity, wanted, clampf(float(params["response"]) * delta, 0.0, 1.0))
	var half: float = float(params["zone_size"]) * 0.5
	zone = clampf(zone + zone_velocity * delta, half, 1.0 - half)
	inside = absf(fish - zone) <= half
	progress += (float(params["gain"]) if inside else -float(params["drain"])) * delta
	progress = minf(progress, 1.0)
	elapsed += delta
	if progress >= 1.0:
		result = RESULT_LANDED
	elif progress <= 0.0 or elapsed >= float(params["time_limit"]):
		result = RESULT_ESCAPED
	return result
