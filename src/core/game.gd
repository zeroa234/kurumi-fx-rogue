extends Node
## 全局：场景切换与跨场景参数。

var params := {}
var run: RunState = null # 当前肉鸽局（RunState）

func _ready() -> void:
	# 调试：-- --shot=res路径/或绝对路径 --shot-delay=秒 [--scene=res://...] 截图后退出
	var args := OS.get_cmdline_user_args()
	var shot := ""
	var delay := 3.0
	for a in args:
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--shot-delay="):
			delay = float(a.substr(13))
		elif a.begins_with("--scene="):
			goto(a.substr(8), params)
		elif a.begins_with("--chapter="):
			params["chapter"] = a.substr(10)
		elif a.begins_with("--scene-index="):
			params["scene_index"] = int(a.substr(14))
	if shot != "":
		_take_shot(shot, delay)

func _take_shot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)
	get_tree().quit()

func goto(scene: String, p := {}) -> void:
	params = p
	get_tree().call_deferred("change_scene_to_file", scene)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
