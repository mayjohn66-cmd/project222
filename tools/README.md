# tools/ — 도구 (파이썬·스크립트, 58개)

> 지금은 한 층에 섞여 있다. 목적별 정리 계획은 [docs/구조_정리안.md](../docs/구조_정리안.md) 5-3. 사용법은 각 파일 맨 위 설명.

| 목적 | 도구 |
|---|---|
| 밸런스 점검 | `balance_baseline` · `check_economy` · `check_demand` · `check_enhancement` · `check_equipment` · `check_arrival` · `check_map_supply` · `check_merchant` · `recipe_prices` · `review_content_economy` · `build_scroll_drops` · `build_draft` |
| 이야기 | `export_story_bundle`(제미나이 검수용 묶음) · `export_story_full` · `export_story_text` · `merge_story_csv`(검수 결과 합치기, 먼저 점검만) · `validate_story` · `audit_story` · `export_rewrite_prompts` |
| 코드 점검 | `unused_scan`(안 쓰는 코드 후보) · `dynamic_call_check` · `ui_text_scan` · `docs_check` · `check_godot` · `check_expedition_run` |
| 그림 가공·설치 | `prepare_*` · `install_*` · `iso_*` · `normalize_*` · `ingest_world3d` · `pixellab_batch` · `sprite_normal` · `height_to_normal` · `upscale_icon` · `fix_texture_import` · `compose_mock_scene` · `preview_tiles` · `audit_active_sprite_links` · `build_art_request_doc` |
| 검증·배포 | `validate_assets` · `build_windows.ps1` · `write_engine_licenses` |

비밀(API 키·토큰)은 파일에 쓰지 않고 환경변수로만 준다(예: `PIXELLAB_TOKEN`).
