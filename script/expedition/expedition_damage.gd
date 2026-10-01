class_name ExpeditionDamage
extends RefCounted


# 원정 전투의 최종 피해 계산식(플레이어 → 적, 적 → 플레이어 모두 같은 식).
#
#   피해 = 공격력² ÷ (공격력 + 방어력)      (반올림, 최소 1)
#
# 뜻: 방어력이 공격력과 같으면 피해가 절반이 되고, 방어력이 0이면 공격력 그대로 들어간다.
#   - 방어를 아무리 쌓아도 피해가 0이나 최소값으로 뚝 떨어지지 않고 조금씩 줄어든다(면역 없음).
#   - 공격력과 방어력의 "비율"이 중요해서, 난이도가 오르며 적 공격이 함께 오르면 방어도 함께 올라야 한다.
#   - 능력치 숫자는 화면에 보이지 않으므로 이 곡선이 완만해야 한다(사용자 결정: 공개는 HP 그림뿐).
# 수치 표는 `python tools/check_equipment.py .`의 "피해 계산식 표".

static func calculate(
	attack: float,
	defense: float
) -> int:
	var atk: float = maxf(attack, 0.0)
	var def: float = maxf(defense, 0.0)

	if atk <= 0.0:
		return 1

	return maxi(1, roundi(atk * atk / (atk + def)))


# 방어로 줄어드는 피해의 비율(0.0~1.0). 표시용이 아니라 밸런스 점검용이다.
static func reduction_ratio(
	attack: float,
	defense: float
) -> float:
	var atk: float = maxf(attack, 0.0)
	var def: float = maxf(defense, 0.0)

	if atk + def <= 0.0:
		return 0.0

	return def / (atk + def)
