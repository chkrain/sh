#!/bin/bash

# set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
CONFIG_DIR="$SCRIPT_DIR/config"
PID_FILE="$SCRIPT_DIR/system_manager.pid"
ERROR_LOG="$LOG_DIR/errors.log"

mkdir -p "$LOG_DIR" "$CONFIG_DIR"

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $message" >> "$ERROR_LOG"
    echo -e "${RED}❌ ОШИБКА: $message${NC}" >&2
}

load_config() {
    local config_file="$CONFIG_DIR/system_manager.conf"
    
    if [ ! -f "$config_file" ]; then
        cat > "$config_file" << EOF
# Интервалы проверок (в секундах)
DISK_CHECK_INTERVAL=60        # 1 минута для тестирования
GIT_CHECK_INTERVAL=120        # 2 минуты для тестирования  
BREAK_REMINDER_INTERVAL=180   # 3 минуты для тестирования
NETWORK_CHECK_INTERVAL=300    # 5 минут

# Настройки уведомлений
ENABLE_DESKTOP_NOTIFICATIONS=true
ENABLE_LOGGING=true
LOG_RETENTION_DAYS=7

# Пороги
DISK_WARNING_THRESHOLD=70
DISK_CRITICAL_THRESHOLD=85
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
    
    if [ "$level" = "ERROR" ]; then
        echo -e "${RED}[$timestamp] $level: $message${NC}"
    elif [ "$level" = "WARNING" ]; then
        echo -e "${YELLOW}[$timestamp] $level: $message${NC}"
    elif [ "$level" = "SUCCESS" ]; then
        echo -e "${GREEN}[$timestamp] $level: $message${NC}"
    else
        echo -e "${BLUE}[$timestamp] $level: $message${NC}"
    fi
}

send_notification() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"
    
    if [ "$ENABLE_DESKTOP_NOTIFICATIONS" = "true" ] && command -v notify-send &> /dev/null; then
        notify-send -u "$urgency" "$title" "$message" 2>/dev/null || true
    fi
}

check_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "Демон уже запущен (PID: $pid)"
            return 1
        else
            log_message "Удаляем устаревший PID файл" "INFO"
            rm -f "$PID_FILE"
        fi
    fi
    return 0
}

run_script_with_timeout() {
    local script_name="$1"
    local script_path="$2"
    local timeout="${3:-300}"  
    
    if [ ! -f "$script_path" ]; then
        log_message "Скрипт $script_name не найден: $script_path" "WARNING"
        return 0
    fi
    
    if [ ! -x "$script_path" ]; then
        log_message "Скрипт $script_name не исполняемый, добавляем права..." "WARNING"
        chmod +x "$script_path"
    fi
    
    log_message "Запуск $script_name..." "INFO"
    
    if timeout "$timeout" bash "$script_path" 2>> "$ERROR_LOG"; then
        log_message "$script_name завершен успешно" "SUCCESS"
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_message "$script_name превысил время выполнения ($timeout сек)" "WARNING"
        else
            log_message "$script_name завершился с кодом: $exit_code" "WARNING"
        fi
        return 0 
    fi
}

cleanup_old_logs() {
    find "$LOG_DIR" -name "*.log" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
}

main_loop() {
    log_message "Запуск системного демона (PID: $$)" "START"
    log_message "Интервалы: диск=$DISK_CHECK_INTERVAL, git=$GIT_CHECK_INTERVAL, перерывы=$BREAK_REMINDER_INTERVAL, сеть=$NETWORK_CHECK_INTERVAL" "INFO"
    
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
            run_script_with_timeout "break_reminder" "$SCRIPT_DIR/interactive_break.sh" 60
            last_break_reminder=$current_time
        fi
        
        if [ $((current_time - last_network_check)) -ge $NETWORK_CHECK_INTERVAL ]; then
            run_script_with_timeout "network_check" "$SCRIPT_DIR/network_check.sh" 180
            last_network_check=$current_time
        fi
        
        if [ $((current_time - last_disk_check)) -ge 86400 ]; then
            cleanup_old_logs
        fi
        
        sleep 30 
    done
}

cleanup() {
    log_message "Остановка системного демона" "STOP"
    [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

handle_error() {
    local line="$1"
    local command="$2"
    local code="$3"
    log_error "Ошибка в строке $line: команда '$command' завершилась с кодом $code"
}

trap 'handle_error ${LINENO} "$BASH_COMMAND" $?' ERR

start_daemon() {
    log_message "Попытка запуска демона..." "INFO"
    if ! check_running; then
        exit 1
    fi
    echo $$ > "$PID_FILE"
    load_config
    log_message "Демон успешно запущен (PID: $$)" "SUCCESS"
    main_loop
}

stop_daemon() {
    log_message "Попытка остановки демона..." "INFO"
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null && echo "Демон остановлен" || echo "Не удалось остановить демон"
        else
            echo "Демон не запущен (неверный PID)"
        fi
        rm -f "$PID_FILE"
    else
        echo "Демон не запущен (нет PID файла)"
    fi
}

status_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "✅ Демон запущен (PID: $pid)"
            echo "📊 Логи ошибок: $ERROR_LOG"
            ps -p "$pid" -o pid,state,time,cmd
        else
            echo "❌ Демон не работает (устаревший PID файл)"
            rm -f "$PID_FILE"
        fi
    else
        echo "❌ Демон не запущен"
    fi
}

show_errors() {
    if [ -f "$ERROR_LOG" ] && [ -s "$ERROR_LOG" ]; then
        echo "Последние ошибки:"
        tail -20 "$ERROR_LOG"
    else
        echo "Ошибок нет или файл не существует"
    fi
}

case "${1:-}" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    status)
        status_daemon
        ;;
    errors)
        show_errors
        ;;
    restart)
        stop_daemon
        sleep 2
        start_daemon
        ;;
    *)
        echo "Использование: $0 {start|stop|restart|status|errors}"
        echo "  start   - запустить демон"
        echo "  stop    - остановить демон" 
        echo "  restart - перезапустить демон"
        echo "  status  - статус демона"
        echo "  errors  - показать ошибки"
        echo "  ./force_cleanup.sh - убить если подвисло"
        exit 1
        ;;
esac