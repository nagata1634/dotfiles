#!/usr/bin/env python3
"""現在フォーカス中のワークスペース内のウィンドウを選んでフォーカスする。

ピッカーは rofi。日本語ウィンドウタイトルを「打って」絞り込めるようにするため
（rofi は XWayland 上で動き、fcitx5 の X Input Method(XIM) 経由で日本語変換入力が通る）。
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import rofi


def pick(menu, prompt):
    """改行区切りの候補から選択させ、選ばれた行の 0始まり index を返す（未選択は None）。"""
    return rofi.dmenu(menu, prompt=prompt, index=True)


def focused_ws(node):
    if node.get("type") == "workspace":
        if '"focused":true' in json.dumps(node, separators=(",", ":")):
            return node
    for c in node.get("nodes", []) + node.get("floating_nodes", []):
        r = focused_ws(c)
        if r:
            return r
    return None


def walk(node, items):
    app = node.get("app_id") or (node.get("window_properties") or {}).get("class")
    is_leaf = not (node.get("nodes") or node.get("floating_nodes"))
    if app and is_leaf:
        items.append((node["id"], "%s: %s" % (app, node.get("name") or "")))
    for c in node.get("nodes", []) + node.get("floating_nodes", []):
        walk(c, items)


def main():
    tree = json.loads(subprocess.check_output(["swaymsg", "-t", "get_tree"]))
    ws = focused_ws(tree)
    items = []
    if ws:
        walk(ws, items)
    if not items:
        return
    menu = "\n".join(label for _, label in items)
    idx = pick(menu, "Window")
    if idx is None:
        return
    con_id = items[idx][0]
    subprocess.run(["swaymsg", "[con_id=%d]" % con_id, "focus"])


if __name__ == "__main__":
    main()
