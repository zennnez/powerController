#!/system/bin/sh

USB_ONLINE_NODE="/sys/class/power_supply/usb/online"

if [ -r "$USB_ONLINE_NODE" ]; then
    tr -d '\r\n' < "$USB_ONLINE_NODE"
else
    printf '%s' "0"
fi
