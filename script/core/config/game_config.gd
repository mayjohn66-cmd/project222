class_name GameConfig
extends RefCounted


# 씬 전환 경로는 한 곳에서 관리한다.
const MAIN_SCENE_PATH: String = "res://scenes/shop/main.tscn"
const TITLE_SCENE_PATH: String = "res://scenes/core/title/title_screen.tscn"
const EXPEDITION_SCENE_PATH: String = "res://scenes/expedition/expedition.tscn"


# 하루는 06:00(아침 시작)에 시작해 다음 날 06:00에 정산한다.
# 영업 중에는 24시간 시간이 흐르고, 06:00에 시간이 멈춘 상태에서 정비(건축·근무표·저장)한다.
const DAY_START_HOUR: int = 6

# 원정 안에서는 상점 시간이 이 배율로 느리게 흐른다(0.5 = 절반 속도).
# 원정에서 돌아오면 자리를 비운 게임 시간만큼 상점을 한꺼번에 정산한다(ShopOfflineSimulator).
const EXPEDITION_TIME_SCALE: float = 0.5

# 심야 비밀 상인: 밤(심야 시간대)이 시작될 때 이 확률로 찾아와 06:00까지 머문다.
# 첫 원정을 다녀온 뒤부터 나올 수 있다. 판매 목록은 data/shop/catalogs/secret_merchant.csv.
const SECRET_MERCHANT_NIGHT_CHANCE: float = 0.10

# 하루 4등분 시간대 시작 시각(각 6시간): 아침 6~12 / 낮 12~18 / 저녁 18~24 / 심야 0~6.
# EmployeeData.get_period_at_hour()와 DayManager.get_period()가 사용한다.
const MORNING_PERIOD_START_HOUR: int = 6
const DAY_PERIOD_START_HOUR: int = 12
const EVENING_PERIOD_START_HOUR: int = 18
const NIGHT_PERIOD_START_HOUR: int = 0


# 공용 UI 씬 (여러 인벤토리/진열대 화면에서 공유)
const ITEM_CARD_SCENE: PackedScene = preload(
	"res://scenes/shared/ui/inventory/item_card.tscn"
)


# 사용자 데이터 경로
const SETTINGS_PATH: String = "user://settings.cfg"

# 설정에서 고를 수 있는 게임 속도 배율(상점 화면에서만 적용, 원정은 항상 1배).
const GAME_SPEED_OPTIONS: Array = [1.0, 2.0, 3.0, 4.0]

const SAVE_SLOT_PATHS: Array = [
	"user://save_slot_1.dat",
	"user://save_slot_2.dat"
]

const SAVE_PATH: String = "user://save_game.dat"
const SAVE_TEST_PATH: String = "user://save_test.dat"

# 마을 지도 편집 결과를 저장하는 경로
const VILLAGE_LAYOUT_USER_PATH: String = "user://village_map_layout.json"


# 개발용 출력(DebugLog.write)을 켜고 끈다. 배포 빌드에서는 값과 상관없이 꺼진다.
const DEBUG_LOG_ENABLED: bool = true


# 전투 파트를 새로 만들 때까지, 전투는 승리한 것으로 보고 보상 단계로 바로 넘어간다.
# false로 바꾸면 예전의 1초 단위 자동 전투가 돌아간다.
const EXPEDITION_AUTO_WIN_BATTLES: bool = true

# 손님 수요: 카테고리를 고른 뒤 그 안에서 품목을 고를 때의 가중치.
# 판매 품목이 늘어도 손님의 수요가 재고 없는 품목으로 흩어지지 않게 하려는 값이다.
#  - 지금 진열대에 재고가 있는 품목은 이 배수만큼 더 자주 원해진다(재고 없는 품목도 원할 수 있음).
#  - 희귀한 재료일수록 덜 원해진다(희귀도 0~3 → 가중치).
const DEMAND_STOCKED_WEIGHT_MULT: float = 10.0
# 손님 유형이 특정 품목(target_type=item)을 원하는 행의 무게: 재고가 있으면 이 배수만 곱한다.
# 유형별 취향(무게)이 재고에 묻히지 않게 카테고리 안 배수보다 작게 둔다.
const DEMAND_STOCKED_ENTRY_WEIGHT_MULT: float = 2.0
const DEMAND_RARITY_WEIGHTS: Dictionary = {
	0: 100.0,
	1: 100.0,
	2: 60.0,
	3: 30.0
}

# 원정 지역을 고르지 않았을 때 쓰는 기본 지역 (expedition_regions.csv의 region_id)
const DEFAULT_REGION_ID: String = "forest"


# 가게와 함께 옮겨 온 식품. 현지 장비/원재료는 거래와 원정에서 얻는다.
const STARTING_INVENTORY: Dictionary = {"water": 6, "bread": 8}
const STARTING_MONEY: int = 0
