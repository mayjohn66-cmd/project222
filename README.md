# 편의점 게임 (project222)

편의점 경영(진열·계산·직원·가구 건축·상품 제작)과 재료를 구하는 판타지 원정을 합친 Godot 4 게임.

- 문서 길잡이: [`docs/README.md`](docs/README.md)
- 작업 지침: [`CLAUDE.md`](CLAUDE.md), 협업 규칙: [`docs/AI_협업_규칙.md`](docs/AI_협업_규칙.md)
- 게임 수치는 `data/` 아래 CSV에 있다.

## 검증 명령

```
python tools/balance/balance_baseline.py .
python tools/art/validate_assets.py . --extra-items docs/drafts/items_materials_draft.csv
```

(`validate_assets.py`는 Pillow가 필요하다: `pip install pillow`)
