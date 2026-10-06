# 방 템플릿 데이터 규격 (초안 v0.2)

> 상위 문서: `docs/원정_규칙서.md` 3.6. 이 문서는 **ChatGPT(새 기능 코드·아트)에게 넘길 데이터 계약**의 초안이다.
> 방 크기·조작은 8×8 직접 조작 구현(ChatGPT, `script/expedition/rooms/`)에 맞춰 v0.2로 고쳤다. 아래 CSV 계약은 아직 게임에 연결되지 않은 초안이다. 예시 CSV(`room_templates_draft.csv`, `room_objects_draft.csv`)는 이 폴더에 있다.
> 태그: ✅확정 / 🟡제안 / ❓미정

## 1. 원칙
- ✅ 방 하나 = 화면 한 장, 플레이 시간 최대 1분. 클리어 = 보스 처치(보스 방은 항상 마지막).
- ✅ 전투·채집은 실시간 직접 조작.
- ✅ **방 크기 8×8타일**(사용자 결정, 구현 `ExpeditionRoomSettings.GRID_SIZE = 8`). 타일 32px이면 256×256이고, 에셋 규격서 4장의 타일 크기(32px)와 맞습니다. 이전 초안의 20×12(640×384)는 폐기했습니다.
- 🟡 방의 모양은 **템플릿(손으로 만든 배치)** 으로 정하고, 그 안의 몬스터·재료 종류는 **CSV의 참조 ID**로 정한다. 모양은 씬/타일맵, 수치와 종류는 CSV.
- 🟡 좌표는 타일 단위 정수. (0,0)이 좌상단.

## 2. 파일 3개 (난이도 표 + 방 템플릿 2개)

### 2.1 `expedition_difficulty.csv` (난이도 테이블, 실제 데이터 파일)
`data/expedition/expedition_difficulty.csv`에 이미 있다(초안 폴더가 아니라 실제 데이터). 지역과 무관하게 난이도 레벨(1~4)마다 한 줄이다.
| 열 | 뜻 |
|---|---|
| difficulty | 난이도 레벨 (1~) |
| room_count | 보스 방 포함 방 수 (레벨 1 = 6 ✅, 나머지 7/8/9 🟡) |
| monster_hp_mult / monster_atk_mult | `enemies.csv` 기본 수치에 곱함 |
| reward_amount_mult | 드롭 수량 배율 |
| rare_chance_mult | 희귀 재료 확률 배율 |

지역별 차이(재료, 몬스터, 방 템플릿)는 `region_id`로 정하고 난이도 표에는 없다. 유적의 입장 소모품(보물 지도)은 `expedition_regions.csv`에 있다.

### 2.2 `room_templates.csv` (방 한 종류 = 한 줄)
| 열 | 뜻 |
|---|---|
| template_id | 예: `forest_battle_a` |
| region_id | 이 방이 나오는 지역 |
| room_type | battle / gather / unknown / treasure / rest / boss |
| width_tiles, height_tiles | 방 크기 |
| player_x, player_y | 시작 위치 |
| exit_x, exit_y | 출구 위치 |
| exit_opens_when | always / all_enemies_dead / boss_dead / event_done |
| time_limit_sec | 설계 상한. 1분 기준(보스 90초, 휴식 30초 등은 ❓) |
| weight | 같은 지역·같은 종류 안에서 뽑힐 가중치 |

### 2.3 `room_objects.csv` (방 안 오브젝트, 여러 줄)
| 열 | 뜻 |
|---|---|
| template_id | 어느 방의 것인지 |
| object_id | 방 안에서 유일한 이름 |
| object_type | enemy_spawn / gather_point / chest / rest_point / room_reward |
| x, y | 위치(room_reward는 위치 없음, 0) |
| ref_id | enemy_spawn = `enemies.csv` ID, gather_point·chest·room_reward = `expedition_loot.csv` 테이블 ID |
| rolls | 드롭 굴림 횟수 (enemy_spawn은 0 = 몬스터 자체는 굴리지 않음) |

- 🟡 **드롭은 오브젝트에 붙는다.** 몬스터마다 굴리지 않고, 전투 방은 `room_reward` 한 줄이 방 클리어 시 굴린다(규칙서 3.2 예산과 같음). 몬스터가 늘어도 재료가 폭증하지 않는다.
- 🟡 미지 방(선택 이벤트)과 휴식은 오브젝트가 아닌 이벤트 데이터로 처리한다(규칙서 3.4). 이벤트 표 재설계는 ❓.

## 3. 실행 순서(코드가 지켜야 할 규칙)
1. 원정 시작 시 선택한 난이도의 `expedition_difficulty.room_count` 층의 지도를 만든다(폭 3, 마지막 층 = 보스).
2. 칸을 고르면 그 칸의 `room_type`과 지역으로 `room_templates`에서 가중치 추첨해 방을 연다.
3. `room_objects`대로 배치하고 몬스터 수치에 난이도 배율을 곱한다.
4. `exit_opens_when` 조건이 되면 출구가 열린다. 채집·보물·휴식은 자유 퇴장.
5. 보스 처치 = 클리어 → 결과 화면. 언제든 철수 가능(획득품 유지).

## 4. 기존 데이터와의 연결
- `expedition_loot.csv`: 이미 들어 있는 `forest_gather`, `forest_enemy`, `forest_treasure`, `forest_boss` 등을 그대로 참조한다.
- `enemies.csv`: `loot_table` 열은 몬스터 단위 드롭이 사라지면 사용하지 않게 된다(❓ 제거 시점).
- `expedition_events.csv`, `expedition_map_nodes.csv`: 미지 방 이벤트와 칸 종류 가중치로 남긴다. 이 표의 gather/battle/treasure 이벤트 행은 방 템플릿으로 대체된다.
- `expedition_gathering_rules.csv`: 도구 유무에 따른 성공률·보너스는 gather_point의 `ref_id`(=드롭 테이블 ID)로 계속 조회한다. 실시간 채집(시간 걸리는 상호작용)과의 결합은 ❓.

## 5. 아트·코드 담당에게 요청할 것 (안)
- 아트: 32px 타일셋(지역별), gather_point/chest/rest_point/출구 오브젝트, 몬스터 스프라이트.
- 코드: 방 씬 로더(템플릿+오브젝트 CSV → 방 생성), 플레이어 이동·기본 공격(스킬·회피 없음, 장비가 공격 방식을 바꿈), 몬스터 AI(예고 동작 0.65초), 기존 지도 노드와 연결. 새 기능이므로 `expedition.gd`에 덧붙이지 않고 `script/expedition/` 아래 새 컨트롤러로 만든다.

## 6. 오픈 이슈
1. (해결) 방 8×8 확정. 남은 것: 지역별 방 배치 템플릿과 장애물 변형을 CSV로 뺄지 지금처럼 코드로 둘지
2. 방 시간 상한(보스 90초, 휴식 30초 등)과 방 종류별 플레이 시간
3. 채집이 시간이 걸리는 실시간 상호작용일 때 도구·성공률 규칙 적용 방식
4. `enemies.csv` `loot_table` 열 폐지 시점
5. 미지 방 이벤트 표의 새 형식
6. 몬스터 체력 배율과 공격 배율 분리 여부
