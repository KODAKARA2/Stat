extends Node
## 개발용: godot --path . -- --shot=경로.png [--wait=프레임] [--click=x,y] [--pause=프레임] ...
## --click / --pause는 적은 순서대로 실행한다(클릭은 실제 입력과 같은 경로).
## 지정 프레임 뒤 화면을 PNG로 저장하고 종료. 인자가 없으면 아무것도 안 함.

func _ready() -> void:
	var shot_path: String = ""
	var wait_frames: int = 10
	var steps: Array = []   # [["click", Vector2] | ["pause", 프레임]]
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--wait="):
			wait_frames = int(arg.trim_prefix("--wait="))
		elif arg.begins_with("--click="):
			var xy: PackedStringArray = arg.trim_prefix("--click=").split(",")
			steps.append(["click", Vector2(float(xy[0]), float(xy[1]))])
		elif arg.begins_with("--rclick="):
			var rxy: PackedStringArray = arg.trim_prefix("--rclick=").split(",")
			steps.append(["rclick", Vector2(float(rxy[0]), float(rxy[1]))])
		elif arg.begins_with("--pause="):
			steps.append(["pause", int(arg.trim_prefix("--pause="))])
	if shot_path == "":
		queue_free()
		return
	for i: int in wait_frames:
		await get_tree().process_frame
	for step: Array in steps:
		if step[0] == "pause":
			for i: int in int(step[1]):
				await get_tree().process_frame
			continue
		for pressed: bool in [true, false]:
			var ev: InputEventMouseButton = InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_RIGHT if step[0] == "rclick" else MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.position = step[1]
			ev.global_position = step[1]
			Input.parse_input_event(ev)
			await get_tree().process_frame
		for i: int in 5:
			await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_path)
	print("screenshot: ", shot_path)
	get_tree().quit()
