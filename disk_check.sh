#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
CONFIG_FILE="$SCRIPT_DIR/config/disk_check.conf"

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
WARNING_THRESHOLD=30
CRITICAL_THRESHOLD=15
CHECK_PARTITIONS=("/" "/home" "/var")
ENABLE_CLEANUP=true
EOF
    fi
    
    source "$CONFIG_FILE"
}

log_disk_message() {
    local message="$1"
    local level="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/disk_check.log"
    echo -e "$level: $message"
}

check_disk_usage() {
    local all_ok=true
    
    for partition in "${CHECK_PARTITIONS[@]}"; do
        if mountpoint -q "$partition"; then
            local usage=$(df "$partition" | awk 'NR==2 {print $5}' | sed 's/%//')
            local available=$(df -h "$partition" | awk 'NR==2 {print $4}')
            local total=$(df -h "$partition" | awk 'NR==2 {print $2}')
            
            log_disk_message "Раздел $partition: $usage% использовано, ${available} свободно из ${total}" "INFO"
            
            if [ "$usage" -ge "$CRITICAL_THRESHOLD" ]; then
                log_disk_message "КРИТИЧЕСКИЙ УРОВЕНЬ! Раздел $partition заполнен на $usage%" "CRITICAL"
                send_notification "Критически мало места" "Раздел $partition заполнен на $usage%! Срочно освободите место." "critical"
                all_ok=false
                
                # Запускаем очистку если включено
                if [ "$ENABLE_CLEANUP" = "true" ]; then
                    log_disk_message "Запуск автоматической очистки..." "INFO"
                    "$SCRIPT_DIR/disk_cleanup.sh"
                fi
                
            elif [ "$usage" -ge "$WARNING_THRESHOLD" ]; then
                log_disk_message "Предупреждение! Раздел $partition заполнен на $usage%" "WARNING"
                send_notification "Мало места на диске" "Раздел $partition заполнен на $usage%. Рекомендуется очистка." "normal"
                all_ok=false
            fi
        fi
    done
    
    if [ "$all_ok" = true ]; then
        log_disk_message "✅ Места на дисках достаточно (>${WARNING_THRESHOLD}% свободно)" "SUCCESS"
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
    check_disk_usage
    local result=$?
    log_disk_message "=== Завершение проверки диска ===" "INFO"
    return $result
}

main "$@"