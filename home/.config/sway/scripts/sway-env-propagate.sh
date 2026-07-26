#!/bin/sh
# sway セッションの環境変数を systemd --user と D-Bus アクティベーション環境へ伝播する。
# 詳細は ~/.dotfiles/CLAUDE.md の「ロケール分離」「常駐ツールの起動元」を参照。
set -eu

SRC="${XDG_CONFIG_HOME:-$HOME/.config}/locale.env"
if [ -r "$SRC" ]; then
    set -a
    . "$SRC"
    set +a
else
    echo "sway-env-propagate: $SRC が読めません。ロケールは継承値を使います" >&2
fi

# --systemd を付けると systemd --user と D-Bus の両方に入る。
# 未設定の変数名を渡しても無害（スキップして exit 0）。
exec dbus-update-activation-environment --systemd \
    DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP \
    LANG LANGUAGE LC_ALL LC_CTYPE LC_MESSAGES LC_COLLATE \
    LC_TIME LC_NUMERIC LC_MONETARY LC_PAPER LC_NAME LC_ADDRESS \
    LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION
