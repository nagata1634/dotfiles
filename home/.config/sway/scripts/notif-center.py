#!/usr/bin/env python3
"""Rofi 通知センター（Nord 統一テーマ）。

dunst の履歴を一覧表示し、選ぶと再表示。おやすみモード切替・全消去も。
Mod+Shift+n、または Waybar のベルアイコンから起動。
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import rofi

ICONS = {"low": "󰋽", "normal": "󰂚", "critical": "󰀦"}


def _uptime():
    try:
        return float(open("/proc/uptime").read().split()[0])
    except Exception:
        return None


def _age(ts_us, up):
    if up is None or not ts_us:
        return ""
    s = up - ts_us / 1e6
    if s < 0:
        return ""
    if s < 60:
        return "%d秒前" % s
    if s < 3600:
        return "%d分前" % (s // 60)
    if s < 86400:
        return "%d時間前" % (s // 3600)
    return "%d日前" % (s // 86400)


def history_entries():
    """(id, 表示ラベル) のリストを返す（新しい順は dunst の履歴順に従う）。"""
    try:
        out = subprocess.check_output(["dunstctl", "history"], text=True)
        d = json.loads(out)
    except Exception:
        return []
    up = _uptime()
    data = d.get("data", [])
    notes = data[0] if data else []
    result = []
    for n in notes:
        g = lambda k: (n.get(k) or {}).get("data")
        icon = ICONS.get(g("urgency"), "󰂚")
        app = (g("appname") or "").strip()
        summ = (g("summary") or "").replace("\n", " ")
        body = (g("body") or "").replace("\n", " ")
        parts = [icon]
        if app:
            parts.append("[" + app + "]")
        if summ:
            parts.append(summ)
        if body:
            parts.append("— " + body)
        label = " ".join(parts)
        if len(label) > 95:
            label = label[:94] + "…"
        a = _age(g("timestamp") or 0, up)
        if a:
            label += "  (" + a + ")"
        result.append((g("id"), label))
    return result


def main():
    paused = subprocess.run(["dunstctl", "is-paused"],
                            capture_output=True, text=True).stdout.strip()
    dnd = "󰂚  おやすみモードを切替（現在: 通常）"
    if paused == "true":
        dnd = "󰂜  おやすみモードを切替（現在: 停止中）"

    entries = history_entries()
    count = len(entries)
    lines = [label for _id, label in entries] if entries else ["󰂜  （通知はありません）"]
    items = lines + [dnd, "󰎟  すべてクリア", "󰑐  最新を再表示"]

    choice = rofi.dmenu(items, prompt=f"通知センター ({count})", no_custom=True)
    if not choice:
        return

    if "おやすみモード" in choice:
        subprocess.run(["dunstctl", "set-paused", "toggle"])
    elif "すべてクリア" in choice:
        subprocess.run(["dunstctl", "history-clear"])
    elif "最新を再表示" in choice:
        subprocess.run(["dunstctl", "history-pop"])
    elif "通知はありません" in choice:
        pass
    else:
        for _id, label in entries:
            if label == choice:
                subprocess.run(["dunstctl", "history-pop", str(_id)])
                break


if __name__ == "__main__":
    main()
