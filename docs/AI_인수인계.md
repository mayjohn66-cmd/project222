# AI 인수인계 표 (GPT · Claude · Gemini 공용)

> **2026-10-03부터 이 파일은 `main`의 `docs/AI_인수인계.md`에 있습니다.** 예전 `docs/handoff` 고아 브랜치는 폐기했고 **절대 체크아웃하지 않습니다**(그 브랜치를 체크아웃하면 작업 폴더의 다른 파일이 모두 사라집니다).
> 수정은 작은 `[docs]` 커밋으로 `main`(또는 현재 작업 브랜치)에 올립니다. 규칙은 `docs/AI_협업_규칙.md` 2장.
> 2026-10-03 정리 당시의 기능 브랜치는 `main`에 병합되어 삭제되었습니다. 그 커밋 번호는 `main` 기록에 남아 있습니다. 이후 새 작업은 최대 두 줄기에서 진행하며, 아래 표의 최신 근거 브랜치를 확인합니다.

사용자는 이 표만 보면 "지금 누가 무엇을 기다리는지" 알 수 있습니다. 세 AI는 서로 직접 대화하지 못하므로, 이 표가 대화를 대신합니다.

## 1. 시작할 때 (사용자가 세 AI에게 같은 문장을 붙입니다)

> `git fetch origin main` 후 `docs/AI_인수인계.md`(`git show origin/main:docs/AI_인수인계.md`)를 읽고, 받는 AI 칸에 내 이름이 있는 줄만 처리해 줘. 끝나면 그 줄의 상태를 바꾸고, 다음 AI에게 넘길 일이 있으면 새 줄을 추가해 줘.

(저장소를 직접 못 보는 AI(Gemini 등)는 사용자가 이 파일 내용을 붙여 넣고, 그 AI의 답을 아래 표에 한 줄로 옮겨 적습니다.)

## 1.1 Gemini는 이렇게 다룹니다 (저장소를 직접 읽지 못함)

Gemini는 API로만 쓰며 저장소를 직접 읽거나 쓰지 못합니다. 대신 **사용자 PC에서 도구가 대신 호출하고 결과를 저장소 파일로 남깁니다**(`dev/gemini/`, 마을·스토리 작업 줄기와 함께 유지). 그래서 Gemini에게는 따로 "맥락 붙여 넣기"를 하지 않고 이 도구를 씁니다.

- 요청: `dev\gemini\run_request_text.bat draft [종류]` 또는 `sync`(새로 생긴·바뀐 요청만 작성). 종류는 `resident_request` / `community_request` / `resident_greeting`.
- 결과: `docs/drafts/story/requests_text_gemini_<시각>.csv`(검수 전 초안). 다듬기는 `polish 파일`, 반영은 `accept 파일`.
- 키(`GEMINI_API_KEY`)는 사용자 PC 환경변수에만 둡니다. 채팅·저장소·클라우드 환경에는 두지 않습니다.
- **Gemini 몫의 일은 이 표에서 받는 AI를 `사용자(Gemini 도구 실행)`로 씁니다.** 사용자가 위 명령을 실행하면 결과 파일이 생기고, 그 파일 경로를 근거 칸에 적어 `완료`로 바꿉니다. 이후 Claude가 `tools/validate_story.py`로 형식·글자 수를 검증합니다.

## 2. 인수인계 표 (아래에 새 줄을 맨 위에 추가)

