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
BACKUP_REMOTE="backup-temp-$(hostname)"

SAFE_REPO_DIRS=("$HOME/Projects" "$HOME/Development" "$HOME/workspace" "$HOME/git" "$HOME/src")

log_git_message() {
    local message="$1"
    local level="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/git_check.log"
    echo -e "$level: $message"
}

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $message" >> "$ERROR_LOG"
    echo -e "${RED}❌ ОШИБКА: $message${NC}" >&2
}

is_safe_path() {
    local path="$1"
    
    local forbidden_paths=("/" "/etc" "/var" "/usr" "/sys" "/proc" "/dev" "/boot")
    for forbidden in "${forbidden_paths[@]}"; do
        if [[ "$path" == "$forbidden"* ]]; then
            return 1
        fi
    done
    
    if [[ "$path" == "$SCRIPT_DIR"* ]]; then
        return 1
    fi
    
    if [[ ! "$path" == "$HOME"* ]]; then
        return 1
    fi
    
    return 0
}

find_git_repos() {
    local git_repos=()
    
    for base_dir in "${SAFE_REPO_DIRS[@]}"; do
        if [ -d "$base_dir" ] && is_safe_path "$base_dir"; then
            while IFS= read -r -d '' repo; do
                if is_safe_path "$repo" && [ -d "$repo/.git" ]; then
                    git_repos+=("$repo")
                    log_git_message "Найден репозиторий: $repo" "INFO"
                fi
            done < <(find "$base_dir" -maxdepth 3 -type d -name ".git" -print0 2>/dev/null | xargs -0 dirname 2>/dev/null || true)
        fi
    done
    
    printf "%s\n" "${git_repos[@]}"
}

setup_backup_remote() {
    local repo_path="$1"
    
    if ! cd "$repo_path" 2>/dev/null; then
        return 1
    fi
    
    if git remote get-url "$BACKUP_REMOTE" &>/dev/null; then
        return 0
    fi
    
    local backup_dir="$HOME/.git-backups/$(basename "$repo_path")-$(date +%Y%m%d)"
    mkdir -p "$backup_dir"
    
    if git init --bare "$backup_dir" &>/dev/null; then
        git remote add "$BACKUP_REMOTE" "$backup_dir"
        log_git_message "Создан backup remote: $backup_dir" "INFO"
        return 0
    fi
    
    return 1
}

auto_commit_and_push() {
    local repo_path="$1"
    local repo_name="$2"
    
    if ! cd "$repo_path" 2>/dev/null; then
        return 1
    fi
    
    if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
        log_git_message "Нет изменений для коммита: $repo_name" "INFO"
        return 0
    fi
    
    local commit_message="Auto-backup: $(date '+%Y-%m-%d %H:%M:%S')"
    
    if git add . && \
       git commit -m "$commit_message" --author="System Manager <auto@backup>"; then
        
        log_git_message "Автоматический коммит создан: $repo_name" "SUCCESS"
        
        if git remote get-url origin &>/dev/null; then
            local current_branch=$(git branch --show-current 2>/dev/null || echo "main")
            if git push origin "$current_branch" &>/dev/null; then
                log_git_message "✅ Успешный пуш в origin: $repo_name" "SUCCESS"
                return 0
            else
                log_git_message "Не удалось запушить в origin: $repo_name" "WARNING"
            fi
        fi
        
        if setup_backup_remote "$repo_path"; then
            local current_branch=$(git branch --show-current 2>/dev/null || echo "main")
            if git push "$BACKUP_REMOTE" "$current_branch" &>/dev/null; then
                log_git_message "✅ Успешный пуш в backup: $repo_name" "SUCCESS"
                send_notification "Git Auto-Backup" "Репозиторий $repo_name автоматически закоммичен и запушен в backup"
                return 0
            else
                log_git_message "Не удалось запушить в backup: $repo_name" "WARNING"
            fi
        fi
        
        log_git_message "Не удалось запушить ни в один remote: $repo_name" "WARNING"
        return 1
    else
        log_git_message "Не удалось создать коммит: $repo_name" "WARNING"
        return 1
    fi
}

