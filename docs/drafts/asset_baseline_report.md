# 에셋 검증 리포트

## 요약 (규칙별)

| 규칙 | PASS | WARN | FAIL | 교체 대상(LEGACY) |
|---|---|---|---|---|
| actor | 0 | 0 | 12 | 0 |
| furniture | 0 | 0 | 12 | 0 |
| item-icon | 16 | 0 | 17 | 0 |
| legacy-characters | 0 | 0 | 0 | 6 |
| legacy-expedition | 0 | 0 | 0 | 9 |
| legacy-ui-reference | 0 | 0 | 0 | 12 |
| legacy-world | 0 | 0 | 0 | 41 |
| ui | 42 | 26 | 0 | 0 |
| **합계** | 58 | 26 | 41 | 68 |

## 누락된 아이콘 (19개)

- `amber_sap` → `art/items/pixel_v1/amber_sap.png` (추가 CSV)
- `bog_mud` → `art/items/pixel_v1/bog_mud.png` (추가 CSV)
- `coal` → `art/items/pixel_v1/coal.png` (추가 CSV)
- `copper_ore` → `art/items/pixel_v1/copper_ore.png` (추가 CSV)
- `deep_gem` → `art/items/pixel_v1/deep_gem.png` (추가 CSV)
- `dry_branch` → `art/items/pixel_v1/dry_branch.png` (추가 CSV)
- `elder_seed` → `art/items/pixel_v1/elder_seed.png` (추가 CSV)
- `forest_mushroom` → `art/items/pixel_v1/forest_mushroom.png` (추가 CSV)
- `glow_algae` → `art/items/pixel_v1/glow_algae.png` (추가 CSV)
- `marsh_reed` → `art/items/pixel_v1/marsh_reed.png` (추가 CSV)
- `queen_jelly` → `art/items/pixel_v1/queen_jelly.png` (추가 CSV)
- `rune_dust` → `art/items/pixel_v1/rune_dust.png` (추가 CSV)
- `rune_stone` → `art/items/pixel_v1/rune_stone.png` (추가 CSV)
- `sealed_scroll` → `art/items/pixel_v1/sealed_scroll.png` (추가 CSV)
- `silver_ore` → `art/items/pixel_v1/silver_ore.png` (추가 CSV)
- `stone_shard` → `art/items/pixel_v1/stone_shard.png` (추가 CSV)
- `toxic_spore` → `art/items/pixel_v1/toxic_spore.png` (추가 CSV)
- `wild_berry` → `art/items/pixel_v1/wild_berry.png` (추가 CSV)
- `worn_coin` → `art/items/pixel_v1/worn_coin.png` (추가 CSV)

## FAIL (41개)

- `art/items/bread.png` — 크기 128x128 (기대 64x64); 반투명 픽셀 303개 (안티앨리어싱 금지); 색 131개 (상한 32)
- `art/items/potion.png` — 크기 128x128 (기대 64x64); 반투명 픽셀 232개 (안티앨리어싱 금지); 색 133개 (상한 32)
- `art/items/water.png` — 크기 128x128 (기대 64x64); 반투명 픽셀 321개 (안티앨리어싱 금지)
- `art/items/expedition/ancient_fragment.png` — 색 142개 (상한 32)
- `art/items/expedition/ancient_relic.png` — 색 167개 (상한 32)
- `art/items/expedition/forest_herb.png` — 색 172개 (상한 32)
- `art/items/expedition/gathering_bottle.png` — 색 180개 (상한 32)
- `art/items/expedition/iron_ore.png` — 색 134개 (상한 32)
- `art/items/expedition/leather_armor.png` — 크기 131x137 (기대 64x64); 반투명 픽셀 765개 (안티앨리어싱 금지); 색 256개 (상한 32)
- `art/items/expedition/mine_crystal.png` — 색 187개 (상한 32)
- `art/items/expedition/raw_water.png` — 색 73개 (상한 32)
- `art/items/expedition/rusty_sword.png` — 크기 66x130 (기대 64x64); 색 206개 (상한 32)
- `art/items/expedition/sickle.png` — 크기 68x130 (기대 64x64); 반투명 픽셀 256개 (안티앨리어싱 금지); 색 180개 (상한 32)
- `art/items/expedition/swamp_moss.png` — 색 171개 (상한 32)
- `art/items/expedition/treasure_map.png` — 색 136개 (상한 32)
- `art/items/expedition/wheat.png` — 색 75개 (상한 32)
- `art/items/pixel_v1/treasure_map.png` — 색 912개 (상한 32)
- `art/furniture/pixel_v1/door.png` — 색 933개 (상한 48)
- `art/furniture/pixel_v1/drink_machine.png` — 반투명 픽셀 1274개 (안티앨리어싱 금지); 색 1034개 (상한 48)
- `art/furniture/pixel_v1/magic_oven.png` — 색 1598개 (상한 48)
- `art/furniture/pixel_v1/plant_small.png` — 반투명 픽셀 1412개 (안티앨리어싱 금지); 색 919개 (상한 48)
- `art/furniture/pixel_v1/production_door.png` — 색 979개 (상한 48)
- `art/furniture/pixel_v1/register.png` — 반투명 픽셀 27개 (안티앨리어싱 금지); 색 550개 (상한 48)
- `art/furniture/pixel_v1/shelf_1x1.png` — 색 1056개 (상한 48)
- `art/furniture/pixel_v1/shelf_2x1.png` — 색 925개 (상한 48)
- `art/furniture/pixel_v1/shelf_3x1.png` — 색 348개 (상한 48)
- `art/furniture/pixel_v1/wall_poster.png` — 반투명 픽셀 1859개 (안티앨리어싱 금지); 색 1015개 (상한 48)
- `art/furniture/pixel_v1/warehouse_door.png` — 반투명 픽셀 1576개 (안티앨리어싱 금지); 색 1059개 (상한 48)
- `art/furniture/pixel_v1/warehouse_rack.png` — 색 1228개 (상한 48)
- `art/player/generated/v3/down.png` — 색 832개 (상한 48)
- `art/player/generated/v3/down_left.png` — 색 845개 (상한 48)
- `art/player/generated/v3/down_right.png` — 색 844개 (상한 48)
- `art/player/generated/v3/download.png` — 반투명 픽셀 4202개 (안티앨리어싱 금지); 색 2960개 (상한 48)
- `art/player/generated/v3/left.png` — 색 751개 (상한 48)
- `art/player/generated/v3/player_idle_8dir_aligned_v3.png` — 색 4893개 (상한 48)
- `art/player/generated/v3/player_idle_8dir_aligned_v3_preview.png` — 색 4893개 (상한 48)
- `art/player/generated/v3/player_idle_8dir_pixel_source_v3.png` — 반투명 픽셀 592051개 (안티앨리어싱 금지); 색 86172개 (상한 48)
- `art/player/generated/v3/right.png` — 색 729개 (상한 48)
- `art/player/generated/v3/up.png` — 색 855개 (상한 48)
- `art/player/generated/v3/up_left.png` — 색 858개 (상한 48)
- `art/player/generated/v3/up_right.png` — 색 909개 (상한 48)