| 번호 | 받는 AI | 보낸 AI | 요청 한 줄 | 근거(브랜치 @ 커밋, 파일) | 상태 |
|---|---|---|---|---|---|
| 16 | 사용자(Gemini 도구 실행) | ChatGPT | 가게 앞에 남기는 안부 service_text 6개 장면의 제안·세 주민 안부·남은 주민 안내·최종 선물 기억을 다듬어 줘(API 호출 안 함) | `feature/village-life` @ 0b064f1, `docs/콘텐츠_가게_앞에_남기는_안부.md`, `default_village_goodwill.tres`, `requests_text.csv`; 생활 후일담 모두 완독 다음 날·방문 순서 자유·최종 완독 때만 창고 선물 문맥 등록 | 대기 |
| 15 | Claude | ChatGPT | 생활 후일담 뒤 안부 사건의 초기 답례(밀 2·약초 2·평판 1 일회성)와 진행 간격을 검토해 줘 | `feature/village-life` @ 0b064f1, `docs/콘텐츠_가게_앞에_남기는_안부.md`; 새 사건 79개·기존 이야기 70개·생활 부탁 98개·후일담 97개·쉼터 51개·일상/수첩/글 도구 통과, 전체 521개 로드 실패 0; main @ a8b2cc2에서 이어감 | 대기 |
| 14 | 사용자(Gemini 도구 실행) | ChatGPT | 쉼터 뒤 생활 부탁 3개와 후일담 3개를 다듬어 줘(기존 personal_request/service_text 사용, API 호출 안 함) | `feature/village-life` @ 44aec02, `docs/콘텐츠_쉼터에서_이어지는_생활_부탁.md`, `default_trail_errands.tres`, `requests_text.csv`; 글 도구에 첫 모임 완독·다음 날·기능 변경 없는 생활 손질 문맥 등록 | 대기 |
| 13 | Claude | ChatGPT | 생활 부탁 초기 수치(갈대 2+수액 1, 가지 3+수액 1, 돌 2+가지 2, 각 30 G·평판 1)와 늪 재료 준비 시점을 검토해 줘 | `feature/village-life` @ 44aec02, `docs/콘텐츠_쉼터에서_이어지는_생활_부탁.md`; 새 부탁 98개·기존 후일담 97개·쉼터 51개·개인 부탁/게시판/수첩/글 도구 통과, 전체 로드 434개 실패 0; 사용자 커밋 959bdf3/cbc6c67 보존 병합 | 대기 |
| 12 | 사용자(Gemini 도구 실행) | ChatGPT | 길목 쉼터 공동 부탁 1개와 첫 모임·재방문 장면 5개를 다듬어 줘(기존 community_request/service_text 사용, API 호출 안 함) | `feature/village-life` @ ed745a5, `docs/콘텐츠_길목의_작은_쉼터.md`, `default_village_rest.tres`의 moments, `requests_text.csv`; 글 도구에 준비·실제 모임·조용한 재방문 문맥 등록 | 대기 |
| 11 | Claude | ChatGPT | 길목 쉼터 초기 수치(가지 5·돌 4 준비, 40 G·평판 1, 다음 날 15~18시 첫 모임 평판 1, 재방문 답례 없음)를 검토해 줘 | `feature/village-life` @ ed745a5, `docs/콘텐츠_길목의_작은_쉼터.md`; 쉼터 51개·후일담 97개·장터 57개·이야기 70개 및 기존 게시판/정착/일정/모임/수첩/글 도구 검사 통과, 전체 로드 432개 실패 0 | 대기 |
| 10 | 사용자(Gemini 도구 실행) | ChatGPT | 장터 뒤 먹거리 개인 부탁 3개와 전달 후 후일담 3개를 다듬어 줘(기존 personal_request/service_text 사용, API 호출 안 함) | `feature/village-life` @ f383d4e, `docs/콘텐츠_장터_뒤의_먹거리와_후일담.md`, `default_market_afterglow.tres`, `requests_text.csv`; 글 도구에 장터·레시피·완독 조건 등록, 장터 화자 문맥 수정 | 대기 |
| 9 | Claude | ChatGPT | 장터 후 먹거리 부탁 초기값(주스 2·스튜 1·약초 음료 2, 각 30 G·평판 1, 앞선 부탁/장터 다음 날·레시피 학습 조건)을 검토해 줘 | `feature/village-life` @ f383d4e, `docs/콘텐츠_장터_뒤의_먹거리와_후일담.md`; 후일담 97개·기존 부탁/주민/수첩/게시판/이야기/장터/글 도구 통과, 전체 로드 427개 실패 0 | 대기 |
| 8 | 사용자(Gemini 도구 실행) | ChatGPT | 작은 노점의 첫 장터 `service_text` 7개 장면의 제안·준비·재방문 안내·이웃들의 장터 대사를 다듬어 줘(새 종류 없음, API 호출 안 함) | `feature/village-life` @ 2082853, `docs/콘텐츠_작은_노점의_첫_장터.md`, `default_village_market.tres`의 moments, `data/shop/requests/requests_text.csv` | 대기 |
| 7 | Claude | ChatGPT | 첫 장터 초기 수치(빵 2·열매 3 전달, 다음 날 12~17시, 밀 3·40 G·평판 1 일회성 정산)를 검토해 줘 | `feature/village-life` @ 2082853, `docs/콘텐츠_작은_노점의_첫_장터.md`; 행사 57개·세 주민 실제 이동·기존 이야기/일정/모임/수첩/거래/게시판/글 도구 검사 통과, 전체 로드 423개 실패 0 | 대기 |
| 6 | 사용자(Gemini 도구 실행) | ChatGPT | 이세르의 마을 이야기 `service_text` 8개 장면의 주민 이야기와 세 기억 분기를 다듬어 줘(새 종류 없음, 수첩·재읽기 문장 포함, API 호출 안 함) | `feature/village-life` @ f300c92, `docs/콘텐츠_이세르의_마을_이야기.md`, `data/shop/requests/requests_text.csv`, `default_village_story.tres`의 moments | 대기 |
| 5 | Claude | ChatGPT | 이세르의 마을 이야기 답례 초기값(약초 2·평판 1, 선택 공통·일회성)을 검토해 줘 | `feature/village-life` @ f300c92, `docs/콘텐츠_이세르의_마을_이야기.md`; 새 퀘스트 70개·기존 주민/개인 부탁/길손/수첩/모임/글 도구 검사 통과, 전체 로드 417개 실패 0 | 대기 |
| 4 | 사용자(Gemini 도구 실행) | ChatGPT | 등불 아래의 길손 `service_text` 5개 항목의 첫 만남·물/빵 선택 반응·재방문 문장을 다듬어 줘(새 종류 없음, CSV 등록·검사 완료, API 호출 안 함) | `feature/village-life` @ 9704992, `docs/콘텐츠_등불_아래의_길손.md`, `data/shop/requests/requests_text.csv`, `default_lantern_wayfarer.tres`의 moments | 대기 |
| 3 | Claude | ChatGPT | 등불 아래의 길손 이벤트 수치(물/빵 중 하나 전달·다음 날 밀 답례·평판)와 누적 콘텐츠의 3D 브랜치 통합 경로를 검토해 줘(자동 병합·사용자 폴더 변경 없음) | `feature/village-life` @ 9704992, `docs/콘텐츠_등불_아래의_길손.md`; 이벤트 47개·기존 게시판/모임/수첩/글 도구 검사 통과, 전체 로드 412개 실패 0 | 대기 |
| 1 | 사용자 | Claude | Pixel Lab 첫 시험: `moss_cottage` 첫 면 결과 보고 | `feature/iso-3d-store` @ 0ae9082, `docs/그림_작업/00_먼저읽기.md` | 대기 |
| 2 | 사용자 | Claude | `main.tscn`에 StoreView3D 노드 1개 추가(기본 OFF, F10) 승인 여부 | `feature/iso-3d-store`, `docs/계획_매장_3D_적용_초안.md` | 결정 필요 |

