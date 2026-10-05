# Claude 작업 기록: 전체 3D 전환과 3D 오브젝트 (2026-10-04 ~ 10-05)

작성: Claude. 사용자 방향: **게임 전체를 3D 로 하고, 2D 코드·스프라이트는 모두 정리하며, 모든 오브젝트를 실제 3D 모델로 바꾼다. 매장은 "현대 편의점이 통째로 이세계에 온" 모습.** 작업은 `main` 에서 직접, 작은 커밋으로 진행했다. 표의 해시는 `git show <해시>` 로 볼 수 있다.

## 1. 한눈에 보는 결과

| 영역 | 상태 | 대표 커밋 |
|---|---|---|
| 2D↔3D 전환 토글 제거(3D 고정) | 완료 | `44661d4`, `5db0ca5` |
| 2D 그리기 코드 제거(바닥·벽·가구 Visual·캐릭터·마을 스프라이트·NPC 임시 그림·미사용 도형 시스템) | 완료 | `4beaf93` `b0433e9` `83c5af1` `06e81b8` `1d5c71f` `2835365` `5f12d98` `c8fab8a` |
| 3D 건축 미리보기(가능 청록/불가 붉음, 발자국·직원·결제·접근 칸) | 완료 | `077974c` |
| 원정 던전 방 3D 무대·연출·준비 마을 3D | 완료 | `8bbb093` `4af2f64` `6a314aa` 외 |
| 날씨·계절(비·눈·낙엽·웅덩이·발자국·덤불 성장) 3D | 완료 | `efd2cbe` `2cf8864` `2078ce3` `5a5bee5` |
| 가구 3D 모델(계산대·창고 선반·음료 제조기·마법 오븐·화분·등불·진열장·벽 장식·문 3종) | 완료 | `2c627b1` |
| 진열대 3D(나무 틀+선반 위 상품 실제 수만큼, 59종 모양) | 완료 | `826f453` `56b25bf` |
| 창고·생산실 3D(RoomMirror) | 완료 | `5a6cc98` |
| 현대 편의점 외관(흰 타일 바닥, 흰 벽+브랜드색 띠, 유리 진열창, 자동문) | 완료 | `2bb6f28` |
| 벽 충돌 두께·앞쪽 벽 투시·풍경 파묻힘 방지 | 완료 | `1646097` `d558618` `c24adc9` |
| 손님·직원별 3D 외형(옷·모자·등짐·손 소품) | 완료 | `01095d7` |
| 냉장함·냉동함 가구(제작·배치·상호작용) | 완료 | `116f170` |
| 행사 장식(벽 장식 줄) | 완료 | `5f12d98` |
| 원정 접선 방(`expedition_contact_room`) 3D 전환 | **미착수** | |

## 2. 구조 요약 (새 기능을 붙일 때 읽을 것)

- **3D 거울**: 게임 로직(2D 노드)은 그대로 두고 `StoreView3D`(`script/world/view3d/store_view_3d.gd`)가 노드 상태를 읽어 3D 로 그린다. 3D 층은 항상 켜져 있고, 건축 중 트리가 멈춰도 갱신된다(`process_mode = ALWAYS`).
- **앞뒤 정렬**: 물체마다 상자(칸 좌표+높이)를 `IsoSorter`(`script/world/shape/iso_sorter.gd`)에 넣어 순번(rank)을 얻고, 셰이더가 순번으로 깊이를 정한다. 그래서 새 3D 물체는 `_set_mesh_item(key, mesh, materials, lo, hi, total_blocks, …)` 로 등록해야 한다. **`IsoSorter` 는 지우지 말 것.**
- **모델 만들기**: `VillageAssets.PartBuilder`(부품=면 하나, 메시당 면 256개 한도 → 재질 이름 하나당 부품 하나), `FurnitureAssets.Frame`(u·v·y 좌표). 높이 1 = 1블록 ≈ 월드 1.
- **회전**: 가구 `rot` 0=앞 +z, 1=+x, 2=-z, 3=-x. 벽 부착물은 0=뒤(y 작은 벽), 1=x 큰 벽, 2=y 큰 벽, 3=x 작은 벽(`FurnitureAssets.wall_front_rot`).
- **지켜야 할 약속**: 수치·종류는 코드에 박지 않고 CSV 로 뺀다.

