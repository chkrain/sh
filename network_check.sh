#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
CONFIG_FILE="$SCRIPT_DIR/config/network_check.conf"

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
HOSTS=("8.8.8.8" "google.com" "github.com")
TIMEOUT=2
FAILURE_THRESHOLD=3
EOF
    fi
    
    source "$CONFIG_FILE"
}

log_network_message() {
    local message="$1"
    local level="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/network_check.log"
    echo -e "$level: $message"
}

check_host() {
    local host="$1"
    local timestamp=$(date +%s)
    
    if ping -c 1 -W "$TIMEOUT" "$host" &>/dev/null; then
        local response_time=$(ping -c 1 -W "$TIMEOUT" "$host" | grep "time=" | cut -d'=' -f4 | cut -d' ' -f1 || echo "0")
        log_network_message "✅ $host - доступен (${response_time}ms)" "INFO"
        return 0
    else
        log_network_message "❌ $host - НЕДОСТУПЕН" "ERROR"
        return 1
    fi
}

check_internet_speed() {
    if command -v speedtest-cli &>/dev/null; then
        log_network_message "Проверка скорости интернета..." "INFO"
        speedtest-cli --simple >> "$LOG_DIR/network_check.log" 2>&1 || true
    fi
}

main() {
    load_config
    log_network_message "=== Проверка сети ===" "INFO"
    
    local failed_hosts=0
    local total_hosts=0
    
    for host in "${HOSTS[@]}"; do
        ((total_hosts++))
        if ! check_host "$host"; then
            ((failed_hosts++))
        fi
        sleep 1
    done
    
    if [ $failed_hosts -ge $FAILURE_THRESHOLD ]; then
        log_network_message "🚨 КРИТИЧЕСКИЙ УРОВЕНЬ! $failed_hosts/$total_hosts хостов недоступны" "CRITICAL"
        send_notification "Проблемы с сетью" "Недоступно $failed_hosts из $total_hosts хостов" "critical"
        return 1
    elif [ $failed_hosts -gt 0 ]; then
        log_network_message "⚠️  Предупреждение: $failed_hosts/$total_hosts хостов недоступны" "WARNING"
        send_notification "Проблемы с сетью" "Недоступно $failed_hosts из $total_hosts хостов" "normal"
        return 1
    else
        log_network_message "✅ Все хосты доступны" "SUCCESS"
        if [ $(date +%H) -eq 12 ] && [ $(date +%M) -lt 10 ]; then
            check_internet_speed
        fi
        return 0
    fi
}

send_notification() {
    local title="$1"
    local message="$2"
    local urgency="$3"
    
    if command -v notify-send &>/dev/null; then
        notify-send -u "$urgency" "$title" "$message"
    fi
}

main "$@"