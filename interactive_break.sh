#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_break_dialog() {
    local exercise="$1"
    
    local result_file=$(mktemp)
    
    if command -v zenity &>/dev/null; then
        zenity --question \
            --title="Время разминки! 💪" \
            --text="<span size='x-large' weight='bold'>$exercise</span>\n\nПрошло 3 часа работы. Рекомендуется сделать перерыв!\n\nПродолжить работу?" \
            --ok-label="Сделал перерыв" \
            --cancel-label="Напомнить через 5 мин" \
            --width=400 \
            --height=200
        
        local result=$?
        echo $result > "$result_file"
    else
        echo -e "${YELLOW}================================================================${NC}"
        echo -e "${GREEN}🎯 ВРЕМЯ РАЗМИНКИ! 💪${NC}"
        echo -e "${YELLOW}================================================================${NC}"
        echo -e "${BLUE}$exercise${NC}"
        echo -e "${YELLOW}================================================================${NC}"
        echo -e "Прошло 3 часа работы. Рекомендуется сделать перерыв!"
        echo -e "1 - Сделал перерыв"
        echo -e "2 - Напомнить через 5 минут"
        echo -e "3 - Пропустить это напоминание"
        read -p "Выберите действие (1-3): " choice
        
        case $choice in
            1) echo 0 > "$result_file" ;;
            2) echo 1 > "$result_file" ;;
            *) echo 2 > "$result_file" ;;
        esac
    fi
    
    local result=$(cat "$result_file")
    rm -f "$result_file"
    return $result
}

check_user_active() {
    local idle_time=$(xprintidle 2>/dev/null || echo 0)
    if [ $idle_time -gt 60000 ]; then
        return 1
    fi
    return 0
}

main() {
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
    local exercise="${exercises[$index]}"
    
    if command -v paplay &>/dev/null; then
        for i in {1..3}; do
            paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || true
            sleep 0.5
        done
    fi

    if ! check_user_active; then
        exit 0
    fi
    
    show_break_dialog "$exercise"
    local result=$?
    
    case $result in
        0)
            if command -v notify-send &>/dev/null; then
                notify-send "Отлично! 👍" "Хорошего продолжения работы!" --icon=dialog-ok
            fi
            ;;
        1)
            if command -v notify-send &>/dev/null; then
                notify-send "Напоминание через 5 мин ⏰" "Не забудьте сделать перерыв!" --icon=dialog-warning
            fi
            sleep 300 
            main 
            ;;
        *)
            if command -v notify-send &>/dev/null; then
                notify-send "Напоминание пропущено" "Следующее напоминание через 3 часа" --icon=dialog-information
            fi
            ;;
    esac
}

main "$@"