## 3. 데이터 파일 (밸런스·외형을 코드 밖에서 조정)

| 파일 | 내용 |
|---|---|
| `data/shop/catalogs/furniture_3d.csv` | 가구의 3D 종류(box/model/shelf/door/wall_plate)·높이·재질·색 |
| `data/shop/catalogs/item_3d.csv` | 진열 상품 → 모양(59종) |
| `data/shop/catalogs/village_art.csv` | 옛 그림 경로 → 칸 크기(마을 편집기가 사용) |
| `data/shop/catalogs/actor_looks_3d.csv` | 사람별 외형: 옷·피부·머리 색, 모자·등짐·손 소품, 아이 체형 |
| `data/shop/events/store_event_decor_3d.csv` | 행사별 장식 종류·색·줄 번호 |

## 4. 추가한 3D 기능 상세

### 4.1 사람별 외형 (`01095d7`)
- 키: 플레이어 `player`, 직원 `worker`, 이야기 NPC `story_npc`, 상인 `merchant_npc`, 손님은 소분류 id(없으면 대분류 id). 손님 종류가 늦게 정해져도 키가 바뀌면 다시 만든다.
- 모자 8종(cap straw hood helmet wizard chef beret fedora), 등짐 5종(backpack quiver satchel mailbag cape), 손 소품 11종(pickaxe hammer sickle staff sword basket flask book lantern briefcase pot). 색은 모두 CSV.
- 코드: `ActorLooks`(로더), `BlockyFigure.build(..., look)`. 빈 칸은 기본 색이라 플레이어 모습은 이전과 같다.
- 갤러리 5쪽 "사람별 외형"에서 전체를 볼 수 있다.

### 4.2 냉장함·냉동함 (`116f170`, 문서 `docs/콘텐츠_냉장_냉동_가구.md`)
- 가구 `fridge_unit`(1×1, 철광석8+수정3) / `freezer_unit`(2×1, 철광석12+수정5). 보강 나무 집기 제작 후 "매장" 분류에서 제작.
- 가까이에서 상호작용하면 `PreservationPanel.open_for_unit` 이 열린다. **처음 열 때 설치 대금 없이 설치**. 관리 메뉴 경로와 설치 대금(120/240G)은 그대로.
- 보관함은 **설비당 하나**(여러 대를 놓아도 총 12개 공유). 대수별 용량은 ❓미정.
- 주의: 새 가구가 `furniture_progression.csv` 에 들어가면 공통 변형 모델이 먼저 쓰이므로 `FurnitureAssets.build` 가 전용 모델(`MODEL_IDS`)을 먼저 쓰게 바꿔 두었다.

### 4.3 행사 장식 (`5f12d98`)
- 진행 중인 행사에 따라 매장 북·서 벽 안쪽 위에 줄이 걸린다(깃발 `bunting` / 꽃 `garland` / 등불 `lanterns` / 전구 `lights`). 바닥에 놓지 않아 동선과 겹치지 않는다. 행사가 둘이면 줄이 한 겹 더 내려온다.
- 코드 `StoreEventDecor3D`, 확인 장면 `dev/spike3d/event_decor_shot.tscn`(행사 날짜별 화면 저장).

## 5. 삭제·정리한 것 (모두 git 기록에 있음)

