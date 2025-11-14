#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
ERROR_LOG="$LOG_DIR/errors.log"
CONFIG_FILE="$SCRIPT_DIR/config/disk_check.conf"

SAFE_PARTITIONS=("/" "/home" "/boot" "/var" "/tmp" "/usr")

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
# Пороги использования диска (процент ИСПОЛЬЗОВАННОГО места)
WARNING_THRESHOLD=70    # Предупреждение при 70% использовано
CRITICAL_THRESHOLD=85   # Критический уровень при 85% использовано
CHECK_PARTITIONS=("/")
ENABLE_CLEANUP=true
EOF
    fi
    
    source "$CONFIG_FILE"
}

is_safe_partition() {
    local partition="$1"
    
    for safe_partition in "${SAFE_PARTITIONS[@]}"; do
        if [[ "$partition" == "$safe_partition" ]]; then
            return 0
        fi
    done
    
    if [[ ! "$partition" =~ ^\/[a-zA-Z0-9_/-]*$ ]]; then
        return 1
    fi
    
    if [[ "$partition" =~ ^\/dev\/ ]]; then
        return 1
    fi
    
    return 0
}

log_disk_message() {
    local message="$1"
    local level="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/disk_check.log"
    echo -e "$level: $message"
}

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $message" >> "$ERROR_LOG"
    echo -e "${RED}❌ ОШИБКА: $message${NC}" >&2
}

safe_execute() {
    local command="$1"
    local description="$2"
    
    if eval "$command" 2>> "$ERROR_LOG"; then
        return 0
    else
        log_error "$description"
        return 1
    fi
}

check_disk_usage() {
    local all_ok=true
    local critical_partitions=()
    local warning_partitions=()
    
    log_disk_message "Проверка разделов: ${CHECK_PARTITIONS[*]}" "INFO"
    
    for partition in "${CHECK_PARTITIONS[@]}"; do
        if ! is_safe_partition "$partition"; then
            log_disk_message "Пропуск непроверенного раздела: $partition" "WARNING"
            continue
        fi
        
        if mountpoint -q "$partition" 2>/dev/null; then
            local usage=$(df "$partition" 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null || echo "0")
            local available=$(df -h "$partition" 2>/dev/null | awk 'NR==2 {print $4}' || echo "unknown")
            local total=$(df -h "$partition" 2>/dev/null | awk 'NR==2 {print $2}' || echo "unknown")
            local free_percent=$((100 - usage))
            
            if [[ "$usage" =~ ^[0-9]+$ ]]; then
                log_disk_message "Раздел $partition: $usage% использовано, ${available} свободно (${free_percent}% свободно) из ${total}" "INFO"
                
                if [ "$usage" -ge "$CRITICAL_THRESHOLD" ]; then
                    log_disk_message "🚨 КРИТИЧЕСКИЙ УРОВЕНЬ! Раздел $partition заполнен на $usage%" "CRITICAL"
                    critical_partitions+=("$partition:$usage%")
                    all_ok=false
                    
                elif [ "$usage" -ge "$WARNING_THRESHOLD" ]; then
                    log_disk_message "⚠️  Предупреждение! Раздел $partition заполнен на $usage%" "WARNING"
                    warning_partitions+=("$partition:$usage%")
                    all_ok=false
                else
                    log_disk_message "✅ Раздел $partition в норме ($usage% использовано)" "INFO"
                fi
            else
                log_error "Не удалось получить использование диска для раздела: $partition"
            fi
        else
            log_disk_message "Раздел не смонтирован или недоступен: $partition" "INFO"
        fi
    done
    
    if [ ${#critical_partitions[@]} -gt 0 ]; then
        local critical_message="Критически мало свободного места:"
        for partition_info in "${critical_partitions[@]}"; do
            IFS=':' read -r partition usage <<< "$partition_info"
            critical_message="$critical_message\n• $partition - $usage использовано"
        done
        
        send_notification "Критически мало места на диске" "$critical_message" "critical"
        
        if [ "$ENABLE_CLEANUP" = "true" ]; then
            log_disk_message "Запуск автоматической очистки..." "INFO"
            if safe_execute "\"$SCRIPT_DIR/disk_cleanup.sh\"" "Запуск очистки диска"; then
                log_disk_message "Очистка завершена" "INFO"
            else
                log_error "Очистка завершилась с ошибками"
            fi
        fi
    fi
    
    if [ ${#warning_partitions[@]} -gt 0 ]; then
        local warning_message="Мало свободного места:"
        for partition_info in "${warning_partitions[@]}"; do
            IFS=':' read -r partition usage <<< "$partition_info"
            warning_message="$warning_message\n• $partition - $usage использовано"
        done
        
        send_notification "Мало места на диске" "$warning_message" "normal"
    fi
    
    if [ "$all_ok" = true ]; then
        log_disk_message "✅ Места на дисках достаточно (использовано <${WARNING_THRESHOLD}%)" "SUCCESS"
        return 0
    else
        return 1
    fi
}

send_notification() {
    local title="$1"
    local message="$2"
    local urgency="$3"
    
    if command -v notify-send &> /dev/null; then
        notify-send -u "$urgency" "$title" "$message"
    fi
}

main() {
    load_config
    log_disk_message "=== Начало проверки диска ===" "INFO"
    
    if check_disk_usage; then
        log_disk_message "✅ Проверка диска завершена успешно" "SUCCESS"
    else
        log_disk_message "⚠️  Обнаружены проблемы с местом на диске" "WARNING"
    fi
    
    log_disk_message "=== Завершение проверки диска ===" "INFO"
    return 0 
}

handle_error() {
    local line="$1"
    local command="$2"
    local code="$3"
    log_error "Ошибка в строке $line: команда '$command' завершилась с кодом $code"
}

trap 'handle_error ${LINENO} "$BASH_COMMAND" $?' ERR

main "$@"