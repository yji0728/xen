#!/bin/bash

#####################################################################
# 게스트 도메인 부팅 로깅 시스템 v1.0
# Xen 게스트 도메인의 완전한 부팅 과정 기록
#####################################################################

set -euo pipefail

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 설정 변수
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUEST_LOG_DIR="/var/log/xen-guest-logging"
GUEST_CONFIG_DIR="/etc/xen-guest-logging"
TEMP_DIR="/tmp/xen-guest-logging"

# 로깅 함수
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${CYAN}[DEBUG]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# 타임스탬프 함수
get_timestamp() {
    date '+%Y%m%d-%H%M%S'
}

get_timestamp_ms() {
    date '+%Y-%m-%d %H:%M:%S.%3N'
}

# 초기화
init_guest_logging() {
    log_section "게스트 도메인 로깅 시스템 초기화"
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        exit 1
    fi
    
    # Xen 설치 확인
    if ! command -v xl >/dev/null; then
        log_error "Xen이 설치되어 있지 않습니다."
        exit 1
    fi
    
    # 디렉토리 구조 생성
    mkdir -p "$GUEST_LOG_DIR"/{domains,console-logs,performance,events,analysis}
    mkdir -p "$GUEST_CONFIG_DIR"
    mkdir -p "$TEMP_DIR"
    
    log_info "게스트 도메인 로깅 시스템 초기화 완료"
}

# 도메인 목록 스캐닝
scan_domains() {
    log_section "도메인 목록 스캐닝"
    
    local domains_file="$GUEST_LOG_DIR/domains/domain-list-$(get_timestamp).txt"
    
    # 현재 실행 중인 도메인 목록
    echo "=== Running Domains ===" > "$domains_file"
    xl list >> "$domains_file" 2>/dev/null || {
        echo "Failed to get domain list" >> "$domains_file"
        log_error "도메인 목록을 가져올 수 없습니다. Xen이 실행 중인지 확인하세요."
        return 1
    }
    
    # 도메인 설정 파일 스캔
    echo -e "\n=== Domain Configuration Files ===" >> "$domains_file"
    if [[ -d /etc/xen ]]; then
        find /etc/xen -name "*.cfg" -o -name "*.conf" | while read -r config_file; do
            echo "Config: $config_file" >> "$domains_file"
        done
    fi
    
    # 자동 시작 도메인
    echo -e "\n=== Auto-start Domains ===" >> "$domains_file"
    if [[ -d /etc/xen/auto ]]; then
        ls -la /etc/xen/auto/ >> "$domains_file" 2>/dev/null || echo "No auto-start domains" >> "$domains_file"
    fi
    
    log_info "도메인 목록 스캔 완료: $domains_file"
}

# 도메인별 콘솔 로깅 설정
setup_domain_console_logging() {
    local domain_name="$1"
    local domain_id="$2"
    
    log_debug "도메인 콘솔 로깅 설정: $domain_name (ID: $domain_id)"
    
    local console_log_dir="$GUEST_LOG_DIR/console-logs/$domain_name"
    mkdir -p "$console_log_dir"
    
    local log_file="$console_log_dir/console-$(get_timestamp).log"
    
    # 콘솔 로깅 스크립트 생성
    cat > "$GUEST_CONFIG_DIR/console-logger-$domain_name.sh" << EOF
#!/bin/bash

# 도메인 $domain_name 콘솔 로거
DOMAIN_NAME="$domain_name"
DOMAIN_ID="$domain_id"
LOG_FILE="$log_file"

# 로그 시작 마커
echo "=== Console logging started for \$DOMAIN_NAME (ID: \$DOMAIN_ID) at \$(date) ===" >> "\$LOG_FILE"

# 도메인이 실행 중인지 확인
check_domain_running() {
    xl list "\$DOMAIN_NAME" >/dev/null 2>&1
}

# 콘솔 로깅 루프
while true; do
    if check_domain_running; then
        # xl console을 통해 콘솔 출력 캡처 (백그라운드)
        timeout 60 xl console "\$DOMAIN_NAME" >> "\$LOG_FILE" 2>/dev/null || true
        
        # 도메인 상태 정보 주기적 기록
        {
            echo "--- Domain Status at \$(date) ---"
            xl list "\$DOMAIN_NAME" 2>/dev/null || echo "Domain not found"
            xl vcpu-list "\$DOMAIN_NAME" 2>/dev/null || echo "vCPU info not available"
            echo
        } >> "\$LOG_FILE"
    else
        echo "Domain \$DOMAIN_NAME is not running. Waiting..." >> "\$LOG_FILE"
        sleep 10
    fi
    
    sleep 5
done
EOF
    
    chmod +x "$GUEST_CONFIG_DIR/console-logger-$domain_name.sh"
}

