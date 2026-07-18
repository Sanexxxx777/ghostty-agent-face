#!/bin/bash
# agent-face.sh — сигнал статуса агента терминалу Ghostty через фон (OSC 11)
# Состояния: run|done|attn|reset
# Хук-процесс без controlling tty — tty ищем подъёмом по цепочке родителей.

# Пауза до установки шейдера-перекрасчика (иначе фон видимо мигает).
# Включить обратно: удалить файл ~/.claude/hooks/agent-face.disabled
[ -e "$HOME/.claude/hooks/agent-face.disabled" ] && exit 0

COLOR_RUN="#332308"
COLOR_DONE="#0A331A"
COLOR_ATTN="#33110A"

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
            printf '%s' "$tty"
            return 0
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        i=$((i + 1))
    done
    return 1
}

case "$1" in
    run)   color="$COLOR_RUN" ;;
    done)  color="$COLOR_DONE" ;;
    attn)  color="$COLOR_ATTN" ;;
    reset) color="" ;;
    *) exit 0 ;;
esac

tty_path=$(find_tty "$$")
[ -n "$tty_path" ] || exit 0

if [ "$1" = "reset" ]; then
    printf '\033]111\007' > "$tty_path" 2>/dev/null
else
    printf '\033]11;%s\007' "$color" > "$tty_path" 2>/dev/null
fi

exit 0
