# NPC 초상화 표정 늘리기 (2026-10-08)

NPC 10명은 지금 초상화가 한 장씩(기본 표정)이다. 표정 그림을 늘려 대사 표시 `{놀람}` 등이 NPC에게도 통하게 한다.

## 1. 게임 쪽(완료)
- 규칙: `art/npc/expr/<npc_id>_<표정id>.png` 파일이 있으면 그 표정을 쓰고, **없으면 기존 기본 초상화**를 쓴다. 그림이 오는 대로 파일만 넣으면 된다(등록 작업 없음).
- 표정 id: `portrait_expressions.csv`의 7가지(neutral은 기본 초상화라 따로 만들지 않는다).
- 대사 표시는 주인공과 같다(`주인공_초상화.md` 8장). 예: `{놀람}…` — 화자가 그 NPC일 때만 적용된다.
- 검사: `dev/scenes/check_player_portraits.tscn`(37항목). 그림 파일이 실제로 들어간 뒤의 화면은 아직 확인하지 못했다.

## 2. 만들 그림(PC)
- 목록: `npc_portrait_requests.csv`(10명 × 6표정 = 60행, `batch` 열로 단계 구분).
- **1단계(40장)**: smile·surprised·worried·flustered. 대사에서 가장 자주 쓰이는 감정이라 먼저 만든다.
- **2단계(20장)**: tired·determined. 1단계 결과가 괜찮을 때 만든다.
- 규격: 기본 초상화와 같은 80x96 생성 → 160x192(2배, NEAREST). 원본은 `_1x`로 보관.
- 방법: 새로 그리지 않고 **기본 초상화(`art/npc/<npc_id>.png`)를 부분 다시 그리기(inpaint)**로 눈·눈썹·입만 바꾼다. 얼굴 윤곽·머리·옷·위치가 같아야 한다(주인공 표정을 만들 때 쓴 방식).
- 인물 외형 기준: `docs/drafts/story/character_profiles.md`. 화풍 기준: `받은그림/초상화/_서브컬처_전체.png`(중간 크기 눈, 짙은 도트 윤곽).
- 저장: 받은 그림은 `docs/그림_작업/받은그림/초상화/npc_표정/<npc_id>/`에 두고 확인한 뒤 `art/npc/expr/`로 복사한다.

## 3. 표정 문구(영어, 인물 이름 뒤에 덧붙임)
- smile: `gentle warm smile, eyes slightly curved`
- surprised: `eyes wider, eyebrows raised, mouth slightly open`
- worried: `eyebrows drawn together, anxious gaze, mouth slightly pressed`
- flustered: `blushing, hesitant eyebrows, awkward small mouth`
- tired: `heavy eyelids, relaxed tired mouth, not sickly`
- determined: `closed mouth, set eyebrows, firm gaze`
- 인물마다 고유한 버릇(코르빈은 눈을 잘 안 마주침, 피니아는 눈썹 변화가 큼 등)은 `character_profiles.md`를 참고해 과장하지 않는 선에서 반영한다.

## 4. 이후(그림이 들어온 뒤)
- 표정이 있는 NPC 대사에 `{표정}`을 단다. **주의**: 첫 손님(델빈) 단계처럼 화자가 "나"로 표시되는 줄이 있어 화자 이름 연결을 먼저 확인한 뒤 달아야 한다. 그림이 오기 전에는 NPC 대사에 표시를 달지 않았다.
- Gemini에게 NPC 대사를 쓰게 할 때 표정 표를 함께 준다.
