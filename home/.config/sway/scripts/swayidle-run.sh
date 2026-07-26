#!/usr/bin/env bash
# swayidle 本体（swayidle.service から起動）。ロックは gtklock。
# アイドル 300s→ロック、360s→画面OFF、900s→サスペンド(s2idle)。サスペンド前ロック。
exec swayidle -w \
    timeout 300 'gtklock -d' \
    timeout 360 'swaymsg "output * power off"' \
          resume 'swaymsg "output * power on"' \
    timeout 60  'pgrep -xu "$USER" gtklock >/dev/null && swaymsg "output * power off"' \
         resume 'pgrep -xu "$USER" gtklock >/dev/null && swaymsg "output * power on"' \
    timeout 900 'systemctl suspend' \
    before-sleep 'gtklock -d' \
    lock 'gtklock -d'
