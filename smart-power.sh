#!/system/bin/sh
##########################################################################################
# Smart power daemon (CPU/GPU caps, refresh rate, touch sampling, per-app profiles).
# Ported from OnePlus-Pad-90W-Smart-Charge, tuned for OnePlus Pad 2 Pro (SM8750).
# Started once at boot by service.sh. Controlled by SMART_POWER in config.txt
# (read at start; set SMART_POWER=0 and reboot to disable).
# Fast charging is handled in service.sh (fast-charge.sh), not here.
##########################################################################################

case "$0" in
    */*) MODDIR=${0%/*} ;;
    *) MODDIR=. ;;
esac
. "$MODDIR/power-data.sh"

load_config
[ "$SMART_POWER" = "1" ] || exit 0

LOG_FILE="$MODDIR/bypass.log"
PID_FILE="/data/local/tmp/smart_power_daemon.pid"
SDCARD_CFG_1="/sdcard/pure_powersave_games.txt"
SDCARD_CFG_2="/sdcard/game_whitelist.txt"
SDCARD_CFG_CASUAL="/sdcard/casual_powersave_games.txt"

CPU0="/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq"
CPU6="/sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq"
GPU="/sys/class/kgsl/kgsl-3d0/devfreq/max_freq"

# Single instance. Match the command line so a stale pid reused after reboot doesn't block us.
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && [ "$OLD_PID" != "$$" ] && grep -q smart-power "/proc/$OLD_PID/cmdline" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$PID_FILE"

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SMART_POWER] $1" >> "$LOG_FILE" 2>/dev/null
}

chmod 666 /proc/touchpanel/* "$CPU0" "$CPU6" "$GPU" 2>/dev/null

# set_caps <policy0 kHz> <policy6 kHz> <gpu Hz>
set_caps() {
    echo "$1" > "$CPU0" 2>/dev/null
    echo "$2" > "$CPU6" 2>/dev/null
    echo "$3" > "$GPU" 2>/dev/null
}

# set_refresh <peak Hz> <min Hz>
set_refresh() {
    settings put system peak_refresh_rate "$1" 2>/dev/null
    settings put system min_refresh_rate "$2" 2>/dev/null
}

set_touch_esports() {
    echo 1 > /proc/touchpanel/game_switch_enable 2>/dev/null
    echo 0 > /proc/touchpanel/sensitive_level 2>/dev/null
    echo 0 > /proc/touchpanel/smooth_level 2>/dev/null
    resetprop -n sys.input.resample.latency -1 2>/dev/null
    resetprop -n persist.vendor.qti.input.resampling 0 2>/dev/null
    resetprop -n view.touch_slop 4 2>/dev/null
}

# Same node values as esports; kept as a separate name for the streaming profile.
set_touch_low_latency() { set_touch_esports; }

set_touch_normal() {
    echo 0 > /proc/touchpanel/game_switch_enable 2>/dev/null
    echo 0 > /proc/touchpanel/sensitive_level 2>/dev/null
    echo 0 > /proc/touchpanel/smooth_level 2>/dev/null
    resetprop -n sys.input.resample.latency -1 2>/dev/null
    resetprop -n persist.vendor.qti.input.resampling 0 2>/dev/null
    resetprop -n view.touch_slop 8 2>/dev/null
}

set_sched_performance() {
    for w in /proc/sys/walt /proc/sys/kernel; do
        [ -f "$w/sched_downmigrate" ] && echo 40 > "$w/sched_downmigrate" 2>/dev/null
        [ -f "$w/sched_upmigrate" ] && echo 60 > "$w/sched_upmigrate" 2>/dev/null
        [ -f "$w/sched_boost" ] && echo 1 > "$w/sched_boost" 2>/dev/null
    done
}

set_sched_powersave() {
    for w in /proc/sys/walt /proc/sys/kernel; do
        [ -f "$w/sched_downmigrate" ] && echo 60 > "$w/sched_downmigrate" 2>/dev/null
        [ -f "$w/sched_upmigrate" ] && echo 85 > "$w/sched_upmigrate" 2>/dev/null
        [ -f "$w/sched_boost" ] && echo 0 > "$w/sched_boost" 2>/dev/null
    done
}

get_fg_app() {
    local focus_line=""
    focus_line=$(dumpsys window visible-apps 2>/dev/null | grep -m1 'mCurrentFocus')
    echo "$focus_line" | sed -n 's/.*[[:space:]]\([a-zA-Z0-9_.]*\)\/[^}]*}.*/\1/p'
}