상태 값: `대기`(받는 쪽이 아직 안 봄) · `진행` · `완료` · `결정 필요`(사용자가 정함) · `막힘`(이유를 요청 칸에 적음).

## 3. 쓰는 규칙

1. **한 줄에 한 일.** 요청은 한 문장, 자세한 내용은 근거 파일에 둡니다.
2. **근거는 `브랜치 @ 커밋`까지 씁니다.** 푸시하지 않은 일은 인수인계하지 않습니다.
3. 받은 AI는 끝나면 상태를 `완료`로 바꾸고 결과를 근거 칸에 갱신합니다.
4. ❓ 설계 결정은 AI가 정하지 않고 받는 AI를 `사용자`로 쓰고 `결정 필요`로 둡니다.
5. 완료된 줄은 맨 아래 "보관"으로 옮기거나 지웁니다. 이 표는 20줄을 넘기지 않습니다.
6. 이 파일만 수정하는 커밋은 `[docs]` 접두사로 올립니다. 파일은 `main`의 `docs/AI_인수인계.md` 한 곳에만 둡니다(복사 금지).

## 4. 모든 AI의 보고 끝 형식 (고정)

작업 결과를 사용자에게 보고할 때 마지막에 아래 세 줄을 붙입니다. 사용자는 자기 폴더 상태와 비교하기만 하면 됩니다.

