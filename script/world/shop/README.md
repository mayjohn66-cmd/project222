# script/world/shop/ — 가게·이야기·마을 (가장 큰 폴더, 156개)

> 지도(2026-10-12). 이 폴더 직속 29개 파일은 운영·마을·바깥·이야기가 섞여 있어 정리 대상이다(정리안 5-1). 아직 옮기지 않았다.

```
shop/
├─ requests/      # 이야기·부탁 전부(73개): 주민·마을·단골·날씨·4막·등불 길손·손님 입장 방식 (requests/README.md)
├─ tutorial/      # 프롤로그와 튜토리얼: 도입 연출, 청소, 안내 단계(재고 소진 → 타블렌의 부탁)
├─ fishing/       # 낚시: 어종·장소·요리, 첫 판매
├─ preservation/  # 계절 재료의 보존(냉장·냉동·말리기) 수업
├─ blacksmith/    # 대장간: 장비 제작·강화와 진행
├─ employees/     # 직원 고용·교육·이야기
├─ power/         # 꺼진 계산대의 전원 복구(마석 발전기)
├─ events/        # 매장 행사(소문 → 진열대)
├─ progression/   # 가게 공간 확장 진행
└─ (직속 29개)
   ├─ 운영:  day_manager, shop_stock, shop_speed_controller, offline_shop_simulator, manual_checkout_controller, register_product_overview, checkout_tutorial, world_interactions
   ├─ 이야기: story_director, story_conditions, secret_merchant_director, npc_intervention_selector
   ├─ 마을:  village_art, village_buildings, village_decor, village_extra_houses, village_blacksmith, village_tool_shop, village_gathering, village_map_editor, nearby_houses
   └─ 바깥:  store_exterior, boundary_segment, floor, wood_walls, dungeon_roadside, dungeon_wall, tile_grid_overlay, day_night_tint
```