check_repo_status() {
    local repo_path="$1"
    
    if ! cd "$repo_path" 2>/dev/null; then
        log_error "Не удалось перейти в репозиторий: $repo_path"
        return 0 
    fi
    
    local repo_name=$(basename "$repo_path")
    local has_changes=false
    local needs_push=false
    local status_summary=""
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_git_message "Пропускаем (не git репозиторий): $repo_name" "WARNING"
        return 0
    fi
    
    local status_output
    if status_output=$(git status --porcelain 2>/dev/null); then
        if [ -n "$status_output" ]; then
            has_changes=true
            local untracked=$(echo "$status_output" | grep "^??" | wc -l)
            local modified=$(echo "$status_output" | grep -E "^(M| A)" | wc -l)
            status_summary="изменения: ${modified} файлов, неотслеживаемых: ${untracked}"
        fi
    else
        log_error "Ошибка получения статуса git в: $repo_path"
        return 0
    fi
    
    if git remote get-url origin &>/dev/null; then
        local current_branch=$(git branch --show-current 2>/dev/null || echo "main")
        local ahead=0
        local behind=0
        
        ahead=$(git rev-list --count "HEAD..origin/$current_branch" 2>/dev/null || echo 0)
        behind=$(git rev-list --count "origin/$current_branch..HEAD" 2>/dev/null || echo 0)
        
        if [ "$ahead" -gt 0 ] || [ "$behind" -gt 0 ]; then
            needs_push=true
            status_summary="$status_summary, нужно синхронизировать с remote (ahead: $ahead, behind: $behind)"
        fi
    fi
    
    if [ "$has_changes" = true ] || [ "$needs_push" = true ]; then
        log_git_message "📦 $repo_name: $status_summary" "WARNING"
        send_notification "Git: несохраненные изменения" "Репозиторий $repo_name требует внимания: $status_summary"
        
        # АВТОМАТИЧЕСКИЙ КОММИТ И ПУШ
        log_git_message "Пытаемся автоматически сохранить изменения: $repo_name" "INFO"
        if auto_commit_and_push "$repo_path" "$repo_name"; then
            log_git_message "✅ Авто-сохранение успешно: $repo_name" "SUCCESS"
            return 0
        else
            log_git_message "❌ Авто-сохранение не удалось: $repo_name" "WARNING"
            return 1
        fi
    else
        log_git_message "✅ $repo_name: актуален" "INFO"
        return 0 
    fi
}

send_notification() {
    local title="$1"
    local message="$2"
    
    if command -v notify-send &>/dev/null; then
        notify-send "$title" "$message" --icon=dialog-information 2>/dev/null || true
    fi
}

cleanup_old_backups() {
    local backup_dir="$HOME/.git-backups"
    if [ -d "$backup_dir" ]; then
        find "$backup_dir" -type d -name "*-*" -mtime +30 -exec rm -rf {} + 2>/dev/null || true
    fi
}

main() {
    log_git_message "=== Проверка Git репозиториев ===" "INFO"
    
    cleanup_old_backups
    
    local repos
    mapfile -t repos < <(find_git_repos)
    local problem_repos=0
    
    log_git_message "Найдено репозиториев: ${#repos[@]}" "INFO"
    
    for repo in "${repos[@]}"; do
        if ! check_repo_status "$repo"; then
            ((problem_repos++))
        fi
    done
    
    if [ $problem_repos -eq 0 ]; then
        log_git_message "✅ Все Git репозитории актуальны" "SUCCESS"
    else
        log_git_message "⚠️  Найдено $problem_repos репозиториев требующих внимания" "WARNING"
    fi
    
    log_git_message "=== Завершение проверки Git ===" "INFO"
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