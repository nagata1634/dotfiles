#!/bin/sh
# KDE Plasma 6 のkscreenlocker/KWinには、蓋を閉じた状態でロック解除すると
# 出力構成が内蔵ディスプレイ(eDP-1)込みでリセットされる既知の不具合がある
# (bugs.kde.org #363238, #450757 等と同系統)。アンロックの度に蓋の状態を見て
# 閉じていれば内蔵ディスプレイを強制的に無効化し直す。

LID_STATE_FILE=$(ls /proc/acpi/button/lid/*/state 2>/dev/null | head -n1)

gdbus monitor --session --dest org.freedesktop.ScreenSaver 2>/dev/null |
while IFS= read -r line; do
  case "$line" in
    *ActiveChanged*false*)
      [ -n "$LID_STATE_FILE" ] || continue
      lid_state=$(awk '{print $2}' "$LID_STATE_FILE" 2>/dev/null)
      if [ "$lid_state" = "closed" ]; then
        # KWin側の出力再構成が完了してから上書きする
        sleep 1
        kscreen-doctor output.eDP-1.disable
      fi
      ;;
  esac
done
