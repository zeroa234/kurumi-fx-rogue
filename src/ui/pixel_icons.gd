class_name PixelIcons
extends RefCounted
## 手绘的小像素图标（ASCII → 贴图），用于新闻标记、地图节点、状态图标。
## 字符：. 透明  k 黑  w 白  r 红  p 粉  y 黄  o 橙  g 绿  c 青  b 蓝  u 紫  s 灰  n 棕  d 深灰

const PAL := {
	"k": Color("120d1d"), "w": Color("f4ecff"), "r": Color("ff5d73"), "p": Color("ff6fa5"),
	"y": Color("ffd166"), "o": Color("ff9f43"), "g": Color("3ddc97"), "c": Color("5ad1e8"),
	"b": Color("4f7bff"), "u": Color("9b86d6"), "s": Color("a89cc8"), "n": Color("a0603a"),
	"d": Color("5b4a85"),
}

const ART := {
	"paper": [
		"........",
		".wwwww..",
		".wsssw..",
		".wwwwww.",
		".wssssw.",
		".wwwwww.",
		".wssssw.",
		".wwwwww.",
	],
	"quake": [
		"...o....",
		"..ooo...",
		".o...o..",
		"oo.o.oo.",
		"...o....",
		"..o.o...",
		".o...o..",
		"nnnnnnnn",
	],
	"storm": [
		"..ssss..",
		".sssssss",
		"ssssssss",
		".ssssss.",
		"...y....",
		"..yy....",
		"...yy...",
		"....y...",
	],
	"volcano": [
		"..r.o...",
		"...ro...",
		"...nn...",
		"..nnnn..",
		"..nrrn..",
		".nnnnnn.",
		"nnnnnnnn",
		"........",
	],
	"virus": [
		"g..g..g.",
		".gggggg.",
		".gwggwg.",
		"ggggggg.",
		".gggggg.",
		".gwggwg.",
		".gggggg.",
		"g..g..g.",
	],
	"sun": [
		"y..y..y.",
		".yyyyy..",
		".yoooy..",
		"yyoooyyy",
		".yoooy..",
		".yyyyy..",
		"y..y..y.",
		"........",
	],
	"flag": [
		"rrrrrr..",
		"rwwwrr..",
		"rrrrrr..",
		"rwwwrr..",
		"s.......",
		"s.......",
		"s.......",
		"s.......",
	],
	"dove": [
		"........",
		"..ww....",
		".wwww..g",
		"wwwwwwgg",
		"..wwww..",
		"...ww...",
		"........",
		"........",
	],
	"vote": [
		"..wwww..",
		"..wsww..",
		"..wwww..",
		"dddddddd",
		"d......d",
		"d.dddd.d",
		"d......d",
		"dddddddd",
	],
	"mic": [
		"..sss...",
		"..sws...",
		"..sss...",
		".s.s.s..",
		"..sss...",
		"...s....",
		"..sss...",
		"........",
	],
	"bank": [
		"...yy...",
		"..yyyy..",
		".yyyyyy.",
		"..y.y.y.",
		"..y.y.y.",
		"..y.y.y.",
		".yyyyyy.",
		"yyyyyyyy",
	],
	"oil": [
		"...k....",
		"..kkk...",
		".kkkkk..",
		".kkkkk..",
		"kkkwkkk.",
		"kkwkkkk.",
		".kkkkk..",
		"..kkk...",
	],
	"chart": [
		"......r.",
		".....rr.",
		"..r.rr..",
		".rrrr...",
		"rr......",
		"........",
		"wwwwwwww",
		"........",
	],
	"bolt": [
		"....yy..",
		"...yy...",
		"..yy....",
		".yyyyy..",
		"...yy...",
		"..yy....",
		".yy.....",
		".y......",
	],
	"gold": [
		"........",
		"..yyyy..",
		".yowwoy.",
		".yowyoy.",
		".yoyyoy.",
		".yoooy..",
		"..yyyy..",
		"........",
	],
	"whisper": [
		".uuuuu..",
		"uwuwuwu.",
		"uuuuuuu.",
		".uuuuu..",
		"..u.....",
		".u......",
		"........",
		"........",
	],
	"calendar": [
		".r..r...",
		"rrrrrrr.",
		"wwwwwww.",
		"wkwkwkw.",
		"wwwwwww.",
		"wkwkwrw.",
		"wwwwwww.",
		"........",
	],
	"cross": [
		"r.....r.",
		".r...r..",
		"..r.r...",
		"...r....",
		"..r.r...",
		".r...r..",
		"r.....r.",
		"........",
	],
	"heart": [
		".pp.pp..",
		"pppppppp",
		"pppwpppp",
		"pppppppp",
		".pppppp.",
		"..pppp..",
		"...pp...",
		"........",
	],
	"coin": [
		"..yyyy..",
		".yyooyy.",
		"yyo..oyy",
		"yyo..oyy",
		"yyo..oyy",
		".yyooyy.",
		"..yyyy..",
		"........",
	],
	"star": [
		"...y....",
		"...y....",
		"yyyyyyy.",
		".yyyyy..",
		"..yyy...",
		".yy.yy..",
		".y...y..",
		"........",
	],
	"node_trade": [
		"........",
		"....r...",
		"...rrr..",
		"g..rrr..",
		"gg.r....",
		"gg......",
		".g......",
		"........",
	],
	"node_elite": [
		"r.....r.",
		"rr...rr.",
		"rrrrrrr.",
		"rwrrrwr.",
		"rrrrrrr.",
		".rrkrr..",
		"..rrr...",
		"........",
	],
	"node_event": [
		"..yyyy..",
		".yy..yy.",
		".....yy.",
		"....yy..",
		"...yy...",
		"...yy...",
		"........",
		"...yy...",
	],
	"node_shop": [
		"pppppppp",
		"pwpwpwpw",
		"........",
		".wwwwww.",
		".wnnnnw.",
		".wnnnnw.",
		".wwwwww.",
		"........",
	],
	"node_rest": [
		"........",
		"....cc..",
		"...c....",
		"...c....",
		"....cc..",
		"bbbbbbbb",
		"bwwbbbbb",
		"b......b",
	],
	"node_boss": [
		"y.y.y.y.",
		"yyyyyyy.",
		"yryyyry.",
		"yyyyyyy.",
		"kkkkkkk.",
		"kwkkkwk.",
		"kkkkkkk.",
		".kk.kk..",
	],
	"node_start": [
		".pppp...",
		"pppppp..",
		"pwpwpp..",
		"pppppp..",
		".pppp...",
		"..pp....",
		".pppp...",
		"........",
	],
}

static var _cache := {}

static func get_icon(id: String, scale := 1) -> Texture2D:
	var key := "%s@%d" % [id, scale]
	if _cache.has(key):
		return _cache[key]
	var art: Array = ART.get(id, ART["paper"])
	var h := art.size()
	var w := String(art[0]).length()
	var img := Image.create(w * scale, h * scale, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var row: String = art[y]
		for x in w:
			var ch := row[x]
			if PAL.has(ch):
				for sy in scale:
					for sx in scale:
						img.set_pixel(x * scale + sx, y * scale + sy, PAL[ch])
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func texture_rect(id: String, scale := 1) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = get_icon(id, scale)
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	return tr