```
브랜치: <브랜치 이름>
커밋: abc1234 (푸시됨 / 푸시 안 됨)
확인하려면: git checkout <브랜치 이름> && git pull  → 이 파일/화면에서 보임
```

## 5. 폴더 사용 약속

폴더가 여러 개라 "고쳤다는 곳에 가 보면 다르다"가 반복됩니다. 아래 약속으로 줄입니다.

| 폴더 | 역할 | 규칙 |
|---|---|---|
| 확인·실행용 폴더 1개 (사용자가 Godot로 여는 곳) | 푸시된 결과를 pull해서 확인 | AI가 말한 `브랜치/커밋`과 `tools\where.bat` 결과가 같은지 먼저 비교 |
| `OneDrive\Documents\project222` | ChatGPT의 작업 중인 변경, Pixel Lab(MCP) 등록 폴더(나중에 user 범위로 정리) | 이 폴더에서 `git add -A` 금지, AI가 브랜치를 바꾸지 않음 |
| `project222-crowd` 등 그 밖의 폴더 | 기능별로 쓰는 임시 폴더 | 쓰고 나면 이 표에 "쓴 폴더" 한 줄 또는 정리 |
| 클라우드 세션 (Claude) | 저장소를 새로 받아 작업하고 푸시 | 푸시한 것만 존재하는 것으로 봅니다 |

폴더 상태 확인: 저장소의 `tools\where.bat`를 더블클릭하면 폴더, 브랜치, 마지막 커밋, 푸시·pull 필요 여부, 저장하지 않은 변경이 한 화면에 나옵니다. 그 화면을 AI에게 캡처해 보내면 사용자 폴더 상태를 AI가 알 수 있습니다.

ChatGPT 콘텐츠 작업·확인 폴더: `C:\Users\john9\Documents\Codex\2026-09-30\clade\work\project222` (`feature/village-life` @ 0b064f1 내용, 통합 main @ a8b2cc2 기준). 이전 `content-expansion`·`handoff` 임시 폴더는 현재 없다. 사용자 실행용 `OneDrive\Documents\project222`의 브랜치는 변경하지 않았다. 최신 사건은 사용자 확인 전이라 작업 줄기에만 있으며 main에 자동 병합하지 않았다. 길손 이벤트 글만 생성하려면 이 콘텐츠가 포함된 폴더에서 `dev\gemini\run_request_text.bat draft service_text --ids lantern_wayfarer,lantern_wayfarer_water,lantern_wayfarer_bread,lantern_wayfarer_return_water,lantern_wayfarer_return_bread`를 사용한다. 초안 생성과 게임 CSV 반영은 별도 단계이며, 결과를 검토한 뒤 반영한다.

이세르의 마을 이야기 장면만 생성: `dev\gemini\run_request_text.bat draft service_text --ids sora_village_story,village_story_naru,village_story_doyun,village_story_reminder,village_story_choose,village_story_lantern,village_story_evening,village_story_home`. 선행 사건·대화 완료·선택의 맥락은 `default_village_story.tres`와 콘텐츠 설명에 있다. 약초·평판 수치 대신 생활 감각과 기억을 다듬고, 선택별 `completion`은 수첩과 이세르의 반복 대화에서 읽는 실제 기억으로 유지한다.

첫 장터 장면만 생성: `dev\gemini\run_request_text.bat draft service_text --ids first_market_intro,first_market_preparation,first_market_wait,first_market_open,first_market_doyun,first_market_sora,first_market_end`. **길손 → 이세르 이야기 → 첫 장터** 세 콘텐츠가 구현되었다. 장터 준비 후 다음 날부터 낮에 실제 이웃이 모이면 참여하며 기한은 없다. 준비 소개는 UI에, 마무리 `completion`은 수첩에 사용한다. 재방문 안내는 날짜가 지나도 맞는 말로 쓰고 새 고객·건물·반복 판매를 약속하지 않는다. 후속 후보는 장터 후일담·계절 먹거리 부탁이다.