# 도메인 성능 모니터링 설정
setup_domain_performance_monitoring() {
    local domain_name="$1"
    
    log_debug "도메인 성능 모니터링 설정: $domain_name"
    
    local perf_log_dir="$GUEST_LOG_DIR/performance/$domain_name"
    mkdir -p "$perf_log_dir"
    
    # 성능 모니터링 스크립트 생성
    cat > "$GUEST_CONFIG_DIR/performance-monitor-$domain_name.sh" << EOF
#!/bin/bash

# 도메인 $domain_name 성능 모니터
DOMAIN_NAME="$domain_name"
PERF_LOG_DIR="$perf_log_dir"

# 성능 데이터 수집 함수
collect_performance_data() {
    local timestamp=\$(date '+%Y-%m-%d %H:%M:%S')
    local perf_file="\$PERF_LOG_DIR/performance-\$(date '+%Y%m%d').log"
    
    {
        echo "[\$timestamp] === Performance Data for \$DOMAIN_NAME ==="
        
        # 기본 도메인 정보
        echo "Domain Information:"
        xl list "\$DOMAIN_NAME" 2>/dev/null || echo "Domain not running"
        
        # vCPU 사용률
        echo "vCPU Information:"
        xl vcpu-list "\$DOMAIN_NAME" 2>/dev/null || echo "vCPU info not available"
        
        # 메모리 사용량
        echo "Memory Usage:"
        xl mem-set "\$DOMAIN_NAME" \$(xl list "\$DOMAIN_NAME" | tail -n1 | awk '{print \$3}') 2>/dev/null || echo "Memory info not available"
        
        # 네트워크 통계
        echo "Network Statistics:"
        xl network-list "\$DOMAIN_NAME" 2>/dev/null | while read -r line; do
            if [[ \$line == *"vif"* ]]; then
                vif_name=\$(echo "\$line" | awk '{print \$1}')
                if [[ -d "/sys/class/net/\$vif_name" ]]; then
                    echo "Interface \$vif_name:"
                    echo "  RX bytes: \$(cat /sys/class/net/\$vif_name/statistics/rx_bytes 2>/dev/null || echo 'N/A')"
                    echo "  TX bytes: \$(cat /sys/class/net/\$vif_name/statistics/tx_bytes 2>/dev/null || echo 'N/A')"
                    echo "  RX packets: \$(cat /sys/class/net/\$vif_name/statistics/rx_packets 2>/dev/null || echo 'N/A')"
                    echo "  TX packets: \$(cat /sys/class/net/\$vif_name/statistics/tx_packets 2>/dev/null || echo 'N/A')"
                fi
            fi
        done
        
        # 블록 디바이스 통계
        echo "Block Device Statistics:"
        xl block-list "\$DOMAIN_NAME" 2>/dev/null || echo "Block device info not available"
        
        echo "=== End Performance Data ===\\n"
        
    } >> "\$perf_file"
}

# 메인 모니터링 루프
while true; do
    if xl list "\$DOMAIN_NAME" >/dev/null 2>&1; then
        collect_performance_data
    else
        echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Domain \$DOMAIN_NAME not running" >> "\$PERF_LOG_DIR/performance-\$(date '+%Y%m%d').log"
    fi
    
    sleep 30  # 30초마다 수집
done
EOF
    
    chmod +x "$GUEST_CONFIG_DIR/performance-monitor-$domain_name.sh"
}

