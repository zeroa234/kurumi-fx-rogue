extends Node
## 肉鸽结算画面布局：每种结局（通关/未达目标/心折/资金耗尽/放弃）弹窗都要完整落在 640×360 内，按钮可见。
## 结算会写存档（相場勘点数），结束时还原本机存档文件。可选 `-- --shots=<绝对目录>` 每种结局存一张截图。

const SCENE := "res://src/run/run_result.tscn"
var _backup = null # 原存档文本；null = 原本没有存档
var _fails := 0

func _ready() -> void:
	if FileAccess.file_exists(Save.PATH):
		_backup = FileAccess.get_file_as_string(Save.PATH)
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	for reason in ["victory", "target", "broken", "bankrupt", "abandon"]:
		Save.data = Save._default()
		var r := RunState.create({"broker": "overseas", "friends": [], "seed": 777})
		r.ended = true
		r.end_reason = reason
		Game.run = r
		var s: Control = load(SCENE).instantiate()
		add_child(s)
		for i in 4:
			await get_tree().process_frame
		_check_layout(s, reason)
		if shots != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots.path_join("result_%s.png" % reason))
		s.queue_free()
		await get_tree().process_frame
	if _backup == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.PATH))
	else:
		var f := FileAccess.open(Save.PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	Save.load_save()
	print("RESULT CHECK: %d failures" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _check_layout(s: Control, reason: String) -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(640, 360))
	var panels := s.find_children("*", "PanelContainer", true, false)
	if panels.is_empty():
		_fail(reason, "没有弹窗")
		return
	var p: Control = panels[0]
	var rect := p.get_global_rect()
	if not screen.encloses(rect):
		_fail(reason, "弹窗超出屏幕 %s" % rect)
	for b in p.find_children("*", "Button", true, false):
		if not screen.encloses((b as Control).get_global_rect()):
			_fail(reason, "按钮「%s」在屏幕外 %s" % [b.text, b.get_global_rect()])
	print("  %s: 弹窗 %s" % [reason, rect])

func _fail(reason: String, msg: String) -> void:
	_fails += 1
	printerr("FAIL %s: %s" % [reason, msg])
