class_name GameDate
extends RefCounted
## 日期工具：交易日（跳过周末）与显示。

const WEEK_CN := ["日", "一", "二", "三", "四", "五", "六"]

static func parse(s: String) -> int:
	var p := s.split("-")
	return Time.get_unix_time_from_datetime_dict({"year": int(p[0]), "month": int(p[1]), "day": int(p[2]), "hour": 0, "minute": 0, "second": 0})

static func weekday(unix: int) -> int:
	return Time.get_datetime_dict_from_unix_time(unix).weekday # 0=周日

## 从 start（应为工作日）开始第 k 个交易日（k 可为负）的 unix 时间
static func trading_day(start: int, k: int) -> int:
	var t := start
	var step := 1 if k >= 0 else -1
	var left := absi(k)
	while left > 0:
		t += step * 86400
		var wd := weekday(t)
		if wd != 0 and wd != 6:
			left -= 1
	return t

## 把任意日期挪到最近的工作日（向后）
static func next_weekday(unix: int) -> int:
	var t := unix
	while weekday(t) == 0 or weekday(t) == 6:
		t += 86400
	return t

static func fmt(unix: int, with_year := true) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	if with_year:
		return "%d/%02d/%02d(%s)" % [d.year, d.month, d.day, WEEK_CN[d.weekday]]
	return "%02d/%02d(%s)" % [d.month, d.day, WEEK_CN[d.weekday]]

static func fmt_md(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%d/%d" % [d.month, d.day]

## 金额显示：万円 / 億円
static func yen(v: float, signed := false) -> String:
	var s := ""
	if signed and v > 0.0:
		s = "+"
	if v < 0.0:
		s = "-"
	var a := absf(v)
	if a >= 1e8:
		return s + "%.2f億円" % (a / 1e8)
	if a >= 1e4:
		return s + "%.1f万円" % (a / 1e4)
	return s + "%d円" % int(round(a))
