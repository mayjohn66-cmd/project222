class_name ExpeditionExitPath
extends RefCounted
## 출구를 지면 위에 이어지는 길로 표시한다. 실제 이동 판정의 좌표를 기준으로 놓는다.
const SHADER := preload("res://script/expedition/view3d/expedition_exit_path.gdshader")

static func build(stage: ExpeditionStage3D, model: RefCounted) -> void:
	var region := str(stage._backdrop.get_meta("region_id",stage.view.region_id))
	var profile := ExpeditionRoomComposition.profile(region)
	var style: Dictionary = profile.get("exit_path",{})
	var kind := str(style.get("kind","dirt"))
	var length := float(style.get("length",3.5))
	var width := float(style.get("width",1.3))
	var inside := float(style.get("inside",0.75))
	var at: Vector2 = model.exit_position
	for opened in [false,true]:
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(width + 0.3,length)
		var material := ShaderMaterial.new()
		material.shader = SHADER
		for i in range(1,4):
			var texture := ReceivedWorldArt.texture("res://art/received/floors/%s_%d.png" % [kind,i])
			material.set_shader_parameter("tile_%d" % i,texture)
			material.set_shader_parameter("normal_%d" % i,SpriteNormalMaps.texture(texture))
		material.set_shader_parameter("exit_position",at)
		material.set_shader_parameter("path_width",width)
		material.set_shader_parameter("path_length",length)
		material.set_shader_parameter("inside_length",inside)
		material.set_shader_parameter("straight_edges",kind == "wood")
		material.set_shader_parameter("opened",1.0 if opened else 0.0)
		var tint := Color(str(style.get("tint",profile.get("floor_tint","ffffff"))))
		tint = ExpeditionEnvironment.floor_tint(tint,stage.view.weather_overlay.environment,str(stage._theme.floor) == "grass")
		material.set_shader_parameter("tint",tint)
		var node := MeshInstance3D.new()
		node.name = "OpenExitPath" if opened else "UnsafeExitPath"
		node.mesh = mesh
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = Vector3(at.x,0.025,at.y + inside - length * 0.5)
		node.set_meta("exit_path_region",region)
		node.set_meta("exit_path_kind",kind)
		node.set_meta("exit_trigger_position",at)
		node.set_meta("exit_path_opened",opened)
		stage._content.add_child(node)
		if opened: stage._exit_glow = node
		else: stage._exit_bars = node
	if stage._theme_id in ["mine","hidden_ruins"]:
		for side in [-1.0,1.0]:
			stage._add_torch(Vector3(at.x + side * (width * 0.5 + 0.35),0.4,at.y - 0.65))
