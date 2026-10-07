#!/usr/bin/env python3
"""生成 PV 剪辑表 config/pv-edit.json（v2）。剪辑改这里，再运行本脚本，然后 make_pv.py 合成。

用 Python 写剪辑表是为了复用「功能段标题」「仲间面板」这类重复结构；JSON 字段含义见生成结果里的 _doc。
所有时刻都对在配乐的拍点上（见 _doc 里的重拍列表）。文案只用调研文档里有出处的事实与游戏玩法说明。
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PINK, CYAN, GOLD, RED, PURP, GREEN, ORANGE = "#ff5da0", "#6ee6ff", "#ffd76e", "#ff3050", "#b48cff", "#7cffa0", "#ff9c5d"
DK = "#0b0814"
INK = "#1a0820"


def T(s, **k):
    return {"type": "text", "s": s, **k}


def sub(s, t, **k):
    """字幕：放在下方黑边里。"""
    return {"type": "text", "s": s, "y": 342, "t": t, "fi": 0.15, **k}


def img(src, **k):
    return {"type": "img", "src": src, **k}


def clip(name, frm, speed=1.0, **k):
    return {"type": "clip", "clip": name, "from": frm, "speed": speed, **k}


def fill(color=None, **k):
    d = {"type": "fill", **k}
    if color:
        d["color"] = color
    return d


def group(layers, **k):
    return {"type": "group", "layers": layers, **k}


LB = {"type": "letterbox", "h": 36}


def header(no, zh, en, col, t0=0.0):
    """功能段标题：左上角斜切色带 + 编号 + 中文 + 英文，从左侧滑入。"""
    return group([
        fill(col, poly=[[0, 12], [236, 12], [220, 46], [0, 46]]),
        fill(DK, poly=[[0, 46], [220, 46], [214, 58], [0, 58]]),
        T(no, scale=2, x=10, y=29, align="l"),
        T(zh, scale=2, x=52, y=29, align="l"),
        T(en, x=130, y=30, align="l", color=INK, outline=None),
    ], t=[t0, None], ox=[[t0, -280], [t0 + 0.2, 0, "out"]])


def tag(s, y, t0, col=PINK, x=12, side="l"):
    """功能标签：带色条的暗色小框，从侧边滑入。"""
    return T(s, scale=2, x=x, y=y, align=side, t=[t0, None], ox=[[t0, -200 if side == "l" else 200], [t0 + 0.15, 0, "out"]],
             box={"bar": col, "pad": 6, "alpha": 0.95})


def friend_panel(poly, cx, t0, from_y, name, col, pid, lines, grad):
    """仲间面板：斜切格子 + 渐变底 + 流线 + 立绘 + 名字 + 两行官方人设转述，从上/下砸进来。"""
    def left(y):  # 斜切左边在 y 处的 x
        return int(poly[0][0] + (poly[3][0] - poly[0][0]) * y / 360)
    return group([
        fill(grad=grad),
        {"type": "speedlines", "color": col, "n": 14, "speed": 300, "seed": int(cx), "alpha": 0.5},
        img("portrait:" + pid, scale=2, anchor="b", x=cx, y=[[t0, 352], [t0 + 2.5, 346]]),
        T(name, scale=3, x=left(34) + 12, y=34, align="l", t=[t0 + 0.08, None]),
        T(lines[0], x=left(300) + 8, y=300, align="l", t=[t0 + 0.15, None], box={"bar": col, "pad": 4}),
        T(lines[1], x=left(322) + 8, y=322, align="l", t=[t0 + 0.2, None], box={"bar": col, "pad": 4}),
    ], poly=poly, border="#ffffff", t=[t0, None], oy=[[t0, from_y], [t0 + 0.16, 0, "out"]])


def chibi_bob(x0, x1, t_in, n=10, beat=0.6225, base=350):
    """Q 版久留美：从 x0 跑到 x1，按半拍上下蹦（base＝脚底 y）。"""
    ys = [[0, base]]
    for i in range(n):
        ys.append([i * beat / 2 + beat / 4, base - 10 if i % 2 == 0 else base, "out" if i % 2 == 0 else "in"])
    return {"x": [[0, x0], [t_in, x1, "out"]], "y": ys}


def build():
    shots = []
    A = shots.append

    # ======================== 序章（安静段，影院黑边） ========================
    A({"id": "open_2008", "at": 0.0, "layers": [
        T("2008年 秋", scale=3, y=160, typewriter=True, cps=6, t=[0.3, None]),
        T("雷曼兄弟破产，金融危机席卷全世界。", color="#a89cc8", y=204, t=[1.4, None], fi=0.4)]})

    A({"id": "lehman", "at": 3.2, "in": {"type": "slash", "d": 0.35, "color": RED}, "layers": [
        fill(DK), {"type": "stripes", "colors": ["#120a1e", "#170e26"], "w": 10, "speed": 16},
        # 左格：母亲的交易画面（实机，原生像素）
        clip("lehman", 30, 4.0, crop=[0, 22, 400, 300], anchor="tl", x=6, y=38,
             poly=[[6, 40], [392, 40], [350, 320], [6, 320]], border="#ffffff", ox=[[0, -420], [0.35, 0, "out"]]),
        # 右格：母亲·梢（剪影立绘）+ 红色渐变 + 集中线
        group([
            fill(grad=["#2a0410", "#c02040"], grad_y=[40, 320]),
            {"type": "focus", "color": "#ff7a90", "cx": 510, "cy": 170, "r": 70, "n": 40},
            img("portrait:kozue_normal", scale=2, anchor="b", x=505, y=322),
            T("母亲 · 梢", x=622, y=58, align="r", color="#e8c0a0"),
        ], poly=[[400, 40], [634, 40], [634, 320], [358, 320]], border="#ffffff",
            ox=[[0.45, 300], [0.8, 0, "out"]], t=[0.45, None]),
        LB,
        sub("母亲瞒着所有人，把家里的钱投进了 FX。", [0.2, 2.6]),
        sub("2000万円，在暴跌中消失殆尽。", [2.7, None], color="#ff7a90")],
        "fx": {"glitch": [[2.65, 2.8, 0.5]], "flash": [[2.65, 0.15, RED]]}})

    A({"id": "living", "at": 8.4, "in": {"type": "dither", "d": 0.6}, "layers": [
        img("bg:bg_living_dim", scale=2),
        {"type": "particles", "kind": "dust", "n": 26, "color": "#7080b0", "seed": 4},
        {"type": "vignette", "strength": 0.7},
        LB, sub("四个月后，母亲离开了这个世界。", [0.6, None])]})

    # 雨夜：背景层 / 远雨 / 角色层 / 近雨 四层视差（角色与背景反向漂移几像素）
    A({"id": "rain", "at": 12.4, "in": {"type": "pixelate", "d": 0.5}, "layers": [
        img("px:pv_rain_bg", scale=2, x=[[0, 323], [5.4, 317, "linear"]]),
        {"type": "particles", "kind": "rain", "n": 90, "color": "#3c5878", "vel": [-40, 380], "len": 6, "seed": 21},
        img("px:pv_rain_fg", scale=2, x=[[0, 316], [5.4, 323, "linear"]]),
        {"type": "particles", "kind": "rain", "n": 45, "color": "#9cc0e8", "vel": [-70, 700], "len": 14, "seed": 22},
        group([
            fill(PINK, poly=[[0, 236], [214, 236], [200, 268], [0, 268]]),
            fill(DK, poly=[[0, 268], [200, 268], [194, 282], [0, 282]]),
            T("福賀 久留美", scale=2, x=14, y=252, align="l"),
            T("FUKUGA KURUMI", x=14, y=275, align="l", color=CYAN, outline=None),
        ], t=[1.0, 3.1], fo=0.2, ox=[[1.0, -260], [1.25, 0, "out"]]),
        LB,
        sub("她的女儿——", [0.6, 2.9]),
        sub("她决定，用同样的 FX……", [3.0, None])]})

    A({"id": "resolve", "at": 17.8, "in": {"type": "dither", "d": 0.4}, "layers": [
        img("px:pv_resolve_bg", scale=2),
        {"type": "particles", "kind": "rain", "n": 30, "color": "#28485a", "vel": [-20, 300], "len": 5, "seed": 31,
         "poly": [[0, 0], [300, 0], [300, 230], [0, 230]]},
        img("px:pv_resolve_fg", scale=2, x=[[0, 326], [2.4, 318, "linear"]]),
        LB,
        T("「把 2000万円 取回来！」", scale=2, y=290, color=PINK, outline=INK, slam=[5, 0.12], t=[0.6, None])],
        "fx": {"shake": [[0.6, 0.85, 3]]}})

    # 爆发前的加速闪切（拍点 20.20 / 20.81 / 21.43，半拍 21.74）
    A({"id": "eyes", "at": 20.20, "layers": [
        fill("#000000"),
        fill(grad=["#3a0a24", PINK], grad_y=[130, 230], poly=[[0, 132], [640, 132], [640, 228], [0, 228]]),
        {"type": "speedlines", "color": "#ffd0e4", "n": 18, "band": [134, 226], "speed": 1400},
        img("portrait:kurumi_focus", crop=[38, 34, 52, 18], scale=5, x=[[0, 330], [0.6, 314, "linear"]],
            poly=[[0, 134], [640, 134], [640, 226], [0, 226]]),
        T("2008 → 2014", x=626, y=244, align="r", color="#ffb0d0", outline=None)],
        "fx": {"flash": [[0, 0.1]]}})

    A({"id": "crash_flash", "at": 20.81, "layers": [
        fill("#120006"),
        {"type": "focus", "color": RED, "r": 130, "n": 70},
        T("2000万円", scale=6, y=176, outline=RED, slam=[9, 0.1]),
        T("−20,000,000", scale=2, y=232, color="#ff7a90", t=[0.15, None])],
        "fx": {"shake": [[0, 0.3, 6]], "flash": [[0, 0.08, RED]]}})

    A({"id": "burst", "at": 21.43, "layers": [
        {"type": "burst", "colors": [PINK, "#ff8cc0"], "cy": 200, "speed": 60},
        img("portrait:kurumi_angry", scale=3, anchor="b", x=320, y=[[0, 400], [0.12, 372, "out"]], silhouette=INK)]})

    A({"id": "white", "at": 21.74, "layers": [
        fill("#ffffff"),
        img("px:pv_key_fg", scale=2, silhouette=PINK, y=[[0, 186], [0.3, 180]])]})

    # ======================== Logo（原曲 63.0 秒爆发）：标题压在角色身后 ========================
    A({"id": "logo", "at": 22.06, "layers": [
        img("px:pv_key_bg", scale=2, x=[[0, 320], [2.5, 324, "linear"]]),
        {"type": "particles", "kind": "sparkle", "n": 26, "color": "#ffffff", "ymax": 0.6, "seed": 8},
        T("FX战士久留美", scale=6, y=96, color=PINK, outline=INK, slam=[10, 0.16], t=[0.04, None]),
        {"type": "particles", "kind": "coins_burst", "n": 34, "origin": [320, 380], "speed": [320, 600],
         "cone": 70, "gravity": 520, "spread_t": 0.3},
        img("px:pv_key_fg", scale=2, x=[[0, 320], [2.5, 316, "linear"]], y=[[0, 214], [0.28, 180, "back"]]),
        group([
            fill(DK, poly=[[0, 286], [640, 270], [640, 318], [0, 334]], alpha=0.9),
            fill(PINK, poly=[[0, 334], [640, 318], [640, 322], [0, 338]]),
            T("同人 · 2000万之路", scale=2, y=296),
            T("FX戦士くるみちゃん  Fan Game", y=319, color=CYAN),
        ], ox=[[0.25, 660], [0.45, 0, "out"]], t=[0.25, None])],
        "fx": {"flash": [[0, 0.3]], "shake": [[0, 0.35, 8]]}})

    # ======================== 玩法（每小节 2.49 秒，切在重拍上） ========================
    A({"id": "cut_kurumi", "at": 24.57, "in": {"type": "slash", "d": 0.2, "color": "#ffffff"}, "layers": [
        {"type": "stripes", "colors": [PINK, "#ff74ae"], "w": 14, "speed": 140},
        {"type": "speedlines", "color": "#ffffff", "n": 28, "speed": 1100, "seed": 9},
        fill(INK, poly=[[0, 64], [372, 64], [300, 292], [0, 292]], ox=[[0, -400], [0.2, 0, "out"]]),
        fill(CYAN, poly=[[0, 292], [300, 292], [297, 300], [0, 300]], ox=[[0.05, -400], [0.25, 0, "out"]]),
        img("portrait:kurumi_happy", scale=3, anchor="b", x=[[0, 780], [0.22, 468, "out"], [2.48, 460, "linear"]],
            y=376, ghost=[3, 0.035]),
        T("福賀 久留美", scale=4, x=24, y=112, align="l", ox=[[0.1, -380], [0.3, 0, "out"]], t=[0.1, None]),
        T("FUKUGA KURUMI", x=28, y=150, align="l", color=CYAN, outline=None, t=[0.3, None]),
        T("大学生 · 20岁", x=28, y=190, align="l", color=GOLD, t=[0.45, None]),
        T("勤奋好学，擅长冷静分析——", x=28, y=216, align="l", t=[0.6, None]),
        T("但图表一乱，就会暴走。", x=28, y=236, align="l", color="#ff9cc6", t=[0.75, None])],
        "fx": {"flash": [[0, 0.1]]}})

    A({"id": "f01_market", "at": 27.05, "in": {"type": "diamond", "d": 0.3}, "layers": [
        {"type": "grid", "speed": 30},
        clip("trade", 208, 1.5, crop=[0, 14, 430, 276], anchor="tl", x=200, y=62,
             poly=[[200, 62], [630, 62], [630, 338], [200, 338]], border=PINK, ox=[[0, 460], [0.25, 0, "out"]]),
        header("01", "行情", "MARKET", PINK),
        tag("多因子算法\n实时生成行情", 110, 0.15),
        tag("最高 888 倍杠杆", 178, 0.77),
        tag("拖动 SL/TP 线\n直接改单", 240, 1.4)]})

    A({"id": "f02_news", "at": 29.54, "in": {"type": "slash", "d": 0.2, "color": CYAN}, "layers": [
        {"type": "grid", "speed": -30, "tint": "#0040a0"},
        clip("trade", 420, 1.2, crop=[0, 14, 430, 276], anchor="tl", x=10, y=62,
             poly=[[10, 62], [440, 62], [440, 338], [10, 338]], border=CYAN, ox=[[0, -460], [0.25, 0, "out"]]),
        header("02", "事件", "NEWS", CYAN),
        tag("新闻速报", 92, 0.15, CYAN, x=628, side="r"),
        tag("经济指标", 136, 0.55, GOLD, x=628, side="r"),
        tag("央行决议", 180, 0.95, PINK, x=628, side="r"),
        tag("谣言", 224, 1.35, PURP, x=628, side="r"),
        tag("散户情绪", 268, 1.75, GREEN, x=628, side="r"),
        T("都会推动价格", x=628, y=320, align="r", color=CYAN, t=[2.0, None])]})

    A({"id": "f03_story", "at": 32.02, "in": {"type": "pixelate", "d": 0.3}, "layers": [
        clip("dialogue", 292, 1.0),
        header("03", "剧情", "STORY", GOLD),
        T("跟着漫画逐卷改编 · 全 15 章", x=628, y=66, align="r", t=[0.3, None], ox=[[0.3, 300], [0.5, 0, "out"]],
          box={"bar": GOLD, "pad": 6, "alpha": 0.95})]})

    # 仲间：三格斜切面板，每拍砸进一格，第四拍压上标语
    A({"id": "friends", "at": 34.50, "layers": [
        fill(DK),
        friend_panel([[0, 0], [236, 0], [196, 360], [0, 360]], 110, 0.0, -370, "萌智子", PURP, "mochiko_smile",
                     ["同校的投资朋友", "总资产 1000万円以上"], ["#1c1030", "#6a4aa0"]),
        friend_panel([[244, 0], [436, 0], [396, 360], [204, 360]], 320, 0.62, 370, "芽吹", GOLD, "mebuki_happy",
                     ["憧憬萌智子而开始 FX", "开朗随性，乐观过头"], ["#2a2008", "#a08030"]),
        friend_panel([[444, 0], [640, 0], [640, 360], [404, 360]], 528, 1.25, -370, "やす子", "#ff5d73", "yasuko_happy",
                     ["投资博主「あふぃちゃん」", "嘴毒，但很会照顾人"], ["#2a0814", "#a03048"]),
        group([
            fill(DK, poly=[[0, 240], [640, 232], [640, 276], [0, 284]], alpha=0.95),
            T("仲间 —— 加入你的构筑", scale=2, y=258),
        ], t=[1.87, None], ox=[[1.87, -640], [2.02, 0, "out"]])],
        "fx": {"flash": [[0, 0.08], [0.62, 0.08], [1.25, 0.08], [1.87, 0.1]]}})

    A({"id": "f04_rogue", "at": 37.01, "in": {"type": "diamond", "d": 0.3}, "layers": [
        clip("map", 40, 1.0),
        header("04", "肉鸽", "ROGUELIKE", ORANGE),
        T("3 幕 · 分叉地图 · 精英与 Boss", x=12, y=338, align="l", t=[0.2, None], box={"bar": ORANGE, "pad": 6, "alpha": 0.95}),
        group([
            {"type": "stripes", "colors": ["#140c22", "#1a1030"], "w": 10, "speed": 30},
            {"type": "icons", "icons": ["rocket", "crystal_ball", "bollinger", "rsi_gauge", "omamori", "fortune_slip",
                                        "black_card", "handcuffs_money", "energy_drink", "headset", "monitors", "piggy_bank",
                                        "dice", "shield", "white_cat", "hourglass"],
             "cols": 4, "scale": 2, "cell": 70, "x": 468, "y": 158, "stagger": 0.045, "t": [1.3, None]},
            T("手法 · 道具 · 诅咒 · 仲间 · FX业者", x=462, y=316, t=[1.6, None]),
        ], poly=[[300, 0], [640, 0], [640, 360], [260, 360]], border=GOLD, t=[1.245, None],
            ox=[[1.245, 400], [1.4, 0, "out"]])]})

    A({"id": "f05_meta", "at": 39.50, "in": {"type": "pixelate", "d": 0.25}, "layers": [
        clip("meta", 60, 1.0),
        header("05", "养成", "META", GREEN),
        T("局外养成「相場勘」 · 无尽模式 · 挑战度 1~10", y=342, t=[0.2, None], box={"bar": GREEN, "pad": 6, "alpha": 0.95}),
        img("chibi:kurumi_chibi", scale=2, anchor="b", t=[0.3, None], **chibi_bob(700, 572, 0.3))],
        "fx": {"glitch": [[2.2, 2.48, 0.6]], "fade_out": 0.12}})

    # ======================== 高潮：瑞郎冲击（原曲 83.2 秒断奏段） ========================
    A({"id": "date_2015", "at": 41.98, "layers": [
        T("2015.01.15  18:30", scale=4, y=160, typewriter=True, cps=18, t=[0.1, None]),
        T("EUR/CHF", scale=2, color="#ff5d73", y=212, t=[0.8, None])],
        "fx": {"glitch": [[0.8, 0.95, 0.6], [1.4, 1.5, 0.5], [2.2, 2.49, 0.8]]}})

    A({"id": "snb_calm", "at": 44.47, "in": {"type": "dither", "d": 0.3}, "layers": [
        clip("snb", 200, 1.0),
        {"type": "vignette", "strength": 0.55, "color": "#30000c"},
        {"type": "letterbox", "h": 34},
        sub("三年未破的 1.20 下限——人人都说「绝对安全」。", [0.1, None])]})

    # 插播速报：在拍点上整数倍推近（×2 → ×3）
    A({"id": "snb_tv", "at": 47.40, "layers": [
        clip("snb", 300, 0.5, punch=[[0, 320, 180, 1], [0.8, 278, 178, 2], [1.43, 255, 178, 3]]),
        {"type": "letterbox", "h": 34}],
        "fx": {"flash": [[0.8, 0.12, RED], [1.43, 0.12, RED]], "shake": [[0.8, 0.95, 3], [1.43, 1.6, 4]]}})

    A({"id": "impact", "at": 49.44, "layers": [clip("snb", 374, 0.0)],
       "fx": {"impact": [[0, 1, "neg"]], "shake": [[0, 0.17, 10]]}})

    A({"id": "snb_crash", "at": 49.61, "layers": [clip("snb", 374, 0.12)],
       "fx": {"flash": [[0, 0.25, "#ff2040"]], "shake": [[0, 1.1, 7]], "glitch": [[0, 0.3, 1.0], [1.2, 1.32, 0.6]]}})

    A({"id": "snb_stopout", "at": 51.32, "layers": [
        clip("snb", 389, 0.4, punch=[[0, 320, 180, 1], [0.3, 228, 199, 2]])],
        "fx": {"shake": [[0.3, 0.6, 6]], "flash": [[0.3, 0.1, RED]]}})

    A({"id": "shock", "at": 52.55, "layers": [
        img("px:cg_shock", scale=2),
        {"type": "focus", "color": "#ff2040", "cx": 470, "cy": 120, "r": 150, "n": 50, "alpha": 0.8},
        group([
            fill("#000000", poly=[[0, 252], [640, 236], [640, 300], [0, 316]], alpha=0.9),
            T("不足金", scale=2, x=60, y=278, align="l"),
            T("1.22亿円", scale=4, x=150, y=276, align="l", color=RED, outline=INK, slam=[7, 0.12], t=[0.18, None]),
        ], ox=[[0.1, -640], [0.22, 0, "out"]], t=[0.1, None])],
        "fx": {"flash": [[0, 0.2, "#ff2040"]], "glitch": [[0, 0.2, 0.9], [1.6, 1.88, 0.7]]}})

    A({"id": "aftermath", "at": 54.43, "layers": [
        img("px:cg_shock", scale=2, grade="mono+dark"),
        {"type": "vignette", "strength": 0.9},
        T("超过 1亿円 的负债。", y=300, t=[0.4, 2.2], fi=0.3, fo=0.3)],
        "fx": {"fade_out": 0.6}})

    # ======================== 反转（原曲 103 秒再推起） ========================
    A({"id": "this_time", "at": 56.91, "layers": [
        T("这一次——", scale=3, y=180, typewriter=True, cps=8, t=[0.3, None])]})

    A({"id": "your_turn", "at": 59.40, "in": {"type": "iris", "d": 0.45, "center": [330, 150]}, "layers": [
        img("px:pv_key_bg", scale=2, x=[[0, 318], [2.5, 322, "linear"]]),
        {"type": "particles", "kind": "sparkle", "n": 20, "color": "#ffffff", "ymax": 0.6, "seed": 18},
        img("px:pv_key_fg", scale=2, x=[[0, 324], [2.5, 316, "linear"]]),
        group([
            fill(PINK, poly=[[0, 262], [640, 246], [640, 302], [0, 318]]),
            fill(DK, poly=[[0, 318], [640, 302], [640, 308], [0, 324]]),
            T("轮到你来交易。", scale=3, y=282, outline=INK, slam=[5, 0.1], t=[0.55, None]),
        ], ox=[[0.45, 660], [0.62, 0, "out"]], t=[0.45, None])],
        "fx": {"shake": [[0.55, 0.75, 4]]}})

    A({"id": "counter", "at": 61.90, "layers": [
        img("px:cg_win", scale=2),
        {"type": "particles", "kind": "coins_fall", "n": 26, "speed": [70, 150], "seed": 41},
        fill(DK, poly=[[0, 252], [640, 252], [640, 336], [0, 336]], alpha=0.8),
        T("目标", scale=2, y=268, color=GOLD, t=[0.1, None]),
        {"type": "counter", "from": 300000, "to": 20000000, "fmt": "{:,.0f}円", "t_in": 0.2, "out_at": 2.49, "scale": 4, "y": 306}],
        "fx": {"flash": [[0, 0.3], [2.49, 0.35, "#ffe08a"]], "shake": [[2.49, 2.7, 5]]}})

    A({"id": "end", "at": 65.90, "d": 5.5, "in": {"type": "dither", "d": 0.4}, "layers": [
        img("bg:bg_city_night", scale=2, grade="dark"),
        {"type": "vignette", "strength": 0.8},
        T("FX战士久留美", scale=5, y=54, color=PINK, outline=INK),
        T("同人 · 2000万之路", scale=2, y=104, t=[0.2, None]),
        T("剧情模式 · 肉鸽模式 · 经典战役 · 图鉴", y=134, color=CYAN, t=[0.5, None]),
        img("chibi:kurumi_chibi", scale=2, anchor="b", t=[0.3, None], **chibi_bob(320, 320, 0.01, n=16, base=246)),
        T("开发中 · Godot 4.7", y=264, color="#a89cc8", t=[0.6, None]),
        T("非官方同人游戏　原作《FX戦士くるみちゃん》でむにゃん / 炭酸だいすき（KADOKAWA）", y=284, color="#d8cff0", t=[0.8, None]),
        T("画面为实机录制，行情由算法生成；第1、11章为参照真实事件的示意走势。", y=299, color="#a89cc8", t=[0.8, None]),
        T("投资有风险，本作不构成任何投资建议。", y=314, color="#a89cc8", t=[0.8, None]),
        T("插画：Anima + 角色 LoRA（AI 生成）　音乐：YuE2（AI 生成）　字体：Fusion Pixel Font（OFL）", y=329, color="#a89cc8", t=[0.8, None])],
        "fx": {"fade_out": 0.8}})
    return shots


DOC = ("PV 剪辑表 v2，由 scripts/pv/build_edit.py 生成（改剪辑请改那个脚本再运行），scripts/pv/make_pv.py 读取。"
       "画布 640×360（游戏原生分辨率），成片最近邻放大 3 倍。"
       "配乐 assets/pv/pv_theme.ogg 从 offset 秒开始播：原曲 63.0 秒的爆发点＝PV 22.06 秒（Logo）；拍长约 0.6225 秒、小节 2.49 秒，"
       "重拍 24.57/27.05/29.54/32.02/34.50/37.01/39.50/41.98/44.47/46.95/49.44/51.94/54.43/56.91/59.40/61.90/64.39；"
       "原曲 83.2 秒起断奏段＝PV 42.2；103 秒再推起＝PV 62；108 秒结束＝PV 67。"
       "镜头：at（绝对开始秒，上一镜头的 d 自动补齐）或 d；bg 底色；in 转场 {type: dither|slash|diamond|shutter|iris|pixelate|flash, d, color, center}；"
       "layers[] 依次叠放；fx {flash:[[t,dur,色]], shake:[[t0,t1,像素]], glitch:[[t0,t1,强度]], impact:[[t0,t1,neg|red|white]]}；fade_in/fade_out（抖动黑场）。"
       "图层通用字段：t=[开始,结束]（null＝到镜头末）、ox/oy 整体偏移、poly 多边形遮罩（随 ox/oy 移动）+ border/bw 描边、alpha、fi/fo（抖动淡入淡出）。"
       "数值字段都可写关键帧 [[t,v],[t,v,缓动]]，缓动 linear|in|out|inout|back|step。"
       "图层类型：img{src,scale(整数),x,y,anchor(c|b|t|l|r|tl),crop,flip,silhouette,grade,ghost[n,dt],frames}；"
       "clip{clip,from,speed,punch[[t,cx,cy,整数倍]],crop+x/y/anchor,grade}；fill{color|grad[c0,c1]+grad_y}；stripes{colors,w,speed}；grid{speed,tint}；"
       "speedlines{color,n,speed,len,band}；focus{color,cx,cy,r,n}；burst{colors,cx,cy,n,speed}；"
       "particles{kind:rain|dust|sparkle|coins_fall|coins_burst,…}；text{s,scale,color,outline(null＝无),x,y,align(c|l|r),typewriter,cps,slam[起始倍数,时长],box{bar,pad,alpha,color},vertical}；"
       "rect；icons{icons,cols,scale,cell,x,y,stagger}；counter{from,to,fmt,t_in,out_at,scale,y}；vignette{strength,color}；letterbox{h}；group{layers}。")

SFX = [
    (3.25, "news", -10), (22.06, "title", -8), (24.57, "open", -12), (27.58, "win", -12), (30.2, "news", -11),
    (34.50, "click", -12), (35.12, "click", -12), (35.75, "click", -12),
    (47.7, "news", -8), (49.44, "crash", -2), (49.6, "alarm", -9), (50.1, "alarm", -11), (51.62, "lose", -6),
    (62.2, "coin", -12), (63.0, "coin", -12), (63.7, "coin", -11), (64.39, "win", -7), (66.3, "title", -9),
]


def main():
    cfg = {
        "_doc": DOC,
        "fps": 30,
        "music": {"src": "assets/pv/pv_theme.ogg", "offset": 41.0, "gain_db": 3.5, "fade_in": 0.8, "fade_out": 2.5,
                  "fade_out_end": 67.0},
        "sfx": [{"t": t, "src": f"assets/sfx/{n}.wav", "gain_db": g} for t, n, g in SFX],
        "shots": build(),
    }
    p = ROOT / "config/pv-edit.json"
    p.write_text(json.dumps(cfg, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"→ {p.relative_to(ROOT)}（{len(cfg['shots'])} 个镜头）")


if __name__ == "__main__":
    main()
