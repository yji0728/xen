#!/bin/bash
# system_monitor.sh - 시스템 패키지 상태 모니터링

# 설정 파일
CONFIG_FILE="/etc/default/system-monitor"
LOG_FILE="/var/log/system-monitor.log"
ALERT_THRESHOLD=10  # 업그레이드 가능한 패키지 임계값

# 로그 함수
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | sudo tee -a "$LOG_FILE" >/dev/null
}

# 이메일 알림 함수 (optional)
send_alert() {
    local subject="$1"
    local message="$2"
    
    # 시스템에 mail 명령이 있는 경우에만 실행
    if command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "$subject" root@localhost
    fi
    
    log_message "ALERT: $subject"
}

# 메인 검사 함수
perform_checks() {
    log_message "Starting system package monitoring"
    
    # 1. 손상된 패키지 검사
    broken_count=$(dpkg -l | grep "^.H" | wc -l)
    if [ $broken_count -gt 0 ]; then
        send_alert "Broken packages detected" "Found $broken_count broken packages. Run 'sudo apt -f install' to fix."
    fi
    
    # 2. 업그레이드 가능한 패키지 수 검사
    upgradable_count=$(apt list --upgradable 2>/dev/null | grep -v "^Listing" | wc -l)
    if [ $upgradable_count -gt $ALERT_THRESHOLD ]; then
        send_alert "Many packages need upgrade" "Found $upgradable_count packages that can be upgraded."
    fi
    
    # 3. 보안 업데이트 검사
    security_updates=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l)
    if [ $security_updates -gt 0 ]; then
        send_alert "Security updates available" "Found $security_updates security updates. Please update soon."
    fi
    
    # 4. 디스크 공간 검사 (/var/cache/apt/)
    cache_usage=$(du -sm /var/cache/apt/ 2>/dev/null | cut -f1)
    if [ -n "$cache_usage" ] && [ $cache_usage -gt 1000 ]; then  # 1GB 이상
        log_message "WARNING: APT cache using ${cache_usage}MB. Consider running 'sudo apt clean'"
    fi
    
    log_message "System monitoring completed. Broken: $broken_count, Upgradable: $upgradable_count, Security: $security_updates"
}

# cron에서 실행되는 경우를 위한 PATH 설정
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 메인 실행
perform_checks