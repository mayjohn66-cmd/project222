<!-- revvy:shared-memory:start -->
Shared memory for ALL agents (Claude/Codex/Kimi) lives at `.revvy/shared-memory.md`.
Read it at session start. When you make a durable decision, adopt a convention,
or leave work half-done, append a dated one-line entry there so the next agent
(possibly a different model) picks up where you left off.
<!-- revvy:shared-memory:end -->

## UI 작업

2026-10-13 사용자 글씨 크기 정돈 후속: 펼친 수첩은 제목 `UiTypography.BOOK_HEADING_SIZE`(38px), 설명·수치·목록 `BOOK_BODY_SIZE`(19px), 버튼·소탭·포스트잇 `BOOK_CONTROL_SIZE`(19px)를 쓴다. 수첩 내부에 기존 크기 변환 `size(18)` 등을 사용해 본문이 갑자기 38px가 되게 하지 않는다. 대화창·일반 확인창의 기존 38px 기준과 구분한다.

UI 수정 전에 `docs/UI_디자인_규칙.md`를 읽는다. 본문·일반 조작 UI의 기준색은 `#F3E3BD`·`#4A3024` 두 개이며 명도·투명도만 조절한다. 선택 버튼은 종이색을 유지하고 갈색 테두리·밑줄·밝기로 구분하며 포커스·커서·진행 표시도 갈색 변형을 쓴다. **2026-10-13 사용자 후속 요청: 수첩 포스트잇은 이 두 색 제한의 예외로, 탭별 종이색을 사용할 수 있다.** 색상은 `ManagementPresentation.BOOKMARK_COLORS`에서 공통 관리하고 포스트잇 글씨는 짙은 갈색으로 유지한다. 예외를 본문 버튼·입력란·아이콘으로 확대하지 않는다. 수첩의 종이 모양·좌우 이동·책장 넘김은 보존하고 일반 조작 스킨을 포스트잇에 적용하지 않는다. 개선할 화면/부품을 먼저 특정하고 대표 화면의 전후 비교부터 확인한다. 코드 검증만으로 디자인이 승인됐다고 판단하지 않는다.
