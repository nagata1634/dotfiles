#!/usr/bin/env python3
"""蓋を閉じたときにログアウトすべきかを判定するだけの述語。副作用は持たない。

sway-lid-logout.service の ExecCondition= から（＝swayidle の before-sleep 経由で）呼ばれる。

  exit 0 : 蓋が閉じていて、内蔵(eDP-1)以外に有効な出力が無い → ログアウトする
  exit 1 : それ以外（蓋が開いている＝アイドルによるサスペンド、または外部モニタあり）

蓋の状態は logind に聞く。sway の bindswitch による `output eDP-1 disable` と
before-sleep はほぼ同時に走るため、「有効な出力が無いこと」だけを見ると
eDP-1 の無効化が間に合っていないときに取りこぼす。
"""
import json
import subprocess
import sys

INTERNAL = "eDP-1"


def lid_closed() -> bool:
    try:
        out = subprocess.check_output(
            ["busctl", "get-property", "org.freedesktop.login1",
             "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "LidClosed"],
            stderr=subprocess.DEVNULL, text=True, timeout=5)
    except Exception:
        return False
    return out.strip() == "b true"


def has_external_output() -> bool:
    try:
        out = subprocess.check_output(
            ["swaymsg", "-t", "get_outputs"],
            stderr=subprocess.DEVNULL, text=True, timeout=5)
        outputs = json.loads(out)
    except Exception:
        # 判定できないときは「外部あり」に倒す（意図しないログアウトを防ぐ）
        return True
    return any(o.get("active") and o.get("name") != INTERNAL for o in outputs)


sys.exit(0 if lid_closed() and not has_external_output() else 1)
