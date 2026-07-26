#!/usr/bin/env python3
"""KTC H27T27 を2台、接続名(DP-N)順で 横(左)/縦(右) に割り当てる。

USB-C/MSTハブ経由で接続名(DP-5/6→DP-7/8…)が変動しても、
make/model でKTCの2台を見つけ、名前昇順で
  - 小さい方  → 横向き・左
  - 大きい方  → 縦向き(reverse=270)・右
に割り当てる（ユーザー確認済みマッピング）。
シリアルが Unknown のため、この相対順序が唯一の識別手段。
順序が逆転したら LOWER_IS_LANDSCAPE を False にする。
"""
import json
import subprocess
from pathlib import Path

SPAN = str(Path.home() / "Pictures/background/.span")
KTC_MAKE = "Shenzhen KTC Technology Group"
KTC_MODEL = "H27T27"
LOWER_IS_LANDSCAPE = True  # 名前が小さい方を横/左にする


def sway(*args):
    subprocess.run(["swaymsg", *args],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    outs = json.loads(subprocess.check_output(["swaymsg", "-t", "get_outputs"]))
    ktc = sorted(o["name"] for o in outs
                 if o.get("make") == KTC_MAKE and o.get("model") == KTC_MODEL)
    if len(ktc) < 2:
        return
    landscape, portrait = (ktc[0], ktc[1]) if LOWER_IS_LANDSCAPE else (ktc[1], ktc[0])

    # 横モニター（左）。y=967 は下端を縦モニターの物理高さに合わせた値。
    sway("output", landscape, "mode", "2560x1440", "position", "0", "967",
         "transform", "normal", "bg", SPAN + "/dp6.png", "fill")
    # 縦モニター（反時計回り90度 = transform 270）、右。
    sway("output", portrait, "mode", "2560x1440", "position", "2560", "0",
         "transform", "270", "bg", SPAN + "/dp5.png", "fill")


if __name__ == "__main__":
    main()
