#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"

log_git_message() {
    local message="$1"
    local level="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/git_check.log"
    echo -e "$level: $message"
}

find_git_repos() {
    local base_dirs=("$HOME/Projects" "$HOME/Development" "$HOME/workspace" "$HOME/git" ".")
    local git_repos=()
    
    for base_dir in "${base_dirs[@]}"; do
        if [ -d "$base_dir" ]; then
            while IFS= read -r -d '' repo; do
                git_repos+=("$repo")
            done < <(find "$base_dir" -type d -name ".git" -printf "%h\0" 2>/dev/null)
        fi
    done
    
    printf "%s\n" "${git_repos[@]}"
}

check_repo_status() {
    local repo_path="$1"
    
    cd "$repo_path"
    
    local repo_name=$(basename "$repo_path")
    local has_changes=false
    local needs_push=false
    local status_summary=""
    
    if [ -n "$(git status --porcelain)" ]; then
        has_changes=true
        local untracked=$(git status --porcelain | grep "^??" | wc -l)
        local modified=$(git status --porcelain | grep -E "^(M| A)" | wc -l)
        status_summary="изменения: ${modified} файлов, неотслеживаемых: ${untracked}"
    fi
    
    if git remote get-url origin &>/dev/null; then
        local current_branch=$(git branch --show-current)
        local ahead=$(git rev-list --count HEAD..origin/$current_branch 2>/dev/null || echo 0)
        local behind=$(git rev-list --count origin/$current_branch..HEAD 2>/dev/null || echo 0)
        
        if [ "$ahead" -gt 0 ] || [ "$behind" -gt 0 ]; then
            needs_push=true
            status_summary="$status_summary, нужно синхронизировать с remote"
        fi
    fi
    
    if [ "$has_changes" = true ] || [ "$needs_push" = true ]; then
        log_git_message "📦 $repo_name: $status_summary" "WARNING"
        send_notification "Git: несохраненные изменения" "Репозиторий $repo_name требует внимания: $status_summary"
        return 1
    else
        log_git_message "✅ $repo_name: актуален" "INFO"
        return 0
    fi
}

send_notification() {
    local title="$1"
    local message="$2"
    
    if command -v notify-send &>/dev/null; then
        notify-send -u normal "$title" "$message"
    fi
}

main() {
    log_git_message "=== Проверка Git репозиториев ===" "INFO"
    
    local repos
    mapfile -t repos < <(find_git_repos)
    local problem_repos=0
    
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
    return $problem_repos
}

main "$@"