# 도메인 이벤트 로깅 설정
setup_domain_event_logging() {
    local domain_name="$1"
    
    log_debug "도메인 이벤트 로깅 설정: $domain_name"
    
    local event_log_dir="$GUEST_LOG_DIR/events/$domain_name"
    mkdir -p "$event_log_dir"
    
    # 이벤트 로깅 스크립트 생성
    cat > "$GUEST_CONFIG_DIR/event-logger-$domain_name.sh" << EOF
#!/bin/bash

# 도메인 $domain_name 이벤트 로거
DOMAIN_NAME="$domain_name"
EVENT_LOG_DIR="$event_log_dir"
EVENT_LOG="\$EVENT_LOG_DIR/events-\$(date '+%Y%m%d').log"

# XenStore 이벤트 모니터링
monitor_xenstore_events() {
    if command -v xenstore-watch >/dev/null; then
        xenstore-watch "/local/domain" 2>/dev/null | while read -r event; do
            echo "[\$(date '+%Y-%m-%d %H:%M:%S')] XenStore Event: \$event" >> "\$EVENT_LOG"
        done &
    fi
}

# 도메인 상태 변화 모니터링
monitor_domain_state() {
    local last_state=""
    
    while true; do
        if xl list "\$DOMAIN_NAME" >/dev/null 2>&1; then
            local current_state=\$(xl list "\$DOMAIN_NAME" | tail -n1 | awk '{print \$5}')
            
            if [[ "\$current_state" != "\$last_state" ]]; then
                echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Domain State Change: \$last_state -> \$current_state" >> "\$EVENT_LOG"
                last_state="\$current_state"
                
                # 상태별 추가 정보 수집
                case "\$current_state" in
                    "r-----")
                        echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Domain \$DOMAIN_NAME is running" >> "\$EVENT_LOG"
                        ;;
                    "------")
                        echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Domain \$DOMAIN_NAME is shutting down" >> "\$EVENT_LOG"
                        ;;
                    "-----d")
                        echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Domain \$DOMAIN_NAME has crashed" >> "\$EVENT_LOG"
                        ;;
                esac
            fi
        else
            if [[ -n "\$last_state" ]]; then
                echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Domain \$DOMAIN_NAME disappeared" >> "\$EVENT_LOG"
                last_state=""
            fi
        fi
        
        sleep 5
    done
}

# 로그 시작
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Event logging started for domain \$DOMAIN_NAME" >> "\$EVENT_LOG"

# 백그라운드 모니터링 시작
monitor_xenstore_events &
monitor_domain_state &

# 메인 프로세스 대기
wait
EOF
    
    chmod +x "$GUEST_CONFIG_DIR/event-logger-$domain_name.sh"
}

# 자동 도메인 감지 및 로깅 설정
setup_automatic_domain_logging() {
    log_section "자동 도메인 감지 및 로깅 설정"
    
    # 현재 실행 중인 도메인 감지
    xl list | tail -n +2 | while read -r domain_info; do
        local domain_name=$(echo "$domain_info" | awk '{print $1}')
        local domain_id=$(echo "$domain_info" | awk '{print $2}')
        
        # Domain-0는 제외
        if [[ "$domain_name" != "Domain-0" ]]; then
            log_info "도메인 감지됨: $domain_name (ID: $domain_id)"
            
            # 각 도메인별 로깅 설정
            setup_domain_console_logging "$domain_name" "$domain_id"
            setup_domain_performance_monitoring "$domain_name"
            setup_domain_event_logging "$domain_name"
            
            # systemd 서비스 생성
            create_domain_systemd_services "$domain_name"
        fi
    done
    
    # 새 도메인 자동 감지 스크립트
    create_domain_watcher_service
}

# 도메인별 systemd 서비스 생성
create_domain_systemd_services() {
    local domain_name="$1"
    
    log_debug "도메인 systemd 서비스 생성: $domain_name"
    
    # 콘솔 로깅 서비스
    cat > "/etc/systemd/system/xen-guest-console-$domain_name.service" << EOF
[Unit]
Description=Xen Guest Console Logger for $domain_name
After=xen.service
Wants=xen.service

[Service]
Type=simple
ExecStart=$GUEST_CONFIG_DIR/console-logger-$domain_name.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 성능 모니터링 서비스
    cat > "/etc/systemd/system/xen-guest-performance-$domain_name.service" << EOF
[Unit]
Description=Xen Guest Performance Monitor for $domain_name
After=xen.service
Wants=xen.service

[Service]
Type=simple
ExecStart=$GUEST_CONFIG_DIR/performance-monitor-$domain_name.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 이벤트 로깅 서비스
    cat > "/etc/systemd/system/xen-guest-events-$domain_name.service" << EOF
[Unit]
Description=Xen Guest Event Logger for $domain_name
After=xen.service
Wants=xen.service

[Service]
Type=simple
ExecStart=$GUEST_CONFIG_DIR/event-logger-$domain_name.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 서비스 활성화
    systemctl daemon-reload
    systemctl enable "xen-guest-console-$domain_name.service"
    systemctl enable "xen-guest-performance-$domain_name.service"
    systemctl enable "xen-guest-events-$domain_name.service"
    
    # 서비스 시작
    systemctl start "xen-guest-console-$domain_name.service"
    systemctl start "xen-guest-performance-$domain_name.service"
    systemctl start "xen-guest-events-$domain_name.service"
}

