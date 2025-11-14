#!/bin/bash

echo "=== Принудительная очистка System Manager ==="

echo "Останавливаем процессы system_manager..."
pkill -f "system_manager.sh" 2>/dev/null || true
pkill -f "disk_check.sh" 2>/dev/null || true
pkill -f "git_check.sh" 2>/dev/null || true
pkill -f "network_check.sh" 2>/dev/null || true
pkill -f "break_reminder.sh" 2>/dev/null || true

echo "Удаляем PID файл..."
rm -f system_manager.pid

sleep 2

echo "Проверяем оставшиеся процессы..."
ps aux | grep -E "(system_manager|disk_check|git_check|network_check|break_reminder)" | grep -v grep

echo "=== Очистка завершена ==="
echo "Теперь можно запустить: ./system_manager.sh start"