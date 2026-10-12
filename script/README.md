# script/ — 게임 코드

> 폴더 지도(2026-10-12). 전체 구조 설명과 정리 계획은 [docs/구조_정리안.md](../docs/구조_정리안.md). 새 기능은 기존 큰 파일(`expedition.gd`, `game_state.gd`, `build_manager.gd`, `worker.gd`, `day_manager.gd`)에 덧붙이지 말고 새 파일로 만든다.

```
script/
├─ core/        # 설정·저장·전체 상태(GameState). 가장 먼저 읽는 곳
├─ data/        # CSV를 읽어 오는 데이터 접근(ItemData 등). shop · expedition · production · shared · story
├─ actor/       # 움직이는 인물: 손님, 직원, 플레이어, 마을 주민, 안내 손님
├─ build/       # 가구 건축(설치·이동·미리보기)
├─ objects/     # 설치되는 물건(계산대·진열대·문·생산 설비)
├─ inventory/   # 가방·창고 격자 모델
├─ expedition/  # 원정: rooms(방) · services(가방·전투 등) · contacts(길 위의 만남) · view3d
├─ ui/          # 화면: management(관리 책) · shop · expedition · common · style
└─ world/       # 가게·마을 세계
   ├─ view3d/   #   3D 화면(등각 렌더링)
   ├─ warehouse/ production/ shape/ shared/
   └─ shop/     #   가게 운영·이야기·마을(README 참고)
```

## 이름 규칙
- `*_director` = 화면·입력 담당(말풍선, E키), `*_flow` = 진행 규칙과 기록, `*_settings` = 수치, `*_data` = CSV 읽기.
- 이름에 id가 들어 있는 CSV·씬은 `data/`, `scenes/`에서 같은 단어로 찾는다.
