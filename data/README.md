# data/ — 밸런스·글 데이터

수치와 글은 코드에 박지 않고 여기에 둔다. 읽는 코드는 `script/data/`. Godot가 CSV마다 만드는 `.import`·`.translation`은 자동 생성 파일이라 직접 고치지 않는다.

```
data/
├─ core/items.csv          # 아이템 전부(이름·가격·분류·그림 경로)
├─ expedition/             # 적·장비·강화비·난이도·이벤트·던전 채집
├─ production/             # 상품·가구 제작법, 재료, 해금 조건
├─ fishing/                # 낚시 어종·장소·요리(JSON)
├─ shop/
│  ├─ catalogs/            # 가구·손님·3D 표현·경제(19개, 4개 폴더로 분류)
│  │  ├─ furniture/ (6)    #   건축 목록·가구 정보·진행·시작 가구·진열대 칸수·계산대 구역
│  │  ├─ customer/  (3)    #   손님 대분류·소분류·수요
│  │  ├─ view3d/    (8)    #   3D 표현: 인물 외형·가구·아이템·계절·날씨·마을 건물·마을 그림 연결
│  │  └─ economy/   (2)    #   식품 유통기한·비밀 상인 판매 목록
│  ├─ events/              # 매장 행사
│  ├─ employees/           # 직원
│  ├─ requests/            # requests_text.csv(모든 이야기 글) · quest_visits.csv(손님 입장 방식)
│  └─ customer_arrival.csv · time_of_day.csv · opening_store_layout.json
├─ story/                  # NPC 초상화·표정·이야기 조건
├─ art/                    # 그림 연결표(id → 그림 파일, JSON)
├─ ui/ui_text.csv          # 화면 문구
└─ village_map_layout.json # 마을 지도 배치
```

값을 바꾼 뒤에는 `python tools/balance/balance_baseline.py .`(밸런스), 이야기 글은 `check_request_text`로 확인한다.
