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


# 원정 지역을 고르지 않았을 때 쓰는 기본 지역 (expedition_regions.csv의 region_id)
const DEFAULT_REGION_ID: String = "forest"


const STARTING_INVENTORY: Dictionary = {
	"water": 999,
	"bread": 999,
	"potion": 999,
	"iron_ore": 999,
	"mine_crystal": 999,
	"wheat": 999
}

const STARTING_MONEY: int = 500000
