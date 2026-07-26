#!/usr/bin/env bash
# Rnote クイックメモ ($mod+F6 用)
#
# ~/Pictures/Rnote/ にタイムスタンプ名の新規 .rnote を作って Rnote で即開く。
# 「ぱっと手書きメモを取りたい」とき用。押すたびに新しいメモが増える。
#
# 書式は A4 + Fixed Size 固定にしたいので、設定済みテンプレートを cp して開く方式。
#   テンプレ: ~/.config/sway/assets/rnote-a4-fixed.rnote
#            (A4 793.701x1122.52 / portrait / layout=fixed_size / 背景=lines、中身は空)
#   テンプレの作り直し方: Rnoteで好みの書式の空ノートを保存し、その .rnote を
#   上記パスへ上書きコピーするだけ（中身のストロークは無くてOK）。
#
# 注意: rnote(Flatpak)は xdg-pictures 権限を持つので ~/Pictures 配下は開ける。
#       保存先を変える場合も xdg-pictures/xdg-documents 内にすること
#       （~/.cache 等サンドボックス外だと開けない/作れない）。
set -euo pipefail

APP=com.github.flxzt.rnote
DIR="$HOME/Pictures/Rnote"
TEMPLATE="$HOME/.config/sway/assets/rnote-a4-fixed.rnote"
mkdir -p "$DIR"

FILE="$DIR/memo-$(date +%Y-%m-%d_%H%M%S).rnote"

# テンプレがあれば A4+FixedSize でコピー、無ければ素の空ノートを生成（保険）
if [ -r "$TEMPLATE" ]; then
    cp "$TEMPLATE" "$FILE"
else
    flatpak run --command=rnote-cli "$APP" create "$FILE"
fi

# GUI で開く（file-forwarding: @@ でファイル引数を囲む）
exec flatpak run --file-forwarding "$APP" @@ "$FILE" @@
