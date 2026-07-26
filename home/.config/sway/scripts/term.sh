#!/usr/bin/env bash
# ターミナル起動ラッパー（Super+Return / rofi -terminal / power-menu などで使用）。
# foot を server/client 構成で使う: footclient が foot-server.socket(systemd) 経由で
# 常駐サーバへ接続するため、ウィンドウ生成が速い。サーバ未起動時は単体 foot に
# フォールバックするので、socket が落ちていても端末は必ず開く。
#
# 呼び出し互換（過去の wezterm ラッパー時代の形式をそのまま受ける）:
#   - rofi -terminal:  term.sh -e <command...>      （-e は foot/footclient が無視）
#   - power-menu.py:   term.sh start -- <command...>（wezterm 風 start を読み飛ばす）

# wezterm の `start` サブコマンドを吸収（foot にはサブコマンドが無い）。
[ "${1:-}" = "start" ] && shift

# systemd の foot-server.socket は %t/foot.sock（= $XDG_RUNTIME_DIR/foot.sock）を待受。
sock="${XDG_RUNTIME_DIR}/foot.sock"
if [ -S "$sock" ]; then
  exec footclient --server-socket="$sock" "$@"
else
  exec foot "$@"
fi
