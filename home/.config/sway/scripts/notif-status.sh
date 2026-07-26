#!/usr/bin/env bash
# Waybar 用：通知の状態をベルアイコンで返す。
# 通常=󰂚 / おやすみモード(停止中)=󰂛
[ "$(dunstctl is-paused 2>/dev/null)" = "true" ] && echo "󰂛" || echo "󰂚"
