#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"

log_cleanup_message() {
    local message="$1"
    local level="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/disk_cleanup.log"
    echo -e "$level: $message"
}

find_old_projects() {
    local base_dirs=("$HOME/Projects" "$HOME/Development" "$HOME/workspace" "$HOME/git")
    local old_projects=()
    
    for base_dir in "${base_dirs[@]}"; do
        if [ -d "$base_dir" ]; then
            while IFS= read -r -d '' project; do
                if [ -d "$project/.git" ]; then
                    local last_commit=$(git -C "$project" log -1 --format=%ct 2>/dev/null || echo 0)
                    local last_modify=$(find "$project" -type f -name "*.py" -o -name "*.js" -o -name "*.java" -o -name "*.cpp" 2>/dev/null | \
                                      xargs stat -c %Y 2>/dev/null | sort -nr | head -1 || echo 0)
                    local recent_activity=$((last_commit > last_modify ? last_commit : last_modify))
                    local days_old=$(( ( $(date +%s) - recent_activity ) / 86400 ))
                    
                    if [ $days_old -gt 90 ] && [ $recent_activity -gt 0 ]; then
                        old_projects+=("$project:$days_old")
                    fi
                fi
            done < <(find "$base_dir" -maxdepth 2 -type d -name ".git" -printf "%h\0" 2>/dev/null)
        fi
    done
    
    printf "%s\n" "${old_projects[@]}"
}

backup_project_to_git() {
    local project_path="$1"
    local days_old="$2"
    
    log_cleanup_message "Резервное копирование проекта: $(basename "$project_path") (не использовался $days_old дней)" "INFO"
    
    cd "$project_path"

    if ! git status &>/dev/null; then
        log_cleanup_message "Пропускаем (не git репозиторий): $project_path" "WARNING"
        return 1
    fi
    
    if git diff --quiet && git diff --cached --quiet; then
        log_cleanup_message "Нет изменений для коммита: $project_path" "INFO"
        return 0
    fi
    
    local commit_message="Auto-backup: проект не использовался $days_old дней. $(date '+%Y-%m-%d %H:%M:%S')"
    
    if git add . && git commit -m "$commit_message"; then
        if git remote get-url origin &>/dev/null; then
            if git push origin main 2>/dev/null || git push origin master 2>/dev/null; then
                log_cleanup_message "✅ Проект закоммичен и запушен: $project_path" "SUCCESS"
                return 0
            else
                log_cleanup_message "✅ Проект закоммичен, но не удалось запушить: $project_path" "WARNING"
                return 0
            fi
        else
            log_cleanup_message "✅ Проект закоммичен (нет remote): $project_path" "INFO"
            return 0
        fi
    else
        log_cleanup_message "❌ Не удалось закоммитить: $project_path" "ERROR"
        return 1
    fi
}

clean_system_temp() {
    log_cleanup_message "Очистка временных файлов..." "INFO"
    
    local freed_space=0
    
    if command -v apt-get &>/dev/null; then
        local apt_cache_size=$(du -s /var/cache/apt/archives 2>/dev/null | cut -f1 || echo 0)
        apt-get clean
        freed_space=$((freed_space + apt_cache_size))
    fi
    
    find /tmp -type f -atime +7 -delete 2>/dev/null
    find /var/tmp -type f -atime +7 -delete 2>/dev/null
    
    find /var/log -name "*.log" -type f -mtime +30 -delete 2>/dev/null
    
    for browser in "$HOME"/.cache/*; do
        if [ -d "$browser" ]; then
            local cache_size=$(du -s "$browser" 2>/dev/null | cut -f1 || echo 0)
            rm -rf "$browser"/*
            freed_space=$((freed_space + cache_size))
        fi
    done
    
    log_cleanup_message "Очищено временных файлов: ~$((freed_space / 1024)) MB" "SUCCESS"
}

main() {
    log_cleanup_message "=== Начало очистки диска ===" "INFO"
    
    log_cleanup_message "Поиск старых проектов для резервного копирования..." "INFO"
    local old_projects
    mapfile -t old_projects < <(find_old_projects)
    
    for project_info in "${old_projects[@]}"; do
        IFS=':' read -r project_path days_old <<< "$project_info"
        backup_project_to_git "$project_path" "$days_old"
    done
    
    clean_system_temp
    
    if [ ${#old_projects[@]} -gt 0 ]; then
        log_cleanup_message "Старые проекты были заархивированы. Рассмотрите возможность их удаления:" "INFO"
        for project_info in "${old_projects[@]}"; do
            IFS=':' read -r project_path days_old <<< "$project_info"
            echo "  - $project_path (не использовался $days_old дней)"
        done
    fi
    
    log_cleanup_message "=== Завершение очистки диска ===" "INFO"
}

main "$@"