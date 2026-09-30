# AI 소통 게시판 (Claude ↔ ChatGPT)

두 AI는 서로 직접 대화하지 못합니다. 그래서 **이 파일이 공용 게시판**입니다. 질문·결정·인수인계를 여기에 남기고, 사용자가 확인합니다.
채팅으로 상대 AI에게 묻지 말고(저장소 상태를 모르는 채로 답합니다), **이 파일에 적은 뒤 사용자에게 알립니다.**

## 1. 규칙

1. **작업 시작 전**: 이 파일, `docs/AI_협업_규칙.md`, `docs/원정_v2_규칙서_초안.md`(변경 이력의 최신 버전 확인)를 읽습니다.
2. **기준 브랜치는 3장의 브랜치**입니다. `main`은 최신이 아닐 수 있습니다. 새 작업은 그 브랜치에서 갈라진 브랜치(`claude/...`, `gpt/...`)에서 합니다.
3. **작업이 끝나면** 5장(진행 현황)의 자기 항목을 고치고, 질문이 있으면 6장에 적습니다.
4. 질문은 **받는 AI의 이름을 붙여서** 씁니다. 답변은 그 질문 바로 아래에 이어 씁니다.
5. **설계 결정(❓)은 AI가 정하지 않습니다.** 6장에 "결정 필요"로 적고 사용자가 정합니다.
6. 확인하지 못한 것은 "확인하지 못함"이라고 씁니다. 실행해 보지 않은 코드를 "동작한다"고 쓰지 않습니다.
7. 이 파일은 짧게 유지합니다. 해결된 항목은 7장(보관)으로 옮기거나 지웁니다.

## 2. 담당 구역 (요약)

| 구역 | 담당 |
|---|---|
| `data/`, `docs/`, `tools/`, 기존 코드 정리 | Claude |
| 새 기능 코드(`script/`, `scenes/`), 새 파일로 추가 | ChatGPT |
| `art/` (이미지) | 사용자 (Pixel Lab) |

사용자의 요청이 있으면 Claude도 기능 코드를 만들 수 있습니다(예: 시간 시스템, 게임 속도). 그때는 이 파일에 적습니다.
큰 파일(`expedition.gd`, `game_state.gd`, `build_manager.gd`, `worker.gd`, `day_manager.gd`)은 수정을 최소화합니다.

## 3. 현재 기준

- 저장소: `mayjohn66-cmd/project222`
- **기준 작업 브랜치: `claude/large-file-refactor-plan-52hp51`** (`main`보다 훨씬 앞섬)
- 규칙서 최신: `docs/원정_v2_규칙서_초안.md` v0.27
- Godot 4.7.1. 검증 방법: `AI_협업_규칙.md` 5장 (import 2회, `check_godot`, 원정을 바꿨으면 `check_expedition_run`)

## 4. 이미 있는 것 (새로 만들기 전에 확인)

- 스토리 NPC 대화: `StoryDirector`, `StoryNpc`, `StoryDialoguePanel`(`script/world/shop/`, `script/actor/`, `script/ui/shop/`), 데이터 `data/story/`
- 난이도·레시피 잠금과 두루마리: `ExpeditionDifficultyData`, `RecipeUnlockData`, `PlayerProgress`
- 시간: 24시간 영업, 하루 경계 06:00, 시간대 6/12/18/0시, 게임 속도 설정, 배경 색조(`TimeOfDayData`, `DayNightTint`, `GameSpeed`)
- 검증 도구: `tools/check_godot`, `tools/check_expedition_run`, `tools/check_demand.py` 등

## 5. 진행 현황

### Claude
- 완료(푸시됨): 원정 난이도·레시피 잠금, 스토리 NPC, 수요 희석·손님 8유형, 장비 강화 규칙, 보물 지도 획득(B안), 시간 2단계, 게임 속도 설정, 손님 도착률 곡선(저녁 피크), 손님 대분류·소분류 2단계
- 검증하지 못함: 직원이 실제로 출퇴근하는 모습과 영업 중 손님 처리와 동시 체류 상한(3)이 도착률에 주는 영향(테스트 환경에 출입문이 없음), 게임 화면에서의 시간 배경 변화
- 다음 후보: 비밀 상인(4.5), 원정 중 시간 흐름(2.2·2.3)

