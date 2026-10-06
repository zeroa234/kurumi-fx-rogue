extends Node
## 启动：进入标题画面。

func _ready() -> void:
	Game.goto("res://src/scenes/title.tscn")
