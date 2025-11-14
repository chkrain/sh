#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
CONFIG_DIR="$SCRIPT_DIR/config"
PID_FILE="$SCRIPT_DIR/system_manager.pid"

mkdir -p "$LOG_DIR" "$CONFIG_DIR"

load_config() {
    local config_file="$CONFIG_DIR/system_manager.conf"
    
    if [ ! -f "$config_file" ]; then
        cat > "$config_file" << EOF
# Интервалы проверок (в секундах)
DISK_CHECK_INTERVAL=86400      # 24 часа
GIT_CHECK_INTERVAL=7200        # 2 часа  
BREAK_REMINDER_INTERVAL=3600   # 1 час
NETWORK_CHECK_INTERVAL=300     # 5 минут

# Настройки уведомлений
ENABLE_DESKTOP_NOTIFICATIONS=true
ENABLE_LOGGING=true
LOG_RETENTION_DAYS=7

# Пороги
DISK_WARNING_THRESHOLD=30
DISK_CRITICAL_THRESHOLD=15
NETWORK_TIMEOUT=2
EOF
    fi
    
    source "$config_file"
}

log_message() {
    local message="$1"
    local level="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $message"
    
    if [ "$ENABLE_LOGGING" = "true" ]; then
        echo "$log_entry" >> "$LOG_DIR/system_manager.log"
    fi
    
    echo -e "${BLUE}[$timestamp]${NC} $level: $message"
}

send_notification() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"
    
    if [ "$ENABLE_DESKTOP_NOTIFICATIONS" = "true" ] && command -v notify-send &> /dev/null; then
        notify-send -u "$urgency" "$title" "$message"
    fi
    
    log_message "$title: $message" "NOTIFICATION"
}

check_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Демон уже запущен (PID: $pid)"
            exit 1
        else
            rm -f "$PID_FILE"
        fi
    fi
}

run_script_with_timeout() {
    local script_name="$1"
    local script_path="$2"
    local timeout="${3:-300}"  
    
    if [ ! -f "$script_path" ]; then
        log_message "Скрипт $script_name не найден: $script_path" "ERROR"
        return 1
    fi
    
    log_message "Запуск $script_name..." "INFO"
    
    if timeout "$timeout" bash "$script_path"; then
        log_message "$script_name завершен успешно" "SUCCESS"
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_message "$script_name превысил время выполнения ($timeout сек)" "WARNING"
        else
            log_message "$script_name завершился с ошибкой: $exit_code" "ERROR"
        fi
        return $exit_code
    fi
}

cleanup_old_logs() {
    find "$LOG_DIR" -name "*.log" -type f -mtime +$LOG_RETENTION_DAYS -delete
}

main_loop() {
    log_message "Запуск системного демона" "START"
    
    local last_disk_check=0
    local last_git_check=0
    local last_break_reminder=0
    local last_network_check=0
    
    while true; do
        local current_time=$(date +%s)
        
        if [ $((current_time - last_disk_check)) -ge $DISK_CHECK_INTERVAL ]; then
            run_script_with_timeout "disk_check" "$SCRIPT_DIR/disk_check.sh" 600
            last_disk_check=$current_time
        fi
        
        if [ $((current_time - last_git_check)) -ge $GIT_CHECK_INTERVAL ]; then
            run_script_with_timeout "git_check" "$SCRIPT_DIR/git_check.sh" 300
            last_git_check=$current_time
        fi
        
        if [ $((current_time - last_break_reminder)) -ge $BREAK_REMINDER_INTERVAL ]; then
            run_script_with_timeout "break_reminder" "$SCRIPT_DIR/break_reminder.sh" 60
            last_break_reminder=$current_time
        fi
        
        if [ $((current_time - last_network_check)) -ge $NETWORK_CHECK_INTERVAL ]; then
            run_script_with_timeout "network_check" "$SCRIPT_DIR/network_check.sh" 180
            last_network_check=$current_time
        fi
        
        if [ $((current_time - last_disk_check)) -ge 259200 ]; then
            cleanup_old_logs
        fi
        
        sleep 60  
    done
}

cleanup() {
    log_message "Остановка системного демона" "STOP"
    rm -f "$PID_FILE"
    exit 0
}

trap cleanup SIGTERM SIGINT

case "${1:-}" in
    start)
        check_running
        echo $$ > "$PID_FILE"
        load_config
        main_loop
        ;;
    stop)
        if [ -f "$PID_FILE" ]; then
            local pid=$(cat "$PID_FILE")
            kill "$pid"
            rm -f "$PID_FILE"
            echo "Демон остановлен"
        else
            echo "Демон не запущен"
        fi
        ;;
    status)
        if [ -f "$PID_FILE" ]; then
            local pid=$(cat "$PID_FILE")
            if kill -0 "$pid" 2>/dev/null; then
                echo "Демон запущен (PID: $pid)"
            else
                echo "Демон не работает (устаревший PID файл)"
                rm -f "$PID_FILE"
            fi
        else
            echo "Демон не запущен"
        fi
        ;;
    *)
        echo "Использование: $0 {start|stop|status}"
        exit 1
        ;;
esac