장터 후속 먹거리 부탁과 후일담도 구현되었다. 부탁만 생성: `dev\gemini\run_request_text.bat draft personal_request --ids naru_market_juice,doyun_market_soup,sora_market_drink`. 후일담만 생성: `dev\gemini\run_request_text.bat draft service_text --ids market_afterglow_naru,market_afterglow_doyun,market_afterglow_sora`. 창고의 완제품을 게시판에서 전달하고 실제 주민에게 E로 다시 이야기한다. 후일담 완독은 추가 보상 없이 수첩에 기억을 남긴다. 정식 인물 기준 파일 두 개는 수정하지 않았다. 기존 장터의 speaker 장면에 우물 모임 문맥을 덮어쓰던 글 도구 문제를 수정했으므로 최신 콘텐츠의 도구를 사용한다.

길목에 놓는 작은 쉼터도 구현되었다. 공동 부탁만 생성: `dev\gemini\run_request_text.bat draft community_request --ids trail_rest_corner`. 모임·재방문 장면만 생성: `dev\gemini\run_request_text.bat draft service_text --ids trail_rest_open,trail_rest_naru,trail_rest_sora,trail_rest_end,trail_rest_quiet`. 첫 장터와 먹거리 후일담 세 개를 모두 완독한 다음 날부터, 꽃자리 준비와 세 주민 친밀도 7 조건을 충족하면 게시판에서 쉼터를 준비한다. 기존 `oak_bench.png`를 재사용했고 새 그림은 만들지 않았다. 준비 다음 날부터 15~18시에 세 주민이 실제로 모여야 첫 모임을 진행한다. 모임 후에는 E로 조용한 재방문을 기록하며 반복 보상·체력 회복·시간 건너뛰기는 없다. 조용한 장면은 현장 묘사이며 주민이 항상 곁에 있다고 쓰지 않는다. 정식 인물 기준 파일은 유지했고 Gemini API는 호출하지 않았다.

쉼터에서 이어지는 생활 부탁 3개와 전달 후 후일담 3개도 구현되었다. 부탁만 생성: `dev\gemini\run_request_text.bat draft personal_request --ids naru_bundle_mending,doyun_handle_mending,sora_page_weights`. 후일담만 생성: `dev\gemini\run_request_text.bat draft service_text --ids trail_afterglow_naru,trail_afterglow_doyun,trail_afterglow_sora`. 길목 첫 모임·앞선 먹거리 전달·해당 후일담 완독 중 가장 늦은 날의 다음 날부터 열린다. 원정 재료를 창고에 모아 게시판에서 전달하고 기존 주민에게 E로 끝까지 이야기를 듣는다. 가방 확장·장비 지급·공격력 개선·날씨·책·새 시설은 없으며 후일담에 추가 답례도 없다. 기한이나 새 원정 방문 강제가 없다. 정식 인물 기준 파일은 유지했고 API는 호출하지 않았다. 개인 부탁 합계는 12개, 전체 대사 CSV는 86행이며 서로 다른 집계다. 작업 중 사용자 커밋 959bdf3와 원격 cbc6c67을 이력 삭제 없이 합쳤다.

가게 앞에 남기는 안부 사건도 구현되었다. 장면만 생성: `dev\gemini\run_request_text.bat draft service_text --ids goodwill_intro,goodwill_naru,goodwill_doyun,goodwill_sora,goodwill_wait,goodwill_finish`. 생활 부탁 세 개의 전달·후일담을 끝까지 들은 다음 날부터 이세르에게 E로 제안을 듣고, 타블렌·코르빈·이세르의 안부를 순서와 시간대에 관계없이 완독한다. 이세르의 제안과 본인 안부는 별도다. 모두 듣고 이세르에게 돌아와 최종 대화 완독 시 밀과 약초를 창고에 일회성 지급한다. 물품 준비·돈 소비·기한·새 시설·고객·편지/선물 오브젝트가 없다. 수첩은 아직 못 들은 주민을 가리키고 완료 뒤 각 안부와 공동 기억을 다시 읽는다. 정식 인물 기준 파일·이미지는 유지했고 API는 호출하지 않았다. 대사 CSV 합계 92행은 퀘스트 수가 아니다. 현재 작업 줄기는 `feature/iso-3d-village`와 `feature/village-life` 두 개다.

## 6. 보관
(완료된 줄을 여기로)