## WARN (26개)

- `art/ui/pixel_theme/arrow_down.png` — 크기 12x12 는 8의 배수가 아님
- `art/ui/pixel_theme/arrow_down_disabled.png` — 크기 12x12 는 8의 배수가 아님
- `art/ui/pixel_theme/arrow_left.png` — 크기 12x12 는 8의 배수가 아님
- `art/ui/pixel_theme/arrow_right.png` — 크기 12x12 는 8의 배수가 아님
- `art/ui/pixel_theme/arrow_up.png` — 크기 12x12 는 8의 배수가 아님
- `art/ui/pixel_theme/hscroll_grabber.png` — 크기 16x10 는 8의 배수가 아님
- `art/ui/pixel_theme/hscroll_grabber_hover.png` — 크기 16x10 는 8의 배수가 아님
- `art/ui/pixel_theme/hscroll_grabber_pressed.png` — 크기 16x10 는 8의 배수가 아님
- `art/ui/pixel_theme/hscroll_track.png` — 크기 16x10 는 8의 배수가 아님
- `art/ui/pixel_theme/hseparator.png` — 크기 16x4 는 8의 배수가 아님
- `art/ui/pixel_theme/open_shop_slot_disabled.png` — 크기 160x54 는 8의 배수가 아님
- `art/ui/pixel_theme/open_shop_slot_hover.png` — 크기 160x54 는 8의 배수가 아님
- `art/ui/pixel_theme/open_shop_slot_normal.png` — 크기 160x54 는 8의 배수가 아님
- `art/ui/pixel_theme/open_shop_slot_pressed.png` — 크기 160x54 는 8의 배수가 아님
- `art/ui/pixel_theme/progress_bg.png` — 크기 32x10 는 8의 배수가 아님
- `art/ui/pixel_theme/progress_fill.png` — 크기 32x10 는 8의 배수가 아님
- `art/ui/pixel_theme/spin_updown.png` — 크기 12x20 는 8의 배수가 아님
- `art/ui/pixel_theme/toggle_off.png` — 크기 24x14 는 8의 배수가 아님
- `art/ui/pixel_theme/toggle_off_disabled.png` — 크기 24x14 는 8의 배수가 아님
- `art/ui/pixel_theme/toggle_on.png` — 크기 24x14 는 8의 배수가 아님
- `art/ui/pixel_theme/toggle_on_disabled.png` — 크기 24x14 는 8의 배수가 아님
- `art/ui/pixel_theme/vscroll_grabber.png` — 크기 10x16 는 8의 배수가 아님
- `art/ui/pixel_theme/vscroll_grabber_hover.png` — 크기 10x16 는 8의 배수가 아님
- `art/ui/pixel_theme/vscroll_grabber_pressed.png` — 크기 10x16 는 8의 배수가 아님
- `art/ui/pixel_theme/vscroll_track.png` — 크기 10x16 는 8의 배수가 아님
- `art/ui/pixel_theme/vseparator.png` — 크기 4x16 는 8의 배수가 아님

## 버전 폴더 (15개) — 버전 관리는 git 으로 대체 권장

- `art/characters/cozy_v1/`
- `art/furniture/pixel_v1/`
- `art/items/pixel_v1/`
- `art/player/generated/v3/`
- `art/world/blacksmith_v2/`
- `art/world/cozy_v10/`
- `art/world/houses_v1/`
- `art/world/market_stalls_v3/`
- `art/world/plaza_props_v1/`
- `art/world/route_props_v1/`
- `art/world/tool_shop_v1/`
- `art/world/village_buildings_v1/`
- `art/world/village_decor_v6/`
- `art/world/village_gathering_v1/`
- `art/world/village_houses_v2/`
