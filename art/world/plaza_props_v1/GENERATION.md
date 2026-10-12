# Plaza props v1

The three transparent pixel-art assets were created with ImageGen from the
merchant-stall and wooden-cart references supplied for the village square.

- `herb_stall_roof_diamond_v6.png`: in-game blue-and-cream herb stall. The
  canopy top is a true 2:1 isometric parallelogram, with both edge directions
  parallel to the lower base. The rear post cap follows its new corner; the
  lower display and feet retain their previous pixels. Canopy plane corners
  in the 1536x1152 sprite are (365,386), (815,161), (1159,333), (709,558);
  its edge slopes are -0.5 and +0.5.
- `herb_stall_flat_roof_v5.png`: source for v6 and previous canopy edit.
- `herb_stall_tile_aligned_v4.png`: tile-aligned base and source for v5. One
  straight affine projection aligns the post feet and counter base to both
  96x48 tile axes. It is baked from `herb_stall_tile_aligned_v2.png`.
- `supply_cart_tile_aligned_v3.png`: in-game two-wheel timber supply cart.
  One straight affine projection aligns its chassis axes and is baked from
  `supply_cart.png`.
- `plaza_crates.png`: low crates, barrel and flowering herb pot.

Placement, uniform display scales, sprite anchors and collision footprints are
defined in `script/world/shop/village_decor.gd`. Cell offsets from the square
are defined in `script/world/shop/exterior/store_exterior.gd`. The reproducible geometry
bake is `dev/script/bake_plaza_sprites.gd`. The roof edits build on
that baked v4 base; v6 is loaded during gameplay.

## Herb stall v2

Created with the built-in ImageGen editor using the existing tile-aligned
orange market stall as the camera/geometry reference and the first blue herb
stall as the content reference. The final request was:

> Rebuild the blue-and-cream herb shop as a standalone transparent pixel-art
> sprite with the same 2:1 isometric projection, scale and footprint as the
> orange market stall. The canopy, counter, beams and post bases must follow
> screen slopes +1/2 and -1/2. Keep the herb jars, purple herbs, leaves and
> timber; keep the canopy a regular isometric parallelogram. No terrain,
> guides, text, opaque backdrop, or ground shadow. Avoid stretching.
