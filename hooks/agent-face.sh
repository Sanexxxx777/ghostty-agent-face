#!/bin/bash
# agent-face.sh — сигнал статуса агента терминалу Ghostty через фон (OSC 11)
# Состояния: run|done|attn|work|dizzy|helpers|reset
# Хук-процесс без controlling tty — tty ищем подъёмом по цепочке родителей.
# После каждой отправки цвета перезапускается сторож agent-face-watch.sh
# (краш-детект + автосон + сброс по нажатию клавиши).

# Пауза до установки шейдера-перекрасчика (иначе фон видимо мигает).
# Включить обратно: удалить файл ~/.claude/hooks/agent-face.disabled
[ -e "$HOME/.claude/hooks/agent-face.disabled" ] && exit 0

# Сигналы = НЕВИДИМЫЕ сдвиги +5/255 от фона темы #282c34 (40,44,52).
# Глаз разницу не видит ни при каких обстоятельствах, шейдер отличает точно.
COLOR_RUN="#2D2C34"
COLOR_DONE="#282C39"
COLOR_ATTN="#2D3134"
COLOR_WORK="#283134"
COLOR_DIZZY="#2D2C39"
COLOR_SLEEP="#283139"
COLOR_HELPERS="#2D3139"

# Возвращает пару "tty pid" — pid предка, на котором tty был найден
# (нужен сторожу как ANCHOR_PID для краш-детекта).
find_tty() {
    local pid="$1"
    local i=0
    local tty
    while [ "$i" -lt 15 ]; do
        if [ -z "$pid" ] || [ "$pid" = "0" ] || [ "$pid" = "1" ]; then
            return 1
        fi
        tty=$(lsof -p "$pid" -a -d 0,1,2 2>/dev/null | grep -Eo '/dev/ttys[0-9]+' | head -1)
        if [ -n "$tty" ]; then
            printf '%s %s' "$tty" "$pid"
            return 0
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        i=$((i + 1))
    done
    return 1
}

state="$1"
# pre = PreToolUse: по tool_name из stdin-JSON различаем субагентов (helpers) и остальные тулы (work)
if [ "$state" = "pre" ]; then
    state="work"
    if [ ! -t 0 ]; then
        hook_json=$(cat 2>/dev/null)
        case "$hook_json" in
            *'"tool_name":"Agent"'*|*'"tool_name":"Task"'*|*'"tool_name":"Workflow"'*) state="helpers" ;;
        esac
    fi
fi

case "$state" in
    run)     color="$COLOR_RUN" ;;
    done)    color="$COLOR_DONE" ;;
    attn)    color="$COLOR_ATTN" ;;
    work)    color="$COLOR_WORK" ;;
    dizzy)   color="$COLOR_DIZZY" ;;
    sleep)   color="$COLOR_SLEEP" ;;
    helpers) color="$COLOR_HELPERS" ;;
    reset)   color="" ;;
    *) exit 0 ;;
esac

tty_info=$(find_tty "$$")
[ -n "$tty_info" ] || exit 0
tty_path=${tty_info% *}
anchor_pid=${tty_info#* }

if [ "$state" = "reset" ]; then
    pkill -f "agent-face-watch.sh $tty_path" 2>/dev/null
    printf '\033]111\007' > "$tty_path" 2>/dev/null
else
    if printf '\033]11;%s\007' "$color" > "$tty_path" 2>/dev/null; then
        pkill -f "agent-face-watch.sh $tty_path" 2>/dev/null
        (setsid bash $HOME/.claude/hooks/agent-face-watch.sh "$tty_path" "$anchor_pid" "$state" >/dev/null 2>&1 &)
    fi
fi

exit 0
