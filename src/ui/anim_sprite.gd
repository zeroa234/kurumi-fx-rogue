class_name AnimSprite
extends TextureRect
## 横向精灵表循环播放（如 Blender 渲染的旋转金币 assets/sprites/anim/coin.png）。

var frames: Array[Texture2D] = []
var fps := 10.0
var _t := 0.0
var _i := 0

static func make(sheet_path: String, frame_w: int, frame_fps := 10.0) -> AnimSprite:
	var a := AnimSprite.new()
	a.fps = frame_fps
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	var sheet: Texture2D = UI.tex(sheet_path)
	if sheet:
		var n := int(sheet.get_width() / frame_w)
		for i in n:
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(i * frame_w, 0, frame_w, sheet.get_height())
			a.frames.append(at)
		a.custom_minimum_size = Vector2(frame_w, sheet.get_height())
	else:
		a.frames.append(PixelIcons.get_icon("coin", 2))
		a.custom_minimum_size = Vector2(16, 16)
	a.texture = a.frames[0]
	return a

func _process(delta: float) -> void:
	if frames.size() <= 1:
		return
	_t += delta
	if _t >= 1.0 / fps:
		_t = 0.0
		_i = (_i + 1) % frames.size()
		texture = frames[_i]
