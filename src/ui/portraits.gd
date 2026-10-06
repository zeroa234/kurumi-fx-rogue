class_name Portraits
extends RefCounted
## 立绘加载：assets/sprites/portraits/<char>_<face>.png（128）与 portraits_small/（64）。
## 缺图时退回 <char>_normal，再缺就画一个占位剪影（发色来自 characters.json）。

static var _cache := {}

static func big(who: String, face := "normal") -> Texture2D:
	return _load_tex("res://assets/sprites/portraits/", who, face, 128)

static func small(who: String, face := "normal") -> Texture2D:
	return _load_tex("res://assets/sprites/portraits_small/", who, face, 64)

static func _load_tex(dir: String, who: String, face: String, sz: int) -> Texture2D:
	var key := "%s%s_%s" % [dir, who, face]
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	for f in [face, "normal"]:
		var p := "%s%s_%s.png" % [dir, who, f]
		if ResourceLoader.exists(p):
			tex = load(p)
			break
	if tex == null:
		tex = _placeholder(who, face, sz)
	_cache[key] = tex
	return tex

static func info(who: String) -> Dictionary:
	return DB.get_json("res://data/story/characters.json").get("characters", {}).get(who, {"name": who, "color": "a89cc8", "hair": "777777"})

static func _placeholder(who: String, face: String, sz: int) -> Texture2D:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var hair := Color(String(info(who).get("hair", "777777")))
	var skin := Color("ffe0d0")
	var s := float(sz) / 64.0
	var c := Vector2(32, 30) * s
	# 头发（后）
	_disc(img, c + Vector2(0, 2) * s, 22 * s, hair)
	# 身体
	for y in range(int(48 * s), sz):
		for x in range(int(12 * s), int(52 * s)):
			img.set_pixel(x, y, Color("f4ecff") if who == "kurumi" else hair.darkened(0.3))
	# 脸
	_disc(img, c + Vector2(0, 4) * s, 15 * s, skin)
	# 刘海
	for y in range(int(12 * s), int(24 * s)):
		for x in range(int(16 * s), int(48 * s)):
			if (x + y) % 7 != 0:
				img.set_pixel(x, y, hair)
	# 眼睛
	var eye := Color("e0457b") if who == "kurumi" else Color("2a2040")
	var ey := int(30 * s)
	if face in ["cry", "sleep"]:
		for dx in range(-3, 4):
			img.set_pixel(int(c.x - 7 * s) + dx, ey, eye)
			img.set_pixel(int(c.x + 7 * s) + dx, ey, eye)
	else:
		for dy in range(0, int(5 * s)):
			for dx in range(0, int(3 * s)):
				img.set_pixel(int(c.x - 8 * s) + dx, ey + dy - 2, eye)
				img.set_pixel(int(c.x + 6 * s) + dx, ey + dy - 2, eye)
	# 嘴
	var my := int(40 * s)
	var mouth := Color("b03050")
	match face:
		"happy", "smug":
			for dx in range(-3, 4):
				img.set_pixel(int(c.x) + dx, my + (1 if absi(dx) < 2 else 0), mouth)
		"shock", "angry", "tilt":
			for dy in 3:
				for dx in range(-2, 2):
					img.set_pixel(int(c.x) + dx, my + dy - 1, mouth)
		_:
			for dx in range(-2, 2):
				img.set_pixel(int(c.x) + dx, my, mouth)
	return ImageTexture.create_from_image(img)

static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in range(int(c.y - r), int(c.y + r) + 1):
		for x in range(int(c.x - r), int(c.x + r) + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				if Vector2(x, y).distance_to(c) <= r:
					img.set_pixel(x, y, col)
