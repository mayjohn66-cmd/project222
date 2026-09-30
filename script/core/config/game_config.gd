class_name GameConfig
extends RefCounted


# 씬 전환 경로는 한 곳에서 관리한다.
const MAIN_SCENE_PATH: String = "res://scenes/shop/main.tscn"
const TITLE_SCENE_PATH: String = "res://scenes/core/title/title_screen.tscn"
const EXPEDITION_SCENE_PATH: String = "res://scenes/expedition/expedition.tscn"


# 편의점의 기본 영업 시간
const SHOP_OPEN_HOUR: int = 9
const SHOP_CLOSE_HOUR: int = 21

# 하루 중 시간대 구분 (아침/낮/저녁/밤) 경계 시각.
# day_manager.gd의 get_period()에서 사용. 영업 시간을 바꿀 때
# 이 값들도 함께 검토할 것.
const DAY_PERIOD_START_HOUR: int = 13
const EVENING_PERIOD_START_HOUR: int = 17

const NIGHT_HOURS: Array = [
	21, 22, 23,
	0, 1, 2, 3, 4, 5, 6, 7, 8
]


# 공용 UI 씬 (여러 인벤토리/진열대 화면에서 공유)
const ITEM_CARD_SCENE: PackedScene = preload(
	"res://scenes/shared/ui/inventory/item_card.tscn"
)


# 사용자 데이터 경로
const SETTINGS_PATH: String = "user://settings.cfg"

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
const DEMAND_RARITY_WEIGHTS: Dictionary = {
	0: 100.0,
	1: 100.0,
	2: 60.0,
	3: 30.0
}

# 원정 지역을 고르지 않았을 때 쓰는 기본 지역 (expedition_regions.csv의 region_id)
const DEFAULT_REGION_ID: String = "forest"


# 시작 재고. 판매 상품은 2~3일치를 넉넉하게, 건축·제작 재료는 첫 설비 하나를 지을 만큼만 준다.
# 손님 수요는 진열대에 재고가 있는 품목을 더 자주 고른다(DEMAND_STOCKED_WEIGHT_MULT).
# 방문객 27명(규칙서의 시간 제안 기준)이면 물·빵은 하루 약 4.7개, 포션은 약 2.4개가 팔린다.
# 방문객이 8명(현재 시간 설정)이면 하루 1.4개 / 0.7개라서 더 오래 간다.
const STARTING_INVENTORY: Dictionary = {
	"water": 12,
	"bread": 12,
	"potion": 6,
	"iron_ore": 20,
	"mine_crystal": 6,
	"wheat": 6
}

const STARTING_MONEY: int = 500000
