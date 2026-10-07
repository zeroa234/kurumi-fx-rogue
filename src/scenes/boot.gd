extends Node
## 启动：首次启动（或设置了每次播放）先放开场 PV，然后进标题画面。

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# 调试参数 --scene= 已由 Game 安排跳转，这里再 goto 标题会把它盖掉
	for a in args:
		if a.begins_with("--scene="):
			return
	# 带任何调试参数（截图等）启动时不播开场
	if args.is_empty() and Opening.should_autoplay():
		Game.goto(Opening.SCENE, {"gate": OS.has_feature("web")})
	else:
		Game.goto("res://src/scenes/title.tscn")
