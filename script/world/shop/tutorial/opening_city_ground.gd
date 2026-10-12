class_name OpeningCityGround
extends RefCounted
## 실제 바닥 셰이더의 텍스처와 색을 저장해 도시 포장/숲 복원을 처리한다.
static func apply(view: StoreView3D, saved: Dictionary, city: bool) -> void:
	if view.village == null: return
	for kind in view.village._ground:
		var material: ShaderMaterial = view.village._ground[kind].material
		var previous: Dictionary = saved.get(kind,{})
		if city:
			var names: Array[String] = []
			for uniform in material.shader.get_shader_uniform_list(): names.append(str(uniform.name))
			if previous.is_empty() or previous.material != material:
				var parameters: Dictionary = {}
				for name in names:
					if name in ["albedo_tex","normal_tex","tint"] or name.begins_with("tile_") or name.begins_with("normal_"):
						parameters[name] = material.get_shader_parameter(name)
				saved[kind] = {"material":material,"parameters":parameters}
			for index in range(1,4):
				var tex := ReceivedWorldArt.texture("res://art/received/floors/paving_%d.png" % index)
				if "tile_%d" % index in names: material.set_shader_parameter("tile_%d" % index,tex)
				if "normal_%d" % index in names: material.set_shader_parameter("normal_%d" % index,SpriteNormalMaps.texture(tex))
			if "albedo_tex" in names: material.set_shader_parameter("albedo_tex",ReceivedWorldArt.texture("res://art/received/floors/paving_1.png"))
			if "normal_tex" in names: material.set_shader_parameter("normal_tex",SpriteNormalMaps.texture(ReceivedWorldArt.texture("res://art/received/floors/paving_1.png")))
			if "tint" in names: material.set_shader_parameter("tint",Color.WHITE)
		elif not previous.is_empty() and previous.material == material:
			for name in previous.parameters: material.set_shader_parameter(name,previous.parameters[name])
	if not city: saved.clear()
