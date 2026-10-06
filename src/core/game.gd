extends Node
## 全局：场景切换与跨场景参数。

var params := {}
var run: RunState = null # 当前肉鸽局（RunState）

func goto(scene: String, p := {}) -> void:
	params = p
	get_tree().call_deferred("change_scene_to_file", scene)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
