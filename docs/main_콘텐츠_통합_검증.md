# main 콘텐츠·3D 통합 검증 (2026-10-04)

## 병합 범위

사용자가 지금까지의 작업을 main에 병합하도록 요청했다. main `ed06085`에서 최신 3D `44661d4`까지 먼저 이동한 뒤 콘텐츠 `7e3761a`를 병합했다. 두 작업의 커밋 이력을 보존하는 merge commit으로 올린다. 사용자 실행 폴더의 저장과 작업 파일은 직접 변경하지 않았다.

- 최신 3D 매장·마을·원정 자연 지형, 기본 3D ON, F9/F10 전환 제거를 유지한다.
- 첫 실제 결제→행상인 물물교환→원정→원재료 판매 도입부, 주민 부탁·정착·관계 사건·제품 발전을 포함한다.
- 공용 매장 행사 3개·계절 행사 8개, 판매 기록에서 이어지는 부탁과 사계절 생활 사건을 포함한다.
- 일반 원정 지역 5개와 지도 조건 유적 1개, 계절·날씨 재료/몬스터, 냉장·냉동·말리기·변형·보존 체험 사건 3개를 포함한다.
- 대사 CSV 241행을 유지한다. Gemini API는 호출하지 않았다.

## 충돌 해결과 실행 중 수정

실제 충돌은 `expedition_room_view.gd`, `expedition_room_controller.gd` 두 곳이었다. 3D 경로와 출발 환경 저장·날씨 오버레이를 함께 유지했다. 초원은 기존 숲, 계곡은 기존 물가 메시를 재사용하고 실외 3D 바닥에 계절 색을 적용했다. 계절 채집 오브젝트도 실제 채집 지점에 표시한다. 실내 광산·유적은 바닥 계절 색과 실외 강수 표현에서 제외한다.

통합 검사에서 3D 쪽 무작위 채집 위치가 콘텐츠 쪽 최종 장애물 변경 이후 벽과 겹치는 문제가 드러났다. 지역 장애물 확정→오브젝트 재배치→채집 지점 배치 순서로 수정했다. 빈 지점 목록은 빈 배열로 처리한다. 테스트 이동 도우미는 장애물을 우회하도록 바꾸되 실제 이동·기본 공격·E API를 사용한다. 원정 완주 검사에서 순간이동·벽 삭제·HP 변경으로 우회하지 않는다.

기존 테스트는 새 도입부의 자동 독백을 열어 둔 채 후반 퀘스트를 호출하거나, 빈 진열대에서 무료 연습 상품을 기대했다. 후반 테스트의 시작 상태를 명확하게 분리하고 첫 결제 검사는 실제 소유 상품 진열·독백 완독·실제 결제·재시도·직원 선점 방지·행상인 연결을 검사하도록 갱신했다. 독립 계절 시나리오에서 날짜를 뒤로 돌릴 때 보존 처리 날짜도 초기화한다. 채집 선택 검사는 무작위 실제 지점을 읽고, 도구가 필요한 선택에는 등록된 도구를 가방에 넣는다. 실제 게임의 조건이나 저장 검증은 완화하지 않았다.

매장 3D 카메라가 stretch 컨테이너의 SubViewport 크기를 매 프레임 다시 쓰던 경고도 제거했다. 컨테이너가 크기를 관리하고 ID 뷰포트는 실제 크기를 따른다. 겨울 채집 캡션은 현 규칙의 ‘서리 얼음’으로 맞췄다.

## 검증 결과

Godot 4.7.1, 각각 별도 사용자 데이터 폴더에서 headless 실행했다. 최종 재검사 결과를 기준으로 아래 46개 씬 모두 종료 코드 0, SCRIPT ERROR/Parse Error 없음이다.

| 검사 | 결과 |
|---|---|
| 필수 import 2회 | 종료 0, 두 번째 스크립트/파싱 오류 0 |
| 전체 `.gd`/`.tscn` 로드 | 604개, 로드 실패 0 |
| 기본 프로젝트 실행 | 240프레임, 종료 0 |
| 실제 3D·날씨 통합 | 88개, 실패 0; 기본 ON/F9·F10 유지/F7 공유/6지역/실내외/메뉴 정지 |
| 기존 원정 도구 | 16판 모두 결과, 막힘 0 |
| 직접 원정 검사 | 16판 모두 결과, 막힘 0 |
| 신규 초원·계곡 | 226개, 실패 0; 8판 완료, 막힘 0 |
| 계절 원정 | 5,225개, 실패 0; 사계절×6지역 24판 완료, 막힘 0 |
| 도입부/수동 결제/결제 재개 | 새 도입부 80개 및 기존 결제 검사, 실패 0 |
| 보존/보존 체험/제품 발전 | 64/187/120개, 실패 0 |
| 원래 계절 사건/생활 재료 부탁 | 146/174개, 실패 0 |
| 주민 관계 선택/행사 후속 부탁 | 234/172개, 실패 0 |
| 매장 행사 일정/실제 판매·대사 | 361/370개, 실패 0 |
| 대사 CSV 형식 | 241행, 오류 0·주의 0 |
| 밸런스 기준선 | 종료 0; 객단가 257G·재고 충분 가정 일매출 6,946G·초기 급여 0 |

밸런스 기준선은 계절 보존 투자/장기 매출/새 일회성 보상 전체를 계산한 경제 시뮬레이션은 아니다. 해당 검토 요청은 인수인계 표에 유지한다.

### 검사 씬 목록

- `all_load`
- `main_content_integration`
- `progressive_tutorial`
- `manual_checkout`
- `checkout_event`
- `preservation`
- `preservation_lessons`
- `crafting_path`
- `resident_trade`
- `village_routine`
- `resident_settlement`
- `village_life`
- `village_smithy`
- `village_gathering`
- `direct_expedition`
- `expedition_run`
- `direct_expedition_run`
- `direct_room_lifecycle`
- `isometric_room`
- `expedition_result_layout`
- `added_dungeons`
- `seasonal_expedition`
- `iso_box`
- `iso_sort_group`
- `iso_sorter`
- `personal_requests`
- `resident_requests`
- `community_board`
- `content_expansion`
- `lantern_wayfarer`
- `village_story`
- `village_market`
- `market_afterglow`
- `village_rest`
- `trail_errands`
- `village_journal`
- `request_text`
- `request_text_runtime`
- `gemini_client`
- `village_goodwill`
- `seasonal_village`
- `seasonal_life_requests`
- `resident_memories`
- `store_event_schedule`
- `store_event_story`
- `store_event_followups`

## 남은 확인 사항

headless 결과는 화면 미관·성능·실제 장시간 플레이의 확인을 대신하지 않는다. main으로 갱신한 뒤 새 게임 첫 거래와 3D 원정/계절 보존을 실제 화면에서 확인한다. 기존 저장 파일은 검사용 프로필과 분리했다.

기존 루트 인증서 읽기 오류와 누락 아이콘의 임시 표시 경고는 남아 있다. 직전 main 에셋 점검에서 84개 누락 아이콘 참조와 42개 규격 FAIL/26개 WARN을 확인했으며, 이번 통합은 이미지 제작·규격 수정을 포함하지 않는다. 검증에 따른 `.import`·`.translation` 부산물 및 자동 생성 밸런스 보고서는 스테이징하지 않는다.

병합 결과 커밋 번호와 다음 검토는 푸시 이후 `docs/AI_인수인계.md`에 기록한다.
