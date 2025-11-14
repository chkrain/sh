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

SAFE_PROJECT_DIRS=("$HOME/Projects" "$HOME/Development" "$HOME/workspace" "$HOME/git" "$HOME/src")

is_safe_path() {
    local path="$1"
    
    local forbidden_paths=("/" "/etc" "/var" "/usr" "/sys" "/proc" "/dev" "/boot")
    for forbidden in "${forbidden_paths[@]}"; do
        if [[ "$path" == "$forbidden"* ]]; then
            return 1
        fi
    done
    
    if [[ ! "$path" == "$HOME"* ]]; then
        return 1
    fi
    
    return 0
}

log_cleanup_message() {
    local message="$1"
    local level="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/disk_cleanup.log"
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
        log_cleanup_message "$description - успешно" "INFO"
        return 0
    else
        log_error "$description - ошибка выполнения"
        return 1
    fi
}

find_old_projects() {
    local old_projects=()
    
    for base_dir in "${SAFE_PROJECT_DIRS[@]}"; do
        if [ -d "$base_dir" ] && is_safe_path "$base_dir"; then
            while IFS= read -r -d '' project; do
                if is_safe_path "$project" && [ -d "$project/.git" ]; then
                    local last_commit=$(git -C "$project" log -1 --format=%ct 2>/dev/null || echo 0)
                    local last_modify=$(find "$project" -type f \( -name "*.py" -o -name "*.js" -o -name "*.java" -o -name "*.cpp" -o -name "*.c" -o -name "*.h" -o -name "*.md" -o -name "*.txt" \) \
                                     -exec stat -c %Y {} \; 2>/dev/null | sort -nr | head -1 || echo 0)
                    local recent_activity=$((last_commit > last_modify ? last_commit : last_modify))
                    local days_old=0
                    
                    if [ $recent_activity -gt 0 ]; then
                        days_old=$(( ( $(date +%s) - recent_activity ) / 86400 ))
                    fi
                    
                    if [ $days_old -gt 90 ]; then
                        old_projects+=("$project:$days_old")
                        log_cleanup_message "Найден старый проект: $(basename "$project") ($days_old дней)" "INFO"
                    fi
                fi
            done < <(find "$base_dir" -maxdepth 2 -type d -name ".git" -printf "%h\0" 2>/dev/null || true)
        fi
    done
    
    printf "%s\n" "${old_projects[@]}"
}

backup_project_to_git() {
    local project_path="$1"
    local days_old="$2"
    
    log_cleanup_message "Резервное копирование проекта: $(basename "$project_path") (не использовался $days_old дней)" "INFO"
    
    if ! cd "$project_path" 2>/dev/null; then
        log_error "Не удалось перейти в директорию: $project_path"
        return 1
    fi

    if ! git status &>/dev/null; then
        log_cleanup_message "Пропускаем (не git репозиторий): $project_path" "WARNING"
        return 1
    fi
    
    local changes_exist=false
    if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git status --porcelain)" ]; then
        changes_exist=true
    fi
    
    if [ "$changes_exist" = false ]; then
        log_cleanup_message "Нет изменений для коммита: $project_path" "INFO"
        return 0
    fi
    
    local commit_message="Auto-backup: проект не использовался $days_old дней. Дата: $(date '+%Y-%m-%d %H:%M:%S')"
    
    if safe_execute "git add ." "Добавление файлов в git" && \
       safe_execute "git commit -m \"$commit_message\"" "Создание коммита"; then
        
        if git remote get-url origin &>/dev/null; then
            local current_branch=$(git branch --show-current 2>/dev/null || echo "main")
            if safe_execute "git push origin $current_branch" "Отправка в remote"; then
                log_cleanup_message "✅ Проект закоммичен и запушен: $project_path" "SUCCESS"
            else
                log_cleanup_message "✅ Проект закоммичен, но не удалось запушить: $project_path" "WARNING"
            fi
        else
            log_cleanup_message "✅ Проект закоммичен (нет remote): $project_path" "INFO"
        fi
        return 0
    else
        log_error "Не удалось закоммитить изменения в: $project_path"
        return 1
    fi
}

clean_system_temp() {
    log_cleanup_message "Очистка временных файлов..." "INFO"
    
    local freed_space=0
    
    local user_temp_dirs=("$HOME/.cache" "$HOME/tmp" "$HOME/.local/share/Trash")
    
    for temp_dir in "${user_temp_dirs[@]}"; do
        if [ -d "$temp_dir" ] && is_safe_path "$temp_dir"; then
            log_cleanup_message "Очистка: $temp_dir" "INFO"
            
            # Только файлы старше 30 дней
            find "$temp_dir" -type f -atime +30 -delete 2>/dev/null || true
            find "$temp_dir" -type d -empty -delete 2>/dev/null || true
        fi
    done
    
    if [ -d "/tmp" ]; then
        find "/tmp" -user "$USER" -type f -atime +7 -delete 2>/dev/null || true
    fi
    
    log_cleanup_message "Очистка временных файлов завершена" "SUCCESS"
}

suggest_cleanup() {
    local old_projects=("$@")
    
    if [ ${#old_projects[@]} -gt 0 ]; then
        log_cleanup_message "🔍 Обнаружены старые проекты. Рекомендуется проверить:" "INFO"
        
        for project_info in "${old_projects[@]}"; do
            IFS=':' read -r project_path days_old <<< "$project_info"
            if [ -n "$project_path" ] && [ -d "$project_path" ]; then
                local size=$(du -sh "$project_path" 2>/dev/null | cut -f1 || echo "unknown")
                log_cleanup_message "  📁 $project_path" "INFO"
                log_cleanup_message "     ⏰ Не использовался: $days_old дней" "INFO"  
                log_cleanup_message "     📊 Размер: $size" "INFO"
                log_cleanup_message "     🗑️  Для удаления выполните: rm -rf \"$project_path\"" "WARNING"
            fi
        done
        
        log_cleanup_message "💡 Все проекты были заархивированы в Git. Вы можете безопасно удалить ненужные." "INFO"
    fi
}

main() {
    log_cleanup_message "=== Начало очистки диска ===" "INFO"
    
    log_cleanup_message "Поиск старых проектов для резервного копирования..." "INFO"
    local old_projects
    mapfile -t old_projects < <(find_old_projects)
    
    local backed_up_count=0
    for project_info in "${old_projects[@]}"; do
        IFS=':' read -r project_path days_old <<< "$project_info"
        if [ -n "$project_path" ] && [ -n "$days_old" ]; then
            if backup_project_to_git "$project_path" "$days_old"; then
                ((backed_up_count++))
            fi
        fi
    done
    
    log_cleanup_message "Заархивировано проектов: $backed_up_count/${#old_projects[@]}" "INFO"
    
    clean_system_temp
    
    suggest_cleanup "${old_projects[@]}"
    
    log_cleanup_message "=== Завершение очистки диска ===" "INFO"
}

handle_error() {
    local line="$1"
    local command="$2"
    local code="$3"
    log_error "Ошибка в строке $line: команда '$command' завершилась с кодом $code"
}

trap 'handle_error ${LINENO} "$BASH_COMMAND" $?' ERR

main "$@"