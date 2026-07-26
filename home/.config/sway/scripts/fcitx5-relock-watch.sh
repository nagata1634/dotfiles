#!/usr/bin/env bash
# gtklock によるロック→解除を検知して fcitx5 を再起動する。
#
# 背景: gtklock は ext-session-lock プロトコルで画面をロックする。解除後、
# fcitx5 の Wayland text-input(wayland_v2 frontend)接続が切れたまま復帰せず、
# IME が無反応になる。full restart で再接続させるのが確実な対処。
#
# 起動経路(swayidle の timeout / lock / before-sleep いずれも gtklock -d)に
# 依存しないよう、logind の Unlock シグナルではなく gtklock プロセスの
# ライフサイクルを監視する。fcitx5-relock-watch.service から起動される。
set -u

UNIT="app-org.fcitx.Fcitx5@autostart.service"

while :; do
    # ロックされる(gtklock が現れる)まで待つ
    until pgrep -xu "$USER" gtklock >/dev/null 2>&1; do
        sleep 2
    done
    # 解除される(gtklock が消える)まで待つ
    while pgrep -xu "$USER" gtklock >/dev/null 2>&1; do
        sleep 1
    done
    # 解除された → IME を再接続
    systemctl --user restart "$UNIT"
    # 直後の再ロックによるばたつき防止
    sleep 2
done
