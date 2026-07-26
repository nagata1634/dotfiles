#!/usr/bin/env python3
"""壁紙ピッカー / span 適用。

- ~/Pictures/background から画像を rofi(サムネイル付き) で選ぶ
- 外部モニタには1枚の画像を「またがって(span)」表示し、内蔵(eDP)には1枚で表示する
- span のジオメトリは現在の出力レイアウト(swaymsg get_outputs)から動的に算出するため、
  モニタ位置や境界を変えても追従する（位置調整ツールから --reapply で呼べる）
- 選んだ元画像のパスは .span/current に記録し、後で同じ画像を再 span できる

役割マッピング（apply-displays.py と統一）:
  外部・横向き(transform normal/180) → dp6.png
  外部・縦向き(transform 90/270)     → dp5.png
  内蔵(eDP*)                          → edp1.png（1枚・cover）

使い方:
  wallpaper-picker.py            # rofi で選んで適用
  wallpaper-picker.py --reapply  # .span/current の画像を現在のレイアウトで再適用
  wallpaper-picker.py PATH       # 指定画像を適用
"""
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import rofi

WALL_DIR = Path.home() / "Pictures/background"
SPAN = WALL_DIR / ".span"
CURRENT = SPAN / "current"            # 直近に選んだ元画像のパスを記録
FULL = SPAN / "_full.png"             # bbox をカバーした中間画像
EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}

# 壁紙ピッカー専用のレイアウト上書き（このメニューだけ大サムネイルのグリッドにする）。
# config.rasi のアイコンは小さい(1.1em)ため、-theme-str でここだけ拡大する。
ROFI_GRID = (
    "window { width: 1160px; }"
    "listview { columns: 4; lines: 2; spacing: 12px; }"
    "element { orientation: vertical; padding: 10px; }"
    "element-icon { size: 240px; }"
    "element-text { horizontal-align: 0.5; }"
)
def sh(*args, check=False):
    return subprocess.run(list(args), check=check,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def magick(*args):
    subprocess.run(["magick", *args], check=True)


def get_outputs():
    return json.loads(subprocess.check_output(["swaymsg", "-t", "get_outputs"]))


def is_internal(name):
    return name.startswith(("eDP", "LVDS", "DSI"))


def is_portrait(o):
    return str(o.get("transform", "")) in ("90", "270")


def mode_size(o):
    """非アクティブでもサイズを得る（rect が 0 のとき current_mode/modes から）。"""
    r = o.get("rect") or {}
    if r.get("width") and r.get("height"):
        return r["width"], r["height"]
    cm = o.get("current_mode") or (o.get("modes") or [{}])[0]
    w, h = cm.get("width", 1920), cm.get("height", 1080)
    # 縦向きなら論理サイズは入れ替わる
    return (h, w) if is_portrait(o) else (w, h)


def notify(msg):
    sh("notify-send", "壁紙", msg)


# ---- 適用本体 -----------------------------------------------------------
def apply(src: Path):
    outs = get_outputs()
    span = [o for o in outs if not is_internal(o["name"]) and o.get("active")]
    internal = [o for o in outs if is_internal(o["name"])]
    SPAN.mkdir(parents=True, exist_ok=True)

    # --- 外部モニタ群: bbox を算出して span ---
    if span:
        xs = [o["rect"]["x"] for o in span]
        ys = [o["rect"]["y"] for o in span]
        x2 = [o["rect"]["x"] + o["rect"]["width"] for o in span]
        y2 = [o["rect"]["y"] + o["rect"]["height"] for o in span]
        bbx, bby = min(xs), min(ys)
        bbw, bbh = max(x2) - bbx, max(y2) - bby
        # 元画像を bbox にカバー配置
        magick(str(src), "-resize", f"{bbw}x{bbh}^",
               "-gravity", "center", "-extent", f"{bbw}x{bbh}", str(FULL))
        for o in span:
            r = o["rect"]
            fname = "dp5.png" if is_portrait(o) else "dp6.png"
            dst = SPAN / fname
            magick(str(FULL), "-crop",
                   f"{r['width']}x{r['height']}+{r['x'] - bbx}+{r['y'] - bby}",
                   "+repage", str(dst))
            sh("swaymsg", "output", o["name"], "bg", str(dst), "fill")

    # --- 内蔵モニタ: 1枚で cover ---
    for o in internal:
        w, h = mode_size(o)
        dst = SPAN / "edp1.png"
        magick(str(src), "-resize", f"{w}x{h}^",
               "-gravity", "center", "-extent", f"{w}x{h}", str(dst))
        if o.get("active"):
            sh("swaymsg", "output", o["name"], "bg", str(dst), "fill")

    CURRENT.write_text(str(src))


# ---- 選択UI -------------------------------------------------------------
def pick_with_rofi() -> Path | None:
    imgs = sorted(p for p in WALL_DIR.rglob("*")
                  if p.is_file() and p.suffix.lower() in EXTS
                  and SPAN not in p.parents)
    if not imgs:
        notify(f"{WALL_DIR} に画像がありません")
        return None
    # 表示=ファイル名 / アイコン=画像自身（サムネイルプレビュー）
    rows = "".join(f"{p.name}\0icon\x1f{p}\n" for p in imgs)
    idx = rofi.dmenu(rows, prompt="壁紙", index=True,
                     extra=["-show-icons", "-theme-str", ROFI_GRID])
    return imgs[idx] if idx is not None else None


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--reapply":
        if not CURRENT.exists():
            notify("再適用する壁紙の記録(.span/current)がありません")
            return
        src = Path(CURRENT.read_text().strip())
        if not src.exists():
            notify(f"記録された画像が見つかりません: {src}")
            return
    elif arg:
        src = Path(arg).expanduser()
        if not src.exists():
            notify(f"画像が見つかりません: {src}")
            return
    else:
        src = pick_with_rofi()
        if not src:
            return
    apply(src)
    notify(f"壁紙を適用: {src.name}")


if __name__ == "__main__":
    main()
