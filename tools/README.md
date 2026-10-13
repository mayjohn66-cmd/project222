# tools/ — 도구 (목적별 5개 폴더, 2026-10-12 정리)

사용법은 각 파일 맨 위 설명. 모두 저장소 맨 위(루트) 폴더에서 실행한다. 예: `python tools/balance/balance_baseline.py .`

```
tools/
├─ balance/   # 밸런스 점검(읽기 전용): 가격·수요·강화·원정 보상
│  balance_baseline · check_pricing(가격 단계 기대 수익) · check_economy · check_demand · check_arrival · check_enhancement · check_equipment
│  check_map_supply · check_merchant · recipe_prices · review_content_economy · build_scroll_drops · build_draft
├─ story/     # 이야기: export_story_bundle(제미나이 검수용 묶음) · export_story_full · export_story_text
│  merge_story_csv(검수 결과 합치기, 먼저 점검만) · audit_completion(콘텐츠 완료 조건 점검표 생성) · validate_story · audit_story · export_rewrite_prompts
├─ code/      # 코드 점검: unused_scan(안 쓰는 코드 후보) · dynamic_call_check · ui_text_scan · docs_check
│  check_godot.tscn(모든 .gd·.tscn 로드 검사) · check_expedition_run.tscn(원정 한 판 검사)
├─ art/       # 그림 가공·설치·검증: prepare_* · install_* · iso_* · normalize_* · ingest_world3d · pixellab_batch
│  sprite_normal · height_to_normal · upscale_icon · fix_texture_import · compose_mock_scene · preview_tiles
│  audit_active_sprite_links · build_art_request_doc · validate_assets · world3d_menu.py · run_world3d.bat
├─ release/   # 배포: build_windows.ps1 · write_engine_licenses.gd
└─ where.bat  # 이 폴더의 git 상태를 한 화면으로 보여 줌(PC에서 더블클릭, 읽기 전용)
```

- Godot로 돌리는 도구: `godot --headless --path . res://tools/code/check_godot.tscn`
- 비밀(API 키·토큰)은 파일에 쓰지 않고 환경변수로만 준다(예: `PIXELLAB_TOKEN`).
- 이 폴더는 게임에 포함되지 않는다(`export_presets.cfg`에서 제외, `.gdignore`).
