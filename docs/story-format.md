# 剧情章节格式（data/story/chapters/*.json）

剧情模式**跟着漫画走**：一个章节文件 = 原作一话或几话。漫画更新后，新增一个 JSON 文件即可，游戏会自动扫描并按 `order` 排序（`src/story/story_db.gd`）。

## 原则
- **只写有出处的情节**。出处统一记在 `docs/research/manga-reference.md`，章节里用 `source` 字段指向它的小节/来源编号。
- 台词是**转述/改编**，不照搬原作对白，不使用原作图片。
- 为教学而加的情节（如模拟账户练习）是**游戏原创**，必须在 `original` 字段里写明。
- 行情是算法生成的；复刻真实事件时，只用核实过的关键价位做关键帧（布朗桥逼近），并在 `source` 里注明来源。

## 顶层字段
| 字段 | 说明 |
|---|---|
| `id` | 唯一 id，如 `ch08` |
| `order` | 排序数字（可用小数插队） |
| `title` | 显示标题 |
| `manga` | 对应原作话数，如 `第11〜15話（3巻）` |
| `period` | 作中时间，如 `2014年春` |
| `source` | 出处说明（指向调研文档） |
| `original` | 游戏原创部分说明（可空） |
| `tutorial` | 是否新手教程章节 |
| `battle` | 是否含经典战役复刻（会出现在「经典战役」菜单） |
| `wip` | 原作连载中、内容未完 |
| `requires` | 需要先读完的章节 id 列表 |
| `unlock_on_clear` | 读完后解锁的标签（如 `friend_mochiko`） |
| `tutorial_complete` | 读完后标记教程完成 → 解锁肉鸽模式 |
| `scenes` | 场景数组（见下） |

## 场景类型
### `title_card`
`{"type":"title_card","text":"2008年 秋","sub":"副标题","bg":"bg_living_dim","hold":1.6}`

### `dialogue`
`{"type":"dialogue","bg":"bg_room_night","lines":[行...]}`

行：`{"who":"kurumi","face":"happy","text":"……","side":"left","bg":"换背景","sfx":"音效"}`
- `who`：`characters.json` 里的 id（kurumi / mochiko / mebuki / yasuko / ikuo / kozue / narrator / tv / note）。
- `face`：立绘表情，对应 `assets/sprites/portraits/<who>_<face>.png`，缺图自动退回 normal 或占位剪影。

### `cg`
`{"type":"cg","image":"cg_shock","lines":[...]}`

### `unlock`
`{"type":"unlock","title":"解锁！","text":"bbcode","unlocks":["roguelike"],"tutorial_done":true}`

### `trade`
```json
{
  "type": "trade",
  "config": { TradeSession 配置：seed, start_date, days, balance, broker, symbols, act,
              market_params, event_params, overrides{start_prices,pegs}, script[...] },
  "mods": { 本场景开启的能力，如 "show_sentiment": 1 },
  "positions": [{"symbol":"USDJPY","side":1,"lots":5,"entry":103.2}],
  "intro": [开场对话行],
  "steps": [教学步骤],
  "win": {"profit": 30000} | {"equity": X} | {"steps": true} | {"always": true},
  "lose_continues": false,
  "on_win": [对话], "on_lose": [对话]
}
```
`config.script` / step 的 `script` 时间线条目：`{"t": 相对tick 或 "day","hour","minute", "do": 动作, ...}`

动作：`news`（def 或 template）、`text`、`sns`、`guide{symbol,price,ticks}`、`effect`、`peg`、`peg_break`、`halt`、`params`、`say`、`dialog{lines}`、`pause{text}`、`indicator{id,day,forced}`、`rate`、`deposit{amount,note}`、`mental{value}`、`finish`，以及界面动作 `lock{names}`、`unlock`、`objective{text}`、`highlight{name}`、`select{symbol}`、`tf{index}`、`speed{value}`、`shake`、`flash`、`sfx`。

教学步骤字段见 `src/story/tutorial_director.gd` 顶部注释。