- 2D 가구·문 그림, 옛 아이템 그림, 쓰지 않는 생성본 이미지 60장(`4bb3780`), 마을 2D 원본 그림 29장·지붕 색 셰이더·옛 확인 장면(`2835365`).
- 캐릭터 2D 스프라이트(`character_visual.gd` 포함, `1d5c71f`), 스토리·상인 NPC 의 도형 임시 그림(`5f12d98`).
- 2D 도형 시스템 `IsoBox` `IsoObject` `IsoSortGroup` `IsoGeometry` 와 전용 미리보기·검사 장면 5쌍(`c8fab8a`). **`IsoSorter` 는 3D 정렬이 쓰므로 남김**(처음에 shape 폴더 전체가 미사용이라고 잘못 보고했다가 확인해서 바로잡음).

## 6. 확인 방법과 검증 상태

- 검사 장면(`dev/scenes/`): `check_main_content_integration`(88), `check_furniture_objects`(563), `check_preservation_unit`(17), `check_iso_sorter`. 모두 실패 0 (2026-10-05 기준).
- 시각 확인: `dev/spike3d/model_gallery.tscn`(1 가구, 2 진열 상품, 3 마을, 4 캐릭터, 5 사람별 외형. `-- --shot <폴더>` 로 PNG 저장), `event_decor_shot.tscn`.
- 실행 환경 메모: 클라우드 컨테이너에서 소프트웨어 렌더(`xvfb-run`)로 확인했다. 새 `class_name` 을 추가했다면 먼저 `godot --headless --import` 를 한 번 돌려야 클래스 목록이 갱신된다.
- **중요: 아래는 소프트웨어 렌더·자동 검사로만 확인했고 사용자 PC 의 실제 GPU 에서는 아직 확인되지 않았다.** 사용자가 직접 확인해 준 것은 진열대 상호작용 복구, 건축 미리보기, 창고·생산실 3D.

## 7. PC 에서 확인이 필요한 것

1. 마을 지도 편집기에서 발자국으로 오브젝트 선택.
2. 창고 선반에 저장 아이템이 층별로 보이는지, 크기가 선반을 뚫지 않는지.
3. 낮 시간 유리 진열창·자동문의 밝기, 흰 타일 바닥의 눈부심.
4. 창고·생산실에서 건축 모드.
5. 손님·직원 외형(등짐·소품이 걷는 동안 몸을 뚫지 않는지), 스토리·상인 NPC 가 3D 로 제대로 보이는지.
6. 냉장함·냉동함 배치·제작·상호작용 거리, 건축 모드 배치·철거.
7. 행사 장식이 포스터 등 벽 장식과 겹치지 않는지.

## 8. 알려진 한계·미결

- 냉장·냉동: 같은 종류 여러 대의 용량 합산 방식(❓), 제작 재료·해금 조건은 Claude 가 정한 임시 값, 아이콘 이미지 없음(3D 미리보기로 대체).
- 행사 장식의 색·종류는 임시 값. 모델·장식에 실제 그림이 생기면 `art/world3d/<자산id>/<면이름>.png` 규칙으로 덮어쓴다(`VillageAssets.apply_overrides`).
- 가구 아이콘이 원래 없는 것(`night_lantern`, `antique_cabinet`, `old_world_map`, `adventurer_banner`)은 이전부터 누락(경고만).
- 원정 준비 마을 스모크 점검 47번째 줄 단언은 `main` 에서도 같게 실패하는 기존 문제.
- 원정 바닥의 눈·젖음 효과 3D 이식은 미룬 상태.
- 사용자 몫: 옛 원격 브랜치·PR #1 정리, PC 확인.

## 9. 다음 후보

1. 원정 접선 방(`script/.../expedition_contact_room.gd`, AnimatedSprite2D 사용) 3D 전환.
2. 위 7장 PC 확인 결과 반영.
3. 남은 미사용 이미지 정리(삭제는 계획·승인 후).

## 10. UI 개편: 관리 창 = 펼치는 노트 (2026-10-05)

사용자 콘셉트: 관리 창을 여는 것은 **영업 일지(책)를 꺼내 펼치는 것**, 탭은 책에 붙은 포스트잇 책갈피. 와이어프레임(세로형 닫힌 책 + 포스트잇 → 펼침면 두 쪽, 탭을 옮기면 해당 포스트잇으로 책장이 넘어감)을 그대로 구현했다. 코드는 `script/ui/management/`.