# 새 도메인 자동 감지 서비스
create_domain_watcher_service() {
    log_section "도메인 감시 서비스 생성"
    
    # 도메인 감시 스크립트
    cat > "$GUEST_CONFIG_DIR/domain-watcher.sh" << 'EOF'
#!/bin/bash

# 새 도메인 자동 감지 및 로깅 설정
KNOWN_DOMAINS_FILE="/var/run/xen-guest-logging/known-domains.txt"
GUEST_CONFIG_DIR="/etc/xen-guest-logging"

# 알려진 도메인 목록 파일 초기화
mkdir -p "$(dirname "$KNOWN_DOMAINS_FILE")"
touch "$KNOWN_DOMAINS_FILE"

# 새 도메인 감지 함수
detect_new_domains() {
    local current_domains=$(xl list | tail -n +2 | awk '{print $1}' | grep -v "Domain-0")
    local known_domains=$(cat "$KNOWN_DOMAINS_FILE" 2>/dev/null || echo "")
    
    for domain in $current_domains; do
        if ! echo "$known_domains" | grep -q "^$domain$"; then
            echo "New domain detected: $domain"
            echo "$domain" >> "$KNOWN_DOMAINS_FILE"
            
            # 새 도메인에 대한 로깅 설정
            setup_new_domain_logging "$domain"
        fi
    done
    
    # 제거된 도메인 정리
    for known_domain in $known_domains; do
        if ! echo "$current_domains" | grep -q "^$known_domain$"; then
            echo "Domain removed: $known_domain"
            cleanup_domain_logging "$known_domain"
            sed -i "/^$known_domain$/d" "$KNOWN_DOMAINS_FILE"
        fi
    done
}

# 새 도메인 로깅 설정
setup_new_domain_logging() {
    local domain_name="$1"
    echo "Setting up logging for new domain: $domain_name"
    
    # 메인 스크립트 호출하여 설정
    /var/log/xen-guest-logging/../../../code/xen_logging_system/guest_domain_logger.sh setup-domain "$domain_name"
}

# 도메인 로깅 정리
cleanup_domain_logging() {
    local domain_name="$1"
    echo "Cleaning up logging for removed domain: $domain_name"
    
    # 서비스 중지 및 비활성화
    systemctl stop "xen-guest-console-$domain_name.service" 2>/dev/null || true
    systemctl disable "xen-guest-console-$domain_name.service" 2>/dev/null || true
    systemctl stop "xen-guest-performance-$domain_name.service" 2>/dev/null || true
    systemctl disable "xen-guest-performance-$domain_name.service" 2>/dev/null || true
    systemctl stop "xen-guest-events-$domain_name.service" 2>/dev/null || true
    systemctl disable "xen-guest-events-$domain_name.service" 2>/dev/null || true
    
    # 서비스 파일 제거
    rm -f "/etc/systemd/system/xen-guest-console-$domain_name.service"
    rm -f "/etc/systemd/system/xen-guest-performance-$domain_name.service"
    rm -f "/etc/systemd/system/xen-guest-events-$domain_name.service"
    
    # 스크립트 파일 제거
    rm -f "$GUEST_CONFIG_DIR/console-logger-$domain_name.sh"
    rm -f "$GUEST_CONFIG_DIR/performance-monitor-$domain_name.sh"
    rm -f "$GUEST_CONFIG_DIR/event-logger-$domain_name.sh"
    
    systemctl daemon-reload
}

# 메인 감시 루프
echo "Domain watcher started at $(date)"

while true; do
    detect_new_domains
    sleep 30  # 30초마다 확인
done
EOF
    
    chmod +x "$GUEST_CONFIG_DIR/domain-watcher.sh"
    
    # 도메인 감시 systemd 서비스
    cat > /etc/systemd/system/xen-domain-watcher.service << EOF
[Unit]
Description=Xen Domain Watcher
After=xen.service xenconsoled.service
Wants=xen.service

[Service]
Type=simple
ExecStart=$GUEST_CONFIG_DIR/domain-watcher.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable xen-domain-watcher.service
    systemctl start xen-domain-watcher.service
    
    log_info "도메인 감시 서비스 설정 완료"
}

