#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"

log_break_message() {
    local message="$1"
    local level="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/break_reminder.log"
}

get_random_exercise() {
    local exercises=(
        "Встаньте и потянитесь вверх 5 раз"
        "Сделайте вращения головой: 5 раз вправо, 5 раз влево"
        "Помассируйте плечи и шею в течение 30 секунд"
        "Сделайте 10 приседаний"
        "Посмотрите в окно вдаль в течение 1 минуты"
        "Сделайте вращения глазами: вверх-вниз, влево-вправо"
        "Встаньте и походите 2 минуты"
        "Сделайте растяжку для запястий"
        "Глубоко подышите 1 минуту"
        "Сделайте наклоны головы к плечам"
    )
    
    local count=${#exercises[@]}
    local index=$((RANDOM % count))
    echo "${exercises[$index]}"
}

main() {
    local exercise=$(get_random_exercise)
    local message="💪 Время разминки! $exercise"
    
    log_break_message "Напоминание: $exercise" "INFO"
    
    if command -v notify-send &>/dev/null; then
        notify-send -u normal "Время разминки!" "$exercise" -t 10000
    fi
    
    echo -e "${GREEN}🎯 $message${NC}"
    
    if command -v paplay &>/dev/null; then
        paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null || true
    fi
}

main "$@"