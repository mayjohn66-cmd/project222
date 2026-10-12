# requests/ — 이야기·부탁 엔진 (73개)

한 이야기는 보통 파일 3개다: **`_director`**(화면·입력) + **`_flow`**(진행 규칙·기록) + **`_settings`**(수치). 구조·조건은 `scenes/shop/requests/default_*.tres`, 대사는 `data/shop/requests/requests_text.csv`.

| 묶음 | 파일 접두어 | 내용 |
|---|---|---|
| 주민 부탁 | `resident_request` · `resident_trade` · `resident_story` · `resident_memory` · `resident_followthrough` · `resident_merchant` | 기본 부탁, 타블렌 교환 노점, 주민과 남기는 기억 |
| 마을 부탁 | `community_*` · `crafting_path_*` · `personal_request_flow` · `workshop_request_flow` | 게시판, 제작 배우기, 개인 부탁 |
| 마을 이야기 | `village_*` · `lantern_*` · `market_afterglow_*` | 생활·확장·장터·쉼터·안부·대장간·수첩, 등불 길손 |
| 단골·날씨·계절 | `regular_*` · `weather_life_*` · `seasonal_*` · `season_stockpile_flow` | 재방문, 날씨 인사, 계절 사건 |
| 4막 | `act_four_*` | 길 위의 가게, 유적의 단서 |
| 입장 방식 | `quest_visit_director` | 이웃이 손님으로 들어와 이야기를 건넴(`data/shop/requests/quest_visits.csv`로 켜고 끔) |
| 기타 | `store_event_followup_flow` · `early_progression_guide` | 매장 행사 후속, 초반 안내 |

새 이야기를 만들 때: 대사는 CSV에, 조건은 `.tres`에, 동작은 위 세 종류 파일로. 대사에 조작법("게시판에서 전달해 줘" 등)은 쓰지 않는다(안내는 summary·수첩이 맡는다).
