#!/usr/bin/env python3
"""DP-5 と DP-6 の役割（横/左 ⇄ 縦/右）を入れ替えるトグル。

この2台は同一型番・EDIDシリアル無しでソフトから区別できず、起動時に DP番号と物理
モニターの対応が入れ替わることがある。配置がズレたらキー一発でこれを実行して直す。
縦モニター（右）には Wacom も map_to_output で貼り直す（全画面追従）。
"""
import json
import os
import subprocess

BG_DIR = os.path.expanduser("~/Pictures/background/.span")


def swaymsg(cmd):
    subprocess.run(["swaymsg", cmd], stdout=subprocess.DEVNULL)


def apply_h(output):
    """横モニター（左）として設定。"""
    swaymsg(f"output {output} mode 2560x1440 position 0 967 transform normal "
            f"bg {BG_DIR}/dp6.png fill")


def apply_v(output):
    """縦モニター（右・反時計回り90度=transform 270）として設定。Wacomも追従。"""
    swaymsg(f"output {output} mode 2560x1440 position 2560 0 transform 270 "
            f"bg {BG_DIR}/dp5.png fill")
    swaymsg(f"input type:tablet_tool map_to_output {output}")


def main():
    outs = json.loads(subprocess.check_output(["swaymsg", "-t", "get_outputs"]))
    # DP-5 が normal(横) なら「DP-5=横/左」の状態 → 反転する必要あり
    t5 = next((o["transform"] for o in outs if o["name"] == "DP-5"), "")
    if t5 == "normal":
        apply_v("DP-5")
        apply_h("DP-6")
    else:
        apply_h("DP-5")
        apply_v("DP-6")


if __name__ == "__main__":
    main()