is_video_app() {
    case "$1" in
        tv.danmaku.bili*|com.bilibili*|com.smile.gifmaker*|com.kuaishou*|com.ss.android.ugc.aweme*|com.ss.android.ugc.trill*|com.zhiliaoapp.musically*|com.google.android.youtube*|app.revanced*|com.tencent.qqlive*|com.qiyi.video*|com.youku*|com.hunantv.imgo*|org.videolan.vlc*|com.mxtech.videoplayer*|com.netflix.mediaclient*|com.amazon.avod*|com.disney.disneyplus*|com.clover.acfun*|com.huawei.himovie*|com.oppo.video*|com.coloros.video*)
            return 0 ;;
        *) return 1 ;;
    esac
}

is_streaming_app() {
    case "$1" in
        com.limelight*|com.valvesoftware.steamlink*|com.parsec.client*|com.chaozhuo.gameassistant*)
            return 0 ;;
        *) return 1 ;;
    esac
}

is_builtin_game() {
    case "$1" in
        com.netease.newspike|com.activision.callofduty.*|com.epicgames.fortnite|com.xiaoji.egggame|jp.sammynet.next.ort.a0001|com.tencent.tmgp.*|com.miHoYo.*|com.kurogame.*|org.yuzu.yuzu_emu*|org.sudachi.sudachi*)
            return 0 ;;
        *) return 1 ;;
    esac
}

is_casual_game() {
    case "$1" in
        com.yooyoo.dwby3d.*|com.tuyoo.*|*.fishing*|*.by3d*|com.pokercity.*|com.jj.*|com.tencent.tmgp.dld|com.tencent.tmgp.cfby|com.xiaomi.gamecenter.*)
            return 0 ;;
        *) return 1 ;;
    esac
}

# in_list <file> <package>: true if package appears in a non-comment line of file.
in_list() {
    [ -f "$1" ] && [ -n "$2" ] && grep -v '^[[:space:]]*#' "$1" 2>/dev/null | grep -q "$2"
}

CURRENT_MODE=""
log_info "Smart power daemon started (PID: $$)."

