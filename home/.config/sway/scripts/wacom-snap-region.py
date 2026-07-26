#!/usr/bin/env python3
"""フォーカス中の窓に Wacom の書き込み範囲(map_to_region)を合わせる。

タブレット実面比 1.6:1（Intuos M ≒ 216×135mm）を保ったまま、フォーカス中の
窓の矩形へ「内接する最大の 1.6:1 矩形」を割り当てる。窓がタイルで下に来ても、
フローティングでも、この 1 キーで書き込み範囲がその窓に追従する。

- 比率は常に固定（窓が 1.6:1 でなければ窓内に中央寄せ＝レターボックス）。
- 向き補正(calibration_matrix)は 45-wacom.conf 側で設定済み。ここは範囲のみ変更。
- 窓自体を約 1.6:1（例 1440×900）にしておくと窓＝書き込み枠がぴったり一致。
"""
import json
import subprocess
import sys

# Wacom Intuos M 実面: 216×135mm。時計回り90°の縦置きで使うため、
# 画面上の書き込み枠は縦長になる（横:縦 = 短辺135:長辺216 = 0.625）。
# ※持ち方(横置き等)を変えたらこの比を入れ替える（横置きなら 216/135）。
ASPECT_W = 135
ASPECT_H = 216
ASPECT = ASPECT_W / ASPECT_H


def get_tree():
    out = subprocess.run(
        ["swaymsg", "-t", "get_tree"], capture_output=True, text=True, check=True
    ).stdout
    return json.loads(out)


def find_focused(node):
    if node.get("focused"):
        return node
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        r = find_focused(child)
        if r:
            return r
    return None


def main():
    f = find_focused(get_tree())
    if not f:
        sys.exit("フォーカス中の窓が見つかりません")
    r = f["rect"]  # layout 絶対座標（装飾込みの矩形）
    X, Y, W, H = r["x"], r["y"], r["width"], r["height"]

    # 窓の中へ 1.6:1 の最大矩形を内接（中央寄せ）
    if W / H > ASPECT:      # 窓が横長すぎ → 高さ基準
        h = H
        w = int(round(h * ASPECT))
    else:                    # 窓が縦長 or ちょうど → 幅基準
        w = W
        h = int(round(w / ASPECT))
    x = X + (W - w) // 2
    y = Y + (H - h) // 2

    subprocess.run(
        ["swaymsg", "input", "type:tablet_tool",
         "map_to_region", str(x), str(y), str(w), str(h)],
        check=True,
    )
    # 通知が使える環境なら軽く知らせる（無ければ無視）
    subprocess.run(
        ["notify-send", "-t", "1500", "Wacom",
         f"書き込み範囲を窓に合わせました {w}×{h}"],
        capture_output=True,
    )


if __name__ == "__main__":
    main()
