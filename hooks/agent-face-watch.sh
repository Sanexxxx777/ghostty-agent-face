#!/bin/bash
# agent-face-watch.sh — сторож фона морды: краш-детект + автосон + сброс по активности
# Вызов: agent-face-watch.sh <TTY> <ANCHOR_PID> <STATE>
# STATE: run|done|attn|work|dizzy|helpers (sleep — внутреннее переключение из done)

tty="$1"
anchor_pid="$2"
state="$3"

[ -n "$tty" ] && [ -n "$anchor_pid" ] && [ -n "$state" ] || exit 0

start_ts=$(date +%s)
tick=0
max_ticks=240

reset_face() {
    printf '\033]111\007' > "$tty" 2>/dev/null
}

while [ "$tick" -lt "$max_ticks" ]; do
    kill -0 "$anchor_pid" 2>/dev/null || { reset_face; exit 0; }

    if [ "$state" = "done" ] || [ "$state" = "sleep" ]; then
        atime=$(stat -f %a "$tty" 2>/dev/null)
        if [ -n "$atime" ] && [ "$atime" -gt "$start_ts" ]; then
            reset_face
            exit 0
        fi
    fi

    if [ "$state" = "done" ]; then
        now=$(date +%s)
        elapsed=$((now - start_ts))
        if [ "$elapsed" -ge 1800 ]; then
            printf '\033]11;#282F37\007' > "$tty" 2>/dev/null
            state="sleep"
        fi
    fi

    sleep 20
    tick=$((tick + 1))
done

exit 0
