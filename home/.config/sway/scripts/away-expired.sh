#!/usr/bin/env bash
# 離席が長すぎるかを判定するだけの述語。真偽を返し、副作用は持たない。
# sway-away-check.service の ExecCondition= から呼ばれる。
#
#   exit 0 : $SWAY_AWAY_LIMIT 秒（既定 10800 = 3時間）以上たっている → ログアウトする
#   exit 1 : まだ / 記録が無い / 記録が壊れている → 何もしない
#
# 実時刻(epoch)の差で測る。単調時計ではサスペンド中の経過が数えられないため。
set -u

MARK="${XDG_RUNTIME_DIR:?}/sway-away-since"
LIMIT="${SWAY_AWAY_LIMIT:-10800}"

[ -r "$MARK" ] || exit 1
read -r since < "$MARK" || exit 1
case "$since" in
    '' | *[!0-9]*) exit 1 ;;
esac

[ $(($(date +%s) - since)) -ge "$LIMIT" ]