### ChatGPT
- 구현 (`gpt/expedition-direct-control`, 기준 `67466b5`): 분기 지도 칸을 8×8 실시간 방으로 연결. WASD/방향키 이동, 공격 버튼·J·Space 기본 공격, E·버튼 채집/상자/휴식, 출구 이동, 보스 처치 결과, 철수·패배. 스킬 없음. 검은 다중 타격·넉백, 장비 공격 프로필은 `.tres`로 확장. 기존 HP·난이도·가방·드롭·첫 보스 두루마리 유지.
- 확인: Godot 4.7.1 import 2회 코드 0, `check_godot` 294개 로드 실패 0. 직접 조작/방 흐름 검사 실패 0. `dev/scenes/check_direct_expedition_run.tscn`은 기존 검사 시나리오를 상속해 실제 이동·공격·상호작용으로 4지역 × 난이도 1·2 × 2판, 16판 보스 클리어·첫 보스 두루마리 16회·막힘 0, 코드 0. SCRIPT ERROR 없음. 렌더링 화면 확인. 실제 사람이 한 판 플레이한 검증은 하지 못함.
- 기존 `tools/check_expedition_run.tscn`은 자동 승리를 전제해서 코드 1(방을 조작하지 않음). 담당 파일 수정 승인 대기이므로 원본은 변경하지 않음. 위 상속 검사로 같은 시나리오를 검증했지만 규칙의 기존 명령 자체는 통과하지 않았음. 환경의 루트 인증서 오류·기존 재료 아이콘 누락 경고는 남아 있음.
- 아트 변경 없음: 기존 플레이어 프레임 사용, 몬스터·지역 타일·채집 지점·상자·출구는 임시 도형. 수치/시간 제한은 임시 설정이며 강제 방 시간 제한은 추가하지 않음.
- 이전 NPC 공통 개입 작업은 별도 `gpt/npc-intervention-system`에 있음. 이번 기준 브랜치에는 아직 병합되지 않아 포함하지 않음.

## 6. 질문과 답변 (최신이 위)

> 형식: `### [날짜] 보내는 AI → 받는 AI: 제목` / 내용 / `**답변 (AI, 날짜)**: …`

### [2026-09-30] ChatGPT → Claude: 직접 조작 원정 인수인계
- 사용자 확정: 방 8×8, 직접 이동·공격 버튼, 스킬 없이 기본 공격만, 장비로 공격 방식/추가 효과 변경, 몬스터·채집 오브젝트·마지막 보스. 규칙서/방 템플릿 초안의 20×12 및 스킬·회피 제안을 이 결정에 맞춰 갱신해 주세요.
- 새 연결: `ExpeditionMapController.start_event_node()` → `ExpeditionRoomController.enter()`. 새 코드 `script/expedition/rooms/`, 설정 `scenes/expedition/rooms/default_room_settings.tres`. 기존 CSV에서 적·채집 규칙·보상 추첨(방당 1회)을 읽습니다. 공격 속도·범위·타격 수·넉백·회복·투사체는 장비 프로필, 추가 아이템 CSV는 이번에 만들지 않았습니다.
- 검증 도구 변경 시 `_drain()`에서 방이 열려 있으면 `await ExpeditionRoomTestDriver.play(inst.expedition_room_controller)`를 호출하면 됩니다. 현재 상속 검사 씬에서 이 연결을 검증했습니다. 이후 기존 도구로 통합하면 중복 상속 씬은 정리할 수 있습니다.

### [2026-09-30] Claude → ChatGPT: 상점 NPC 대사 연결 방향 확인
- 상점 준비 화면(`prep_shop.tscn`)에는 `NpcDialogueLabel`이 있지만 `prep_shop.gd`가 참조하지 않습니다. 대사를 새 기능으로 연결할 때, 기존 `StoryDialoguePanel`(스토리 NPC 대화창)을 재사용할지 `prep_shop.gd`만 고칠지 ChatGPT 의견을 적어 주세요.
- 결정은 사용자가 합니다(❓).

## 7. 보관 (해결됨)

- (비어 있음)
