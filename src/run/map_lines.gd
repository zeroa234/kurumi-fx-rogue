class_name MapLines
extends Control
## 画地图节点之间的连线（像素点线）。

var run: RunState
var pos_fn: Callable

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if run == null:
		return
	var avail := run.available()
	for row in run.map:
		for n in row:
			var a: Vector2 = pos_fn.call(n)
			for nid in n.next:
				var m := run.node(nid)
				var b: Vector2 = pos_fn.call(m)
				var col := Color(0.42, 0.36, 0.58, 0.8)
				if n.done and (m.done or avail.has(nid)):
					col = Color(1.0, 0.44, 0.65, 0.9) if m.done or n.id == run.current else col
				_dotted(a + Vector2(8, 0), b - Vector2(8, 0), col)

func _dotted(a: Vector2, b: Vector2, col: Color) -> void:
	var d := a.distance_to(b)
	var steps := int(d / 3.0)
	for i in steps:
		var p := a.lerp(b, float(i) / maxf(1.0, steps)).floor()
		draw_rect(Rect2(p, Vector2(1, 1)), col)
