#!/bin/bash
# systemd-sleep フック本体（設置先: /etc/systemd/system-sleep/trackpad-usb-reset.sh）
# Apple Magic Trackpad (USB 05ac:0265) を復帰後に unbind→bind して
# 再認識させる（物理的な電源入れ直しの代替）。root で実行される。
#
# systemd-sleep 引数: $1=pre|post  $2=suspend|hibernate|...
case "$1" in
  post)
    for d in /sys/bus/usb/devices/*/; do
      [ -f "$d/idVendor" ] || continue
      if [ "$(cat "$d/idVendor" 2>/dev/null)" = "05ac" ] && \
         [ "$(cat "$d/idProduct" 2>/dev/null)" = "0265" ]; then
        dev=$(basename "$d")
        echo "$dev" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null
        sleep 1
        echo "$dev" > /sys/bus/usb/drivers/usb/bind 2>/dev/null
        logger -t trackpad-usb-reset "reset USB device $dev after resume"
      fi
    done
    ;;
esac
exit 0
