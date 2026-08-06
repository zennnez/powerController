#!/system/bin/sh

MODDIR=${0%/*}

chmod 755 "$MODDIR/service.sh"
chmod 755 "$MODDIR/uninstall.sh"
chmod 755 "$MODDIR/get-status.sh"
chmod 755 "$MODDIR/get-usb-online.sh"
chmod 755 "$MODDIR/set-config.sh"
chmod 755 "$MODDIR/power-data.sh"
chmod 755 "$MODDIR/get-log.sh"
chmod 755 "$MODDIR/clear-log.sh"
