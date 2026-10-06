class_name Mods
extends RefCounted
## 修正值汇总。手法/仲间/道具/诅咒/局外养成/业者都往这里叠加。
## 规则：key 以 _mult 结尾的相乘，其余相加。

const DEFAULTS := {
	"leverage_mult": 1.0,
	"spread_mult": 1.0,
	"swap_mult": 1.0,
	"sl_slip_mult": 1.0,
	"profit_mult": 1.0,
	"loss_mult": 1.0,
	"trend_profit": 0.0,     # 顺着当前 regime 方向平仓的盈利加成（比例）
	"event_profit": 0.0,     # 事件发生后 8 tick 内开仓的盈利加成
	"mental_loss_mult": 1.0,
	"mental_gain_mult": 1.0,
	"mental_max": 100.0,
	"mental_regen": 0.0,     # 每天回复
	"news_lead": 0.0,        # 新闻提前量（tick）
	"forecast_acc": 0.0,     # 指标预测精度（0~1）
	"show_fair": 0.0,
	"show_clusters": 0.0,
	"show_sentiment": 0.0,
	"show_trend": 0.0,
	"ind_ma": 0.0,
	"ind_bb": 0.0,
	"ind_rsi": 0.0,
	"trailing": 0.0,
	"max_positions": 3.0,
	"zero_cut": 0.0,         # >0 = 负余额清零的次数
	"insurance": 0.0,        # 单笔亏损返还比例（每日一次）
	"nanpin": 0.0,           # 逆向加仓时均价改善比例
	"fp_mult": 1.0,
	"work_pay_mult": 1.0,
	"stopout_delta": 0.0,    # 强平线下调（百分点）
	"max_lot_mult": 1.0,
	"swap_reinvest": 0.0,
	"tilt_resist": 0.0,      # 暴走阈值下调
	"shop_discount": 0.0,
	"calendar_days": 1.0,    # 经济日历可见天数
}

var _base := {}
var _layers := {} # source_id -> Dictionary

func _init() -> void:
	_base = DEFAULTS.duplicate()

func set_layer(source: String, values: Dictionary) -> void:
	_layers[source] = values

func remove_layer(source: String) -> void:
	_layers.erase(source)

func has_layer(source: String) -> bool:
	return _layers.has(source)

func get_v(key: String) -> float:
	var v: float = float(_base.get(key, 1.0 if key.ends_with("_mult") else 0.0))
	var mult := key.ends_with("_mult")
	for src in _layers:
		var layer: Dictionary = _layers[src]
		if layer.has(key):
			if mult:
				v *= float(layer[key])
			else:
				v += float(layer[key])
	return v

func flag(key: String) -> bool:
	return get_v(key) > 0.0