# 게스트 로그 분석 도구
create_guest_log_analysis_tools() {
    log_section "게스트 로그 분석 도구 생성"
    
    # 통합 분석 스크립트
    cat > "$GUEST_LOG_DIR/analyze_guest_logs.sh" << 'EOF'
#!/bin/bash

#####################################################################
# 게스트 도메인 로그 통합 분석 도구
#####################################################################

GUEST_LOG_DIR="/var/log/xen-guest-logging"
ANALYSIS_DIR="$GUEST_LOG_DIR/analysis"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

# 분석 보고서 생성
create_guest_analysis_report() {
    local report_file="$ANALYSIS_DIR/guest-analysis-$TIMESTAMP.html"
    
    mkdir -p "$ANALYSIS_DIR"
    
    cat > "$report_file" << 'HTML_START'
<!DOCTYPE html>
<html>
<head>
    <title>Xen Guest Domain Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .domain { background-color: #f9f9f9; margin: 10px 0; padding: 10px; border-radius: 3px; }
        .error { color: red; font-weight: bold; }
        .warning { color: orange; font-weight: bold; }
        .success { color: green; font-weight: bold; }
        .timestamp { color: #666; font-size: 0.9em; }
        pre { background: #f5f5f5; padding: 10px; overflow-x: auto; font-size: 0.9em; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .chart { margin: 10px 0; }
    </style>
</head>
<body>
HTML_START

    echo "<h1>Xen Guest Domain Analysis Report</h1>" >> "$report_file"
    echo "<p class='timestamp'>Generated: $(date)</p>" >> "$report_file"
    
    # 도메인 개요
    analyze_domain_overview "$report_file"
    
    # 도메인별 상세 분석
    analyze_individual_domains "$report_file"
    
    # 성능 요약
    analyze_performance_summary "$report_file"
    
    # 이벤트 요약
    analyze_events_summary "$report_file"
    
    # 문제점 및 권장사항
    analyze_issues_recommendations "$report_file"
    
    echo "</body></html>" >> "$report_file"
    
    echo "Guest domain analysis report generated: $report_file"
}

# 도메인 개요 분석
analyze_domain_overview() {
    local report_file="$1"
    
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Domain Overview</h2>" >> "$report_file"
    
    # 현재 실행 중인 도메인
    echo "<h3>Currently Running Domains</h3>" >> "$report_file"
    echo "<table>" >> "$report_file"
    echo "<tr><th>Name</th><th>ID</th><th>Memory (MB)</th><th>VCPUs</th><th>State</th><th>Time</th></tr>" >> "$report_file"
    
    xl list | tail -n +2 | while read -r line; do
        local name=$(echo "$line" | awk '{print $1}')
        local id=$(echo "$line" | awk '{print $2}')
        local mem=$(echo "$line" | awk '{print $3}')
        local vcpus=$(echo "$line" | awk '{print $4}')
        local state=$(echo "$line" | awk '{print $5}')
        local time=$(echo "$line" | awk '{print $6}')
        
        if [[ "$name" != "Domain-0" ]]; then
            echo "<tr><td>$name</td><td>$id</td><td>$mem</td><td>$vcpus</td><td>$state</td><td>$time</td></tr>" >> "$report_file"
        fi
    done
    
    echo "</table>" >> "$report_file"
    echo "</div>" >> "$report_file"
}

# 도메인별 상세 분석
analyze_individual_domains() {
    local report_file="$1"
    
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Individual Domain Analysis</h2>" >> "$report_file"
    
    for domain_dir in "$GUEST_LOG_DIR/console-logs"/*; do
        if [[ -d "$domain_dir" ]]; then
            local domain_name=$(basename "$domain_dir")
            
            echo "<div class='domain'>" >> "$report_file"
            echo "<h3>Domain: $domain_name</h3>" >> "$report_file"
            
            # 콘솔 로그 분석
            analyze_console_logs "$domain_name" "$report_file"
            
            # 성능 로그 분석
            analyze_performance_logs "$domain_name" "$report_file"
            
            # 이벤트 로그 분석
            analyze_event_logs "$domain_name" "$report_file"
            
            echo "</div>" >> "$report_file"
        fi
    done
    
    echo "</div>" >> "$report_file"
}

# 콘솔 로그 분석
analyze_console_logs() {
    local domain_name="$1"
    local report_file="$2"
    
    local console_dir="$GUEST_LOG_DIR/console-logs/$domain_name"
    local latest_console=$(ls -t "$console_dir"/*.log 2>/dev/null | head -n1)
    
    if [[ -n "$latest_console" ]]; then
        echo "<h4>Console Log Analysis</h4>" >> "$report_file"
        echo "<p>Latest log: $(basename "$latest_console")</p>" >> "$report_file"
        
        local log_size=$(du -h "$latest_console" | cut -f1)
        local line_count=$(wc -l < "$latest_console")
        echo "<p>Log size: $log_size, Lines: $line_count</p>" >> "$report_file"
        
        # 에러 및 경고 검출
        local errors=$(grep -c -iE "error|fail|panic|fatal" "$latest_console" 2>/dev/null || echo 0)
        local warnings=$(grep -c -iE "warn|warning" "$latest_console" 2>/dev/null || echo 0)
        
        echo "<p>Errors: $errors, Warnings: $warnings</p>" >> "$report_file"
        
        if [[ $errors -gt 0 ]]; then
            echo "<h5>Recent Errors:</h5>" >> "$report_file"
            echo "<pre>" >> "$report_file"
            grep -iE "error|fail|panic|fatal" "$latest_console" | tail -n5 >> "$report_file"
            echo "</pre>" >> "$report_file"
        fi
    else
        echo "<p class='warning'>No console logs found for $domain_name</p>" >> "$report_file"
    fi
}

# 성능 로그 분석
analyze_performance_logs() {
    local domain_name="$1"
    local report_file="$2"
    
    local perf_dir="$GUEST_LOG_DIR/performance/$domain_name"
    local latest_perf=$(ls -t "$perf_dir"/*.log 2>/dev/null | head -n1)
    
    if [[ -n "$latest_perf" ]]; then
        echo "<h4>Performance Analysis</h4>" >> "$report_file"
        
        # 최근 성능 데이터 추출
        local cpu_usage=$(grep -o "CPU.*%" "$latest_perf" | tail -n1 || echo "N/A")
        local memory_usage=$(grep -o "Memory:.*MB" "$latest_perf" | tail -n1 || echo "N/A")
        
        echo "<p>Recent CPU Usage: $cpu_usage</p>" >> "$report_file"
        echo "<p>Recent Memory Usage: $memory_usage</p>" >> "$report_file"
    else
        echo "<p class='warning'>No performance logs found for $domain_name</p>" >> "$report_file"
    fi
}

# 이벤트 로그 분석
analyze_event_logs() {
    local domain_name="$1"
    local report_file="$2"
    
    local event_dir="$GUEST_LOG_DIR/events/$domain_name"
    local latest_event=$(ls -t "$event_dir"/*.log 2>/dev/null | head -n1)
    
    if [[ -n "$latest_event" ]]; then
        echo "<h4>Event Analysis</h4>" >> "$report_file"
        
        local state_changes=$(grep -c "State Change" "$latest_event" 2>/dev/null || echo 0)
        local crashes=$(grep -c "crashed" "$latest_event" 2>/dev/null || echo 0)
        
        echo "<p>State Changes: $state_changes</p>" >> "$report_file"
        echo "<p>Crashes: $crashes</p>" >> "$report_file"
        
        if [[ $crashes -gt 0 ]]; then
            echo "<h5>Recent Crashes:</h5>" >> "$report_file"
            echo "<pre>" >> "$report_file"
            grep "crashed" "$latest_event" | tail -n3 >> "$report_file"
            echo "</pre>" >> "$report_file"
        fi
    else
        echo "<p class='warning'>No event logs found for $domain_name</p>" >> "$report_file"
    fi
}

# 성능 요약
analyze_performance_summary() {
    local report_file="$1"
    
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Performance Summary</h2>" >> "$report_file"
    echo "<p>Overall system performance analysis across all guest domains.</p>" >> "$report_file"
    echo "</div>" >> "$report_file"
}

# 이벤트 요약
analyze_events_summary() {
    local report_file="$1"
    
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Events Summary</h2>" >> "$report_file"
    echo "<p>Summary of significant events across all guest domains.</p>" >> "$report_file"
    echo "</div>" >> "$report_file"
}

# 문제점 및 권장사항
analyze_issues_recommendations() {
    local report_file="$1"
    
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Issues and Recommendations</h2>" >> "$report_file"
    echo "<p>Identified issues and recommendations for optimization.</p>" >> "$report_file"
    echo "</div>" >> "$report_file"
}

# 메인 실행
main() {
    echo "Starting guest domain log analysis..."
    create_guest_analysis_report
    echo "Analysis complete!"
}

main "$@"
EOF
    
    chmod +x "$GUEST_LOG_DIR/analyze_guest_logs.sh"
    
    log_info "게스트 로그 분석 도구 생성 완료"
}

# 로그 회전 설정
setup_guest_log_rotation() {
    log_section "게스트 로그 회전 설정"
    
    cat > /etc/logrotate.d/xen-guest-logging << 'EOF'
/var/log/xen-guest-logging/*/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        # 로그 회전 후 서비스 재시작
        systemctl reload xen-domain-watcher 2>/dev/null || true
    endscript
}
EOF
    
    log_info "게스트 로그 회전 설정 완료"
}

# 사용법 출력
show_usage() {
    echo "사용법: $0 [명령어] [옵션]"
    echo
    echo "명령어:"
    echo "  setup               전체 게스트 로깅 시스템 설정"
    echo "  setup-domain NAME   특정 도메인 로깅 설정"
    echo "  analyze             게스트 로그 분석 보고서 생성"
    echo "  scan                현재 도메인 상태 스캔"
    echo "  status              로깅 서비스 상태 확인"
    echo
    echo "옵션:"
    echo "  -h, --help          이 도움말 출력"
    echo
    echo "예시:"
    echo "  sudo $0 setup                    # 전체 시스템 설정"
    echo "  sudo $0 setup-domain ubuntu     # ubuntu 도메인만 설정"
    echo "  sudo $0 analyze                 # HTML 분석 보고서 생성"
    echo "  sudo $0 scan                    # 현재 도메인 스캔"
}

# 특정 도메인 설정
setup_single_domain() {
    local domain_name="$1"
    
    if [[ -z "$domain_name" ]]; then
        log_error "도메인 이름을 지정해주세요."
        show_usage
        exit 1
    fi
    
    log_section "도메인 '$domain_name' 로깅 설정"
    
    # 도메인 존재 확인
    if ! xl list "$domain_name" >/dev/null 2>&1; then
        log_error "도메인 '$domain_name'을 찾을 수 없습니다."
        exit 1
    fi
    
    local domain_id=$(xl list "$domain_name" | tail -n1 | awk '{print $2}')
    
    setup_domain_console_logging "$domain_name" "$domain_id"
    setup_domain_performance_monitoring "$domain_name"
    setup_domain_event_logging "$domain_name"
    create_domain_systemd_services "$domain_name"
    
    log_info "도메인 '$domain_name' 로깅 설정 완료"
}

# 상태 확인
check_status() {
    log_section "게스트 로깅 시스템 상태"
    
    echo "도메인 감시 서비스:"
    systemctl status xen-domain-watcher.service --no-pager -l | head -n5 || echo "서비스가 실행되지 않음"
    
    echo -e "\n활성 게스트 로깅 서비스:"
    systemctl list-units --type=service --state=running | grep "xen-guest-" || echo "활성 서비스 없음"
    
    echo -e "\n로그 디렉토리 크기:"
    du -sh "$GUEST_LOG_DIR" 2>/dev/null || echo "로그 디렉토리 없음"
}

# 메인 함수
main() {
    local command="${1:-setup}"
    
    case "$command" in
        setup)
            init_guest_logging
            scan_domains
            setup_automatic_domain_logging
            create_guest_log_analysis_tools
            setup_guest_log_rotation
            log_info "게스트 도메인 로깅 시스템 설정 완료!"
            ;;
        setup-domain)
            init_guest_logging
            setup_single_domain "$2"
            ;;
        analyze)
            if [[ -f "$GUEST_LOG_DIR/analyze_guest_logs.sh" ]]; then
                "$GUEST_LOG_DIR/analyze_guest_logs.sh"
            else
                log_error "분석 도구가 설치되지 않았습니다. 먼저 'setup'을 실행하세요."
            fi
            ;;
        scan)
            scan_domains
            ;;
        status)
            check_status
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "알 수 없는 명령어: $command"
            show_usage
            exit 1
            ;;
    esac
}

# 스크립트 실행
main "$@"