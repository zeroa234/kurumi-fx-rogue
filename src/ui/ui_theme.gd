extends Node
## 全局像素主题与配色。所有界面通过 UI.xxx 取颜色与工厂方法。

const FONT_PATH := "res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.otf.woff2"

var BG := Color("1b1528")
var PANEL := Color("261d3a")
var PANEL2 := Color("31264b")
var BORDER := Color("5b4a85")
var BORDER_HI := Color("9b86d6")
var TEXT := Color("f4ecff")
var DIM := Color("a89cc8")
var MUTED := Color("6e6290")
var PINK := Color("ff6fa5")
var YELLOW := Color("ffd166")
var CYAN := Color("5ad1e8")
var ORANGE := Color("ff9f43")
var WHITE := Color("ffffff")
var UP := Color("ff5d73")    # 红涨（中文习惯）
var DOWN := Color("3ddc97")  # 绿跌
var GRID := Color("2e2447")

var font: Font
var theme: Theme

func _ready() -> void:
	_apply_colors()
	font = load(FONT_PATH)
	if font is FontFile:
		var ff: FontFile = font
		ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		ff.hinting = TextServer.HINTING_NONE
		ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	theme = _build_theme()
	get_tree().root.theme = theme

func _apply_colors() -> void:
	# 国际配色：绿涨红跌
	if Save.setting("green_up", false):
		var t := UP
		UP = DOWN
		DOWN = t

func up_down(v: float) -> Color:
	if v > 0.0:
		return UP
	if v < 0.0:
		return DOWN
	return TEXT

func box(bg: Color, border: Color = BORDER, bw := 1, pad := 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(pad)
	s.anti_aliasing = false
	return s

func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 12
	# Label
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("line_spacing", "Label", 1)
	# Button
	t.set_stylebox("normal", "Button", box(PANEL2, BORDER, 1, 3))
	t.set_stylebox("hover", "Button", box(Color("3d3060"), BORDER_HI, 1, 3))
	t.set_stylebox("pressed", "Button", box(Color("4a3a75"), PINK, 1, 3))
	t.set_stylebox("disabled", "Button", box(Color("201830"), Color("3a3055"), 1, 3))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), BORDER_HI, 1, 3))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", WHITE)
	t.set_color("font_pressed_color", "Button", YELLOW)
	t.set_color("font_disabled_color", "Button", MUTED)
	# Panel / PanelContainer
	t.set_stylebox("panel", "Panel", box(PANEL, BORDER, 1, 3))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, BORDER, 1, 3))
	# LineEdit / SpinBox
	t.set_stylebox("normal", "LineEdit", box(Color("150f22"), BORDER, 1, 2))
	t.set_stylebox("focus", "LineEdit", box(Color("150f22"), BORDER_HI, 1, 2))
	t.set_color("font_color", "LineEdit", TEXT)
	# ScrollContainer / ItemList / RichText
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font)
	t.set_font("bold_font", "RichTextLabel", font)
	t.set_font_size("normal_font_size", "RichTextLabel", 12)
	t.set_font_size("bold_font_size", "RichTextLabel", 12)
	t.set_constant("line_separation", "RichTextLabel", 1)
	# Tooltip
	t.set_stylebox("panel", "TooltipPanel", box(Color("120c1e"), BORDER_HI, 1, 3))
	t.set_color("font_color", "TooltipLabel", TEXT)
	# 滚动条细一点
	var sb := box(Color("1f1830"), Color("1f1830"), 0, 0)
	var gr := box(BORDER, BORDER, 0, 0)
	for n in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", n, sb)
		t.set_stylebox("grabber", n, gr)
		t.set_stylebox("grabber_highlight", n, box(BORDER_HI, BORDER_HI, 0, 0))
		t.set_stylebox("grabber_pressed", n, box(PINK, PINK, 0, 0))
	# OptionButton / PopupMenu
	t.set_stylebox("panel", "PopupMenu", box(Color("150f22"), BORDER_HI, 1, 2))
	t.set_stylebox("normal", "OptionButton", box(PANEL2, BORDER, 1, 3))
	t.set_stylebox("hover", "OptionButton", box(Color("3d3060"), BORDER_HI, 1, 3))
	t.set_stylebox("pressed", "OptionButton", box(Color("4a3a75"), PINK, 1, 3))
	# TabBar
	t.set_stylebox("tab_selected", "TabBar", box(PANEL2, BORDER_HI, 1, 2))
	t.set_stylebox("tab_unselected", "TabBar", box(PANEL, BORDER, 1, 2))
	t.set_stylebox("tab_hovered", "TabBar", box(Color("3d3060"), BORDER_HI, 1, 2))
	t.set_color("font_selected_color", "TabBar", YELLOW)
	t.set_color("font_unselected_color", "TabBar", DIM)
	# ProgressBar
	t.set_stylebox("background", "ProgressBar", box(Color("150f22"), BORDER, 1, 0))
	t.set_stylebox("fill", "ProgressBar", box(PINK, PINK, 0, 0))
	return t

# ---------------------------------------------------------------- 工厂

func label(text: String, color: Color = TEXT, size := 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if size != 12:
		l.add_theme_font_size_override("font_size", size)
	return l

func button(text: String, cb: Callable = Callable(), min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	if cb.is_valid():
		b.pressed.connect(cb)
	b.pressed.connect(func(): Sfx.play("click"))
	return b

func panel(bg: Color = PANEL, border: Color = BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border, 1, 3))
	return p

func hbox(sep := 2) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

func vbox(sep := 2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

func rich(bb := "") -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bb
	r.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	return r

func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

## 居中弹窗：返回内容 VBox；UI.close_modal(vbox) 关闭
func modal(parent: Node, border: Color = BORDER_HI, width := 380, dim_alpha := 0.55) -> VBoxContainer:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, dim_alpha)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color("201838"), border, 1, 6))
	root.add_child(p)
	var v := vbox(6)
	v.custom_minimum_size.x = width
	p.add_child(v)
	v.set_meta("root", root)
	p.resized.connect(func(): p.position = ((Vector2(640, 360) - p.size) / 2.0).floor())
	return v

func close_modal(v: Control) -> void:
	if is_instance_valid(v) and v.has_meta("root"):
		v.get_meta("root").queue_free()

## 图标：优先 assets/sprites/icons/<id>.png，没有则用像素占位
func icon(id: String, fallback := "star") -> Texture2D:
	var t := tex("res://assets/sprites/icons/%s.png" % id)
	if t:
		return t
	return PixelIcons.get_icon(fallback, 3)

func hex(c: Color) -> String:
	return c.to_html(false)

func tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null
