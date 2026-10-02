extends "res://dev/script/production_art_preview.gd"
func preview() -> void:
	super.preview()
	var id := "magic_oven" if OS.get_cmdline_user_args().has("--oven") else "drink_machine"
	for object in $ProductionRoom/Objects.get_children():
		if object is ProductionFacility and object.facility_id==id:
			$Actors/Player._show_facility_status(object)
			if OS.get_cmdline_user_args().has("--start"):
				if id=="drink_machine":
					GameState.add_item("raw_water",5)
					$Actors/Player.facility_recipe_picker.select(1)
					$Actors/Player._on_facility_recipe_selected(1)
				$Actors/Player._on_facility_start_pressed()
				assert(object.production_state==ProductionFacility.ProductionState.PROCESSING)
				if OS.get_cmdline_user_args().has("--ready"):
					object._process(10000)
					$Actors/Player._refresh_facility_dialog()
					assert(object.production_state==ProductionFacility.ProductionState.READY)
					if OS.get_cmdline_user_args().has("--collect"):
						$Actors/Player._on_facility_collect_pressed()
						assert(object.production_state==ProductionFacility.ProductionState.IDLE)
						print("WORKSHOP_COLLECT_OK")
			break