| 부분 | 파일 | 요약 |
|---|---|---|
| 펼침면·표지·책장 넘김 그리기 | `book_views.gd` | `Paper`(두 쪽·가운데 홈·탭별 종이색/무늬), `Cover`(닫힌 표지), `Flip`(탭 이동 시 앞/뒤 방향 책장 넘김, 옛/새 화면 사진을 한 장의 앞뒤면으로 씀) |
| 3D 책(열고 닫기) | `book_stage_3d.gd` | 정사영 카메라로 비스듬히 보다가 펼침이 끝나면 정확히 위에서 내려다봐 2D 펼침면과 같은 자리·크기로 겹침. 표지 바깥 질감은 2D 표지 그림을 SubViewport 로 한 번 그려 사용. 포스트잇은 내비게이션 버튼 위치에서 가져와 3D 로 붙임 |
| 연출 순서 | `management_presentation.gd` | 열기: 3D 책 상승 → 표지가 제본선 축으로 넘어감 → 3D 를 걷고 2D UI 나타남. 닫기: 반대. `book_3d`(3D/2D 선택), `animations_enabled`(끄기, 검사 장면용) |
| 탭 넘김(3D 책장) | `book_flip_3d.gd`, `book_views.gd`(Flip) | 탭을 옮기면 옛/새 화면을 사진으로 떠 한 장의 앞뒤면 + 바닥 두 쪽으로 쓴다. 한 장은 14마디로 자유 모서리가 뒤처지며 휘고 그림자가 진다. 뒤쪽 탭 = 오른쪽 쪽이 왼쪽으로, 앞쪽 탭 = 왼쪽 쪽이 오른쪽으로. **탭이 멀수록 종이를 더 넘긴다**(건너뛰는 탭 수만큼, 최대 6장, 장마다 0.09초씩 늦게 시작; 맨 위 한 장의 앞면만 옛 화면, 맨 마지막 한 장의 뒷면만 새 화면, 나머지는 빈 종이). `book_3d` 를 끄면 2D 책장 넘김 |
| 탭별 두 쪽 배치 | `book_layout.gd`, `book_flow_vbox.gd`, `inventory_detail_pane.gd` | 인벤토리(왼쪽 목록 / 오른쪽 상세 + 가구는 3D 미리보기), 설계도·생산·직원·건설·일정·정보. 긴 목록은 `BookFlowVBox` 가 두 쪽에 걸쳐 흐름 |
| 이름 | `player_progress.gd`, `title_screen.gd` | 새 게임 전에 점장 이름을 지음(최대 8자), 저장·불러오기, 표지 명패에 표시 |

- 조정 값: 책 두께 `BookViews.COVER_PAD/FORE_W/BOTTOM_T`, 두 쪽 간격 `BookLayout.GUTTER`(48), 포스트잇 `FLAG_OUT`(튀어나온 길이)·`FLAG_GAP`(간격)·`ONTO`(펼친 탭이 쪽 위로 넘어오는 길이), 3D 시작 각도 `BookStage3D.PITCH_START`, 연출 시간은 `management_presentation.gd`의 `_open_3d/_close_3d` 트윈.
- 확인 도구(`dev/spike3d/`): `book_anim_shot`(열기·닫기 연속 장면), `book_flip_shot`(탭 넘김), `book_tabs_shot`(전 탭 배치), `ui_audit_shot`(UI 현황), `ui_style_preview`(스타일 시안).
- 알려진 한계: 소프트웨어 렌더로만 확인. 탭 넘김은 화면 사진 방식이라 새 화면 사진을 뜨는 한 프레임 동안 깜빡임 가능. 정보 탭처럼 긴 글은 두 쪽을 채운 뒤 스크롤. 3D 책의 쪽에는 UI 가 없고(펼침 뒤 2D 로 교체) 쪽 옆면 줄무늬는 3D 쪽에 일부만 있음.