while true; do
    batt_status=$(cat /sys/class/power_supply/battery/status 2>/dev/null || echo "Discharging")
    batt_level=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "50")
    batt_temp_raw=$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo "300")
    batt_volt_uv=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo "3800000")
    batt_curr_raw=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo "0")

    batt_volt=$((batt_volt_uv / 1000))
    batt_temp_c=$((batt_temp_raw / 10))
    batt_temp_dec=$((batt_temp_raw % 10))

    dpms_state=$(cat /sys/class/drm/card0-DSI-1/dpms 2>/dev/null || echo "On")

    if [ "$dpms_state" != "On" ]; then
        if [ "$CURRENT_MODE" != "SCREEN_OFF" ]; then
            CURRENT_MODE="SCREEN_OFF"
            log_info "Screen off. Entering deep standby profile."
            set_caps 960000 1017600 160000000
            set_touch_normal
            set_sched_powersave
            dumpsys deviceidle step >/dev/null 2>&1
        fi
        POWER_DESC="Screen off (deep standby, Doze)"
        TOUCH_DESC="Paused (screen off)"
        curr_app="None (Screen Off)"
        sleep_interval=10
    else
        sleep_interval=3
        curr_app=$(get_fg_app)

        IS_CUSTOM_GAME=0
        if in_list "$SDCARD_CFG_1" "$curr_app" || in_list "$SDCARD_CFG_2" "$curr_app"; then
            IS_CUSTOM_GAME=1
        fi

        IS_CASUAL_GAME=0
        in_list "$SDCARD_CFG_CASUAL" "$curr_app" && IS_CASUAL_GAME=1

        if pgrep -x llama-server >/dev/null 2>&1; then
            # Local AI server running
            if [ "$CURRENT_MODE" != "AI_SERVER" ]; then
                CURRENT_MODE="AI_SERVER"
                log_info "Local AI server (llama-server) running. 3.28GHz Prime + 2.92GHz Perf."
                set_caps 2918400 3283200 1100000000
                set_sched_performance
                set_refresh 120.0 120.0
                echo 500 > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null
            fi
            POWER_DESC="Local AI inference (3.28GHz Prime, full boost)"
            TOUCH_DESC="Responsive touch (120Hz)"
        elif [ "$IS_CUSTOM_GAME" = "1" ] || is_builtin_game "$curr_app"; then
            # Heavy game: 3.28GHz Prime cap + 1100MHz GPU + 540Hz esports touch
            if [ "$CURRENT_MODE" != "GAME:$curr_app" ]; then
                CURRENT_MODE="GAME:$curr_app"
                log_info "Heavy game active [$curr_app]. 3.28GHz Prime cap + 540Hz esports touch."
                set_caps 2918400 3283200 1100000000
                set_touch_esports
                set_sched_performance
                set_refresh 120.0 120.0
                echo 500 > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null
            fi
            POWER_DESC="Esports performance (3.28GHz Prime, steady 120fps)"
            TOUCH_DESC="540Hz esports touch (0ms latency)"
        elif [ "$IS_CASUAL_GAME" = "1" ] || is_casual_game "$curr_app"; then
            # Casual 3D game: charging -> full speed, battery -> balanced caps
            if [ "$batt_status" = "Charging" ]; then
                if [ "$CURRENT_MODE" != "CASUAL_PLUGGED:$curr_app" ]; then
                    CURRENT_MODE="CASUAL_PLUGGED:$curr_app"
                    log_info "Casual 3D game [$curr_app] (CHARGING). 120Hz + 1100MHz GPU + 3.28GHz Prime."
                    set_touch_esports
                    set_sched_performance
                    set_refresh 120.0 120.0
                    echo 500 > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null
                fi
                set_caps 2918400 3283200 1100000000
                POWER_DESC="Casual 3D, charging (120Hz + 1100MHz GPU)"
                TOUCH_DESC="540Hz esports touch (0ms latency)"
            else
                if [ "$CURRENT_MODE" != "CASUAL_BATTERY:$curr_app" ]; then
                    CURRENT_MODE="CASUAL_BATTERY:$curr_app"
                    log_info "Casual 3D game [$curr_app] (BATTERY). 120Hz + 734MHz GPU + 2.44GHz Prime."
                    set_touch_normal
                    set_sched_powersave
                    set_refresh 120.0 60.0
                    echo 1000 > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null
                fi
                set_caps 2227200 2438400 734000000
                POWER_DESC="Casual 3D, battery (120Hz max, 734MHz GPU)"
                TOUCH_DESC="Power-saving touch (120Hz sampling)"
            fi
        elif is_streaming_app "$curr_app"; then
            # Moonlight / Steam Link
            if [ "$CURRENT_MODE" != "STREAMING:$curr_app" ]; then
                CURRENT_MODE="STREAMING:$curr_app"
                log_info "Streaming app [$curr_app]. Low touch latency + 120Hz."
                set_caps 2400000 2649600 734000000
                set_touch_low_latency
                set_sched_performance
                set_refresh 120.0 120.0
            fi
            POWER_DESC="Low-latency streaming (120Hz, low-power decode)"
            TOUCH_DESC="Low-latency streaming touch"
        elif is_video_app "$curr_app"; then
            # Video: 60Hz lock + media powersave
            if [ "$CURRENT_MODE" != "VIDEO:$curr_app" ]; then
                CURRENT_MODE="VIDEO:$curr_app"
                log_info "Video app [$curr_app]. 60Hz lock and media powersave."
                set_caps 1785600 1689600 443000000
                set_touch_normal
                set_sched_powersave
                set_refresh 60.0 60.0
                echo 1500 > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null
            fi
            POWER_DESC="Video power saving (60Hz lock, hardware decode)"
            TOUCH_DESC="Power-saving touch (120Hz sampling)"
        else
            # Daily / balanced
            if [ "$CURRENT_MODE" != "DAILY" ]; then
                CURRENT_MODE="DAILY"
                log_info "Daily app. 120Hz UI + 2.44GHz Prime cap."
                set_caps 2227200 2438400 1100000000
                set_touch_normal
                set_sched_powersave
                set_refresh 120.0 120.0
                echo 1000 > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null
            fi
            POWER_DESC="Daily (120Hz UI, 2.44GHz Prime cap)"
            TOUCH_DESC="Power-saving touch (120Hz sampling)"
        fi
    fi

    CHARGE_DESC=$(cat "$FAST_CHARGE_STATE_FILE" 2>/dev/null)
    [ -z "$CHARGE_DESC" ] && CHARGE_DESC="N/A"

    cat << JSON > "$POWER_STATUS_JSON.tmp"
{
  "charge_state": "$CHARGE_DESC",
  "power_profile": "$POWER_DESC",
  "touch_sampling_mode": "$TOUCH_DESC",
  "battery_level": $batt_level,
  "battery_temp": "$batt_temp_c.$batt_temp_dec",
  "battery_voltage_mv": $batt_volt,
  "battery_current_ma": $batt_curr_raw,
  "foreground_app": "$curr_app",
  "mode": "$CURRENT_MODE",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
JSON
    mv "$POWER_STATUS_JSON.tmp" "$POWER_STATUS_JSON" 2>/dev/null
    chmod 644 "$POWER_STATUS_JSON" 2>/dev/null

    sleep "$sleep_interval"
done
