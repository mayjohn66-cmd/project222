# art/ — 게임이 쓰는 그림 (PNG 약 2,000장)

그림 담당(ChatGPT·사용자)의 영역. 코드 담당은 그림을 직접 만들거나 지우지 않는다(삭제는 계획·승인 뒤). 규격은 `docs/에셋_규격서_초안.md`, 검사는 `python tools/art/validate_assets.py`.

```
art/
├─ actors/      # 인물·몬스터 움직임(1,068장, 가장 많음)
├─ received/    # 받은 그림 중 게임에 연결된 것(674장): 마을·가구·환경
├─ items/       # 아이템 아이콘(91)
├─ ui/          # 화면 조각(78)
├─ npc/         # NPC 초상화·표정(51)
├─ world3d/     # 3D 건물·소품 질감(16)
├─ furniture/ portraits/(player) characters/ expedition/ world/ fonts/
```
그림 원본·작업 기록은 `docs/그림_작업/`(게임에는 들어가지 않음).
