#!/bin/bash

#####################################################################
# Xen 부팅 과정 전체 로그 기록 시스템 v1.0
# BIOS/UEFI부터 게스트 도메인까지 완전한 부팅 로그 수집
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

# 전역 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_BASE_DIR="/var/log/xen-boot-logging"
CONFIG_DIR="/etc/xen-boot-logging"
RUNTIME_DIR="/var/run/xen-boot-logging"
LOG_VERSION="1.0"

# 로그 수집 모듈 상태
declare -A LOGGING_MODULES=(
    ["bios_uefi"]="INACTIVE"
    ["bootloader"]="INACTIVE"
    ["xen_hypervisor"]="INACTIVE"
    ["dom0_kernel"]="INACTIVE"
    ["guest_domains"]="INACTIVE"
    ["system_services"]="INACTIVE"
)

# 로깅 함수
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${CYAN}[DEBUG]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# 타임스탬프 생성
get_timestamp() {
    date '+%Y%m%d-%H%M%S'
}

get_timestamp_ms() {
    date '+%Y-%m-%d %H:%M:%S.%3N'
}

# 초기화
init_logging_system() {
    log_section "Xen 부팅 로그 시스템 초기화"
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        exit 1
    fi
    
    # 디렉토리 구조 생성
    mkdir -p "$LOG_BASE_DIR"/{bios-uefi,bootloader,xen-hypervisor,dom0-kernel,guest-domains,system-services,analysis}
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$RUNTIME_DIR"
    
    # 로그 디렉토리 권한 설정
    chmod 755 "$LOG_BASE_DIR"
    chmod 755 "$CONFIG_DIR"
    chmod 755 "$RUNTIME_DIR"
    
    log_info "로그 시스템 디렉토리 구조 생성 완료"
    log_info "기본 로그 디렉토리: $LOG_BASE_DIR"
}

# BIOS/UEFI 로그 수집 설정
setup_bios_uefi_logging() {
    log_section "BIOS/UEFI 로그 수집 설정"
    
    local session_id=$(get_timestamp)
    local log_dir="$LOG_BASE_DIR/bios-uefi"
    
    # UEFI 펌웨어 이벤트 로그 수집
    if [[ -d /sys/firmware/efi ]]; then
        log_info "UEFI 시스템 감지됨"
        
        # UEFI 변수 로그
        cat > "$log_dir/uefi-variables-$session_id.log" << 'EOF'
# UEFI 변수 로그 수집
EOF
        
        if [[ -d /sys/firmware/efi/efivars ]]; then
            echo "=== UEFI Variables ===" >> "$log_dir/uefi-variables-$session_id.log"
            ls -la /sys/firmware/efi/efivars/ >> "$log_dir/uefi-variables-$session_id.log" 2>/dev/null || true
        fi
        
        # UEFI 부팅 항목
        if command -v efibootmgr >/dev/null; then
            echo "=== UEFI Boot Manager ===" >> "$log_dir/uefi-boot-$session_id.log"
            efibootmgr -v >> "$log_dir/uefi-boot-$session_id.log" 2>/dev/null || true
        fi
        
        # ACPI 테이블 정보
        if [[ -d /sys/firmware/acpi/tables ]]; then
            echo "=== ACPI Tables ===" >> "$log_dir/acpi-tables-$session_id.log"
            ls -la /sys/firmware/acpi/tables/ >> "$log_dir/acpi-tables-$session_id.log" 2>/dev/null || true
        fi
        
        LOGGING_MODULES["bios_uefi"]="ACTIVE"
        log_info "UEFI 로그 수집 활성화됨"
    else
        log_info "Legacy BIOS 시스템 감지됨"
        
        # BIOS 정보 수집
        echo "=== BIOS Information ===" > "$log_dir/bios-info-$session_id.log"
        dmidecode -t bios >> "$log_dir/bios-info-$session_id.log" 2>/dev/null || true
        
        LOGGING_MODULES["bios_uefi"]="ACTIVE"
        log_info "BIOS 로그 수집 활성화됨"
    fi
    
    # 하드웨어 정보 수집
    echo "=== Hardware Information ===" > "$log_dir/hardware-info-$session_id.log"
    {
        echo "CPU Information:"
        cat /proc/cpuinfo | head -n20
        echo
        echo "Memory Information:"
        cat /proc/meminfo | head -n10
        echo
        echo "PCI Devices:"
        lspci
        echo
        echo "USB Devices:"
        lsusb
    } >> "$log_dir/hardware-info-$session_id.log" 2>/dev/null || true
}

# 부트로더 로그 설정
setup_bootloader_logging() {
    log_section "부트로더 로그 설정"
    
    local session_id=$(get_timestamp)
    local log_dir="$LOG_BASE_DIR/bootloader"
    
    # GRUB 설정 분석
    echo "=== GRUB Configuration Analysis ===" > "$log_dir/grub-analysis-$session_id.log"
    {
        echo "GRUB Default Settings:"
        cat /etc/default/grub
        echo
        echo "GRUB Configuration:"
        grep -E "menuentry|multiboot" /boot/grub/grub.cfg | head -n20
        echo
        echo "Current Boot Parameters:"
        cat /proc/cmdline
    } >> "$log_dir/grub-analysis-$session_id.log" 2>/dev/null || true
    
    # 부트 메시지 수집 설정
    # 이는 다음 부팅 시 수집됩니다
    cat > "$CONFIG_DIR/bootloader-logging.conf" << 'EOF'
# 부트로더 로그 설정
GRUB_TERMINAL_OUTPUT="console serial"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
EOF
    
    # systemd-boot 로그 (존재하는 경우)
    if [[ -d /boot/loader ]]; then
        echo "=== systemd-boot Configuration ===" > "$log_dir/systemd-boot-$session_id.log"
        find /boot/loader -name "*.conf" -exec cat {} + >> "$log_dir/systemd-boot-$session_id.log" 2>/dev/null || true
    fi
    
    LOGGING_MODULES["bootloader"]="ACTIVE"
    log_info "부트로더 로그 수집 활성화됨"
}

# Xen 하이퍼바이저 로그 설정
setup_xen_hypervisor_logging() {
    log_section "Xen 하이퍼바이저 로그 설정"
    
    local session_id=$(get_timestamp)
    local log_dir="$LOG_BASE_DIR/xen-hypervisor"
    
    # Xen이 설치되어 있는지 확인
    if ! command -v xl >/dev/null; then
        log_warn "Xen이 설치되어 있지 않습니다. 하이퍼바이저 로그를 건너뜁니다."
        LOGGING_MODULES["xen_hypervisor"]="INACTIVE"
        return
    fi
    
    # Xen 정보 수집
    echo "=== Xen System Information ===" > "$log_dir/xen-info-$session_id.log"
    {
        if xl info >/dev/null 2>&1; then
            echo "Xen Hypervisor Information:"
            xl info
            echo
            echo "Domain List:"
            xl list
            echo
            echo "vCPU Information:"
            xl vcpu-list
            echo
            echo "Memory Information:"
            xl mem-max 0 2>/dev/null || echo "Memory information not available"
        else
            echo "Xen hypervisor not running or accessible"
        fi
    } >> "$log_dir/xen-info-$session_id.log" 2>/dev/null || true
    
    # Xen 하이퍼바이저 로그 수집
    echo "=== Xen Hypervisor Log ===" > "$log_dir/xen-dmesg-$session_id.log"
    if xl dmesg >/dev/null 2>&1; then
        xl dmesg >> "$log_dir/xen-dmesg-$session_id.log" 2>/dev/null || true
    else
        echo "Xen dmesg not available (not running under Xen)" >> "$log_dir/xen-dmesg-$session_id.log"
    fi
    
    # Xen 설정 파일 백업
    if [[ -f /etc/xen/xl.conf ]]; then
        cp /etc/xen/xl.conf "$log_dir/xl-conf-$session_id.backup"
    fi
    
    # 지속적 로그 수집 스크립트 생성
    cat > "$CONFIG_DIR/xen-continuous-logging.sh" << 'EOF'
#!/bin/bash
# Xen 지속적 로그 수집

LOG_DIR="/var/log/xen-boot-logging/xen-hypervisor"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

# 5분마다 실행
while true; do
    if command -v xl >/dev/null && xl info >/dev/null 2>&1; then
        {
            echo "=== $(date) ==="
            echo "Domain List:"
            xl list
            echo "vCPU List:"
            xl vcpu-list
            echo "Recent Xen Messages:"
            xl dmesg | tail -n20
            echo
        } >> "$LOG_DIR/xen-continuous-$(date '+%Y%m%d').log"
    fi
    sleep 300
done
EOF
    
    chmod +x "$CONFIG_DIR/xen-continuous-logging.sh"
    
    LOGGING_MODULES["xen_hypervisor"]="ACTIVE"
    log_info "Xen 하이퍼바이저 로그 수집 활성화됨"
}

# Dom0 커널 로그 설정
setup_dom0_kernel_logging() {
    log_section "Dom0 커널 로그 설정"
    
    local session_id=$(get_timestamp)
    local log_dir="$LOG_BASE_DIR/dom0-kernel"
    
    # 현재 커널 로그 수집
    echo "=== Dom0 Kernel Log ===" > "$log_dir/kernel-log-$session_id.log"
    dmesg -T >> "$log_dir/kernel-log-$session_id.log" 2>/dev/null || true
    
    # 커널 모듈 정보
    echo "=== Loaded Kernel Modules ===" > "$log_dir/kernel-modules-$session_id.log"
    lsmod >> "$log_dir/kernel-modules-$session_id.log" 2>/dev/null || true
    
    # 커널 매개변수
    echo "=== Kernel Parameters ===" > "$log_dir/kernel-params-$session_id.log"
    cat /proc/cmdline >> "$log_dir/kernel-params-$session_id.log" 2>/dev/null || true
    
    # 시스템 정보
    echo "=== System Information ===" > "$log_dir/system-info-$session_id.log"
    {
        echo "Kernel Version:"
        uname -a
        echo
        echo "OS Information:"
        cat /etc/os-release
        echo
        echo "Uptime:"
        uptime
        echo
        echo "Load Average:"
        cat /proc/loadavg
    } >> "$log_dir/system-info-$session_id.log" 2>/dev/null || true
    
    # journalctl 로그 수집 설정
    cat > "$CONFIG_DIR/dom0-journal-logging.sh" << 'EOF'
#!/bin/bash
# Dom0 journalctl 지속적 로그 수집

LOG_DIR="/var/log/xen-boot-logging/dom0-kernel"
TIMESTAMP=$(date '+%Y%m%d')

# 부팅 관련 로그 수집
journalctl -b 0 > "$LOG_DIR/journal-boot-$TIMESTAMP.log"

# Xen 관련 서비스 로그
journalctl -u xen* > "$LOG_DIR/journal-xen-services-$TIMESTAMP.log"

# 커널 메시지
journalctl -k > "$LOG_DIR/journal-kernel-$TIMESTAMP.log"

# 실시간 로그 모니터링 (백그라운드)
journalctl -f --no-tail > "$LOG_DIR/journal-realtime-$TIMESTAMP.log" &
EOF
    
    chmod +x "$CONFIG_DIR/dom0-journal-logging.sh"
    
    LOGGING_MODULES["dom0_kernel"]="ACTIVE"
    log_info "Dom0 커널 로그 수집 활성화됨"
}

# 게스트 도메인 로그 설정
setup_guest_domain_logging() {
    log_section "게스트 도메인 로그 설정"
    
    local session_id=$(get_timestamp)
    local log_dir="$LOG_BASE_DIR/guest-domains"
    
    # 게스트 도메인 설정 파일 스캔
    echo "=== Guest Domain Configurations ===" > "$log_dir/guest-configs-$session_id.log"
    if [[ -d /etc/xen ]]; then
        find /etc/xen -name "*.cfg" -o -name "*.conf" | while read -r config_file; do
            echo "Configuration: $config_file" >> "$log_dir/guest-configs-$session_id.log"
            cat "$config_file" >> "$log_dir/guest-configs-$session_id.log" 2>/dev/null || true
            echo "---" >> "$log_dir/guest-configs-$session_id.log"
        done
    fi
    
    # 자동 시작 도메인 확인
    if [[ -d /etc/xen/auto ]]; then
        echo "=== Auto-start Domains ===" > "$log_dir/autostart-domains-$session_id.log"
        ls -la /etc/xen/auto/ >> "$log_dir/autostart-domains-$session_id.log" 2>/dev/null || true
    fi
    
    # 게스트 도메인 로그 수집 스크립트
    cat > "$CONFIG_DIR/guest-domain-logging.sh" << 'EOF'
#!/bin/bash
# 게스트 도메인 로그 수집

LOG_DIR="/var/log/xen-boot-logging/guest-domains"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

# xl이 사용 가능한지 확인
if ! command -v xl >/dev/null; then
    echo "xl command not available" > "$LOG_DIR/guest-error-$TIMESTAMP.log"
    exit 1
fi

# 현재 실행 중인 도메인 목록
echo "=== Running Domains ===" > "$LOG_DIR/running-domains-$TIMESTAMP.log"
xl list >> "$LOG_DIR/running-domains-$TIMESTAMP.log" 2>/dev/null || true

# 각 도메인별 상세 정보
xl list | tail -n +2 | while read -r domain_info; do
    domain_name=$(echo "$domain_info" | awk '{print $1}')
    domain_id=$(echo "$domain_info" | awk '{print $2}')
    
    if [[ "$domain_name" != "Domain-0" ]]; then
        echo "=== Domain: $domain_name (ID: $domain_id) ===" > "$LOG_DIR/domain-$domain_name-$TIMESTAMP.log"
        
        # 도메인 상세 정보
        xl list "$domain_name" >> "$LOG_DIR/domain-$domain_name-$TIMESTAMP.log" 2>/dev/null || true
        
        # 도메인 설정 정보
        xl list -l "$domain_name" >> "$LOG_DIR/domain-$domain_name-detail-$TIMESTAMP.log" 2>/dev/null || true
        
        # vCPU 정보
        xl vcpu-list "$domain_name" >> "$LOG_DIR/domain-$domain_name-vcpu-$TIMESTAMP.log" 2>/dev/null || true
        
        # 네트워크 정보
        xl network-list "$domain_name" >> "$LOG_DIR/domain-$domain_name-network-$TIMESTAMP.log" 2>/dev/null || true
        
        # 블록 디바이스 정보
        xl block-list "$domain_name" >> "$LOG_DIR/domain-$domain_name-block-$TIMESTAMP.log" 2>/dev/null || true
    fi
done

# XenStore 정보
if command -v xenstore-ls >/dev/null; then
    echo "=== XenStore Information ===" > "$LOG_DIR/xenstore-$TIMESTAMP.log"
    xenstore-ls / >> "$LOG_DIR/xenstore-$TIMESTAMP.log" 2>/dev/null || true
fi
EOF
    
    chmod +x "$CONFIG_DIR/guest-domain-logging.sh"
    
    LOGGING_MODULES["guest_domains"]="ACTIVE"
    log_info "게스트 도메인 로그 수집 활성화됨"
}

# 시스템 서비스 로그 설정
setup_system_services_logging() {
    log_section "시스템 서비스 로그 설정"
    
    local session_id=$(get_timestamp)
    local log_dir="$LOG_BASE_DIR/system-services"
    
    # 시스템 서비스 상태 수집
    echo "=== System Services Status ===" > "$log_dir/services-status-$session_id.log"
    systemctl list-units --type=service --state=running >> "$log_dir/services-status-$session_id.log" 2>/dev/null || true
    
    # Xen 관련 서비스 상세 정보
    echo "=== Xen Services Detail ===" > "$log_dir/xen-services-detail-$session_id.log"
    local xen_services=("xenconsoled" "xen-qemu-dom0-disk-backend" "xenstored" "xen-init-dom0")
    
    for service in "${xen_services[@]}"; do
        if systemctl list-unit-files | grep -q "$service"; then
            echo "Service: $service" >> "$log_dir/xen-services-detail-$session_id.log"
            systemctl status "$service" >> "$log_dir/xen-services-detail-$session_id.log" 2>/dev/null || true
            echo "---" >> "$log_dir/xen-services-detail-$session_id.log"
        fi
    done
    
    # 부팅 성능 분석
    echo "=== Boot Performance Analysis ===" > "$log_dir/boot-performance-$session_id.log"
    if command -v systemd-analyze >/dev/null; then
        systemd-analyze >> "$log_dir/boot-performance-$session_id.log" 2>/dev/null || true
        echo >> "$log_dir/boot-performance-$session_id.log"
        systemd-analyze blame | head -n20 >> "$log_dir/boot-performance-$session_id.log" 2>/dev/null || true
    fi
    
    LOGGING_MODULES["system_services"]="ACTIVE"
    log_info "시스템 서비스 로그 수집 활성화됨"
}

# 로그 분석 도구 설정
setup_log_analysis_tools() {
    log_section "로그 분석 도구 설정"
    
    # 통합 로그 분석 스크립트
    cat > "$LOG_BASE_DIR/analyze_boot_logs.sh" << 'EOF'
#!/bin/bash

#####################################################################
# Xen 부팅 로그 통합 분석 도구
#####################################################################

LOG_BASE_DIR="/var/log/xen-boot-logging"
ANALYSIS_DIR="$LOG_BASE_DIR/analysis"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

# 분석 보고서 생성
create_analysis_report() {
    local report_file="$ANALYSIS_DIR/boot-analysis-$TIMESTAMP.html"
    
    cat > "$report_file" << 'HTML_START'
<!DOCTYPE html>
<html>
<head>
    <title>Xen Boot Log Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; }
        .error { color: red; font-weight: bold; }
        .warning { color: orange; font-weight: bold; }
        .success { color: green; font-weight: bold; }
        .timestamp { color: #666; font-size: 0.9em; }
        pre { background: #f5f5f5; padding: 10px; overflow-x: auto; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
HTML_START

    echo "<h1>Xen Boot Log Analysis Report</h1>" >> "$report_file"
    echo "<p class='timestamp'>Generated: $(date)</p>" >> "$report_file"
    
    # 시스템 개요
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>System Overview</h2>" >> "$report_file"
    echo "<table>" >> "$report_file"
    echo "<tr><th>Property</th><th>Value</th></tr>" >> "$report_file"
    echo "<tr><td>Hostname</td><td>$(hostname)</td></tr>" >> "$report_file"
    echo "<tr><td>OS</td><td>$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)</td></tr>" >> "$report_file"
    echo "<tr><td>Kernel</td><td>$(uname -r)</td></tr>" >> "$report_file"
    if command -v xl >/dev/null && xl info >/dev/null 2>&1; then
        echo "<tr><td>Xen Version</td><td>$(xl info | grep xen_version | awk '{print $3}')</td></tr>" >> "$report_file"
        echo "<tr><td>Boot Mode</td><td>Xen Hypervisor</td></tr>" >> "$report_file"
    else
        echo "<tr><td>Boot Mode</td><td>Native Kernel</td></tr>" >> "$report_file"
    fi
    echo "</table>" >> "$report_file"
    echo "</div>" >> "$report_file"
    
    # 부팅 단계별 분석
    analyze_boot_stages "$report_file"
    
    # 오류 및 경고 요약
    analyze_errors_warnings "$report_file"
    
    # 성능 분석
    analyze_performance "$report_file"
    
    echo "</body></html>" >> "$report_file"
    
    echo "Analysis report generated: $report_file"
}

# 부팅 단계별 분석
analyze_boot_stages() {
    local report_file="$1"
    
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Boot Stages Analysis</h2>" >> "$report_file"
    
    # BIOS/UEFI 단계
    if [[ -d "$LOG_BASE_DIR/bios-uefi" ]]; then
        echo "<h3>BIOS/UEFI Stage</h3>" >> "$report_file"
        local latest_hardware=$(ls -t "$LOG_BASE_DIR/bios-uefi"/hardware-info-*.log 2>/dev/null | head -n1)
        if [[ -n "$latest_hardware" ]]; then
            echo "<p class='success'>Hardware information collected</p>" >> "$report_file"
            echo "<pre>$(head -n20 "$latest_hardware")</pre>" >> "$report_file"
        else
            echo "<p class='warning'>No hardware information found</p>" >> "$report_file"
        fi
    fi
    
    # 부트로더 단계
    if [[ -d "$LOG_BASE_DIR/bootloader" ]]; then
        echo "<h3>Bootloader Stage</h3>" >> "$report_file"
        local latest_grub=$(ls -t "$LOG_BASE_DIR/bootloader"/grub-analysis-*.log 2>/dev/null | head -n1)
        if [[ -n "$latest_grub" ]]; then
            echo "<p class='success'>GRUB configuration analyzed</p>" >> "$report_file"
            echo "<pre>$(grep -A5 "Current Boot Parameters:" "$latest_grub" || echo "No boot parameters found")</pre>" >> "$report_file"
        fi
    fi
    
    # Xen 하이퍼바이저 단계
    if [[ -d "$LOG_BASE_DIR/xen-hypervisor" ]]; then
        echo "<h3>Xen Hypervisor Stage</h3>" >> "$report_file"
        local latest_xen=$(ls -t "$LOG_BASE_DIR/xen-hypervisor"/xen-info-*.log 2>/dev/null | head -n1)
        if [[ -n "$latest_xen" ]] && grep -q "Xen Hypervisor Information:" "$latest_xen"; then
            echo "<p class='success'>Xen hypervisor is running</p>" >> "$report_file"
            echo "<pre>$(grep -A10 "Xen Hypervisor Information:" "$latest_xen" || echo "No Xen info found")</pre>" >> "$report_file"
        else
            echo "<p class='warning'>Xen hypervisor not detected or not running</p>" >> "$report_file"
        fi
    fi
    
    echo "</div>" >> "$report_file"
}

# 오류 및 경고 분석
analyze_errors_warnings() {
    local report_file="$1"
    
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Errors and Warnings</h2>" >> "$report_file"
    
    # 로그에서 오류 패턴 검색
    local error_patterns=("error" "Error" "ERROR" "fail" "Fail" "FAIL" "panic" "PANIC")
    local warning_patterns=("warn" "Warn" "WARN" "warning" "Warning" "WARNING")
    
    echo "<h3>Critical Errors</h3>" >> "$report_file"
    local error_found=false
    for pattern in "${error_patterns[@]}"; do
        find "$LOG_BASE_DIR" -name "*.log" -exec grep -l "$pattern" {} + | while read -r log_file; do
            if [[ ! "$error_found" == "true" ]]; then
                echo "<ul>" >> "$report_file"
                error_found=true
            fi
            echo "<li>$(basename "$log_file"): $(grep "$pattern" "$log_file" | head -n1)</li>" >> "$report_file"
        done
    done
    if [[ ! "$error_found" == "true" ]]; then
        echo "<p class='success'>No critical errors found</p>" >> "$report_file"
    else
        echo "</ul>" >> "$report_file"
    fi
    
    echo "</div>" >> "$report_file"
}

# 성능 분석
analyze_performance() {
    local report_file="$1"
    
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Performance Analysis</h2>" >> "$report_file"
    
    # 부팅 시간 분석
    if command -v systemd-analyze >/dev/null; then
        echo "<h3>Boot Time</h3>" >> "$report_file"
        echo "<pre>$(systemd-analyze 2>/dev/null || echo "Boot time analysis not available")</pre>" >> "$report_file"
        
        echo "<h3>Slowest Services</h3>" >> "$report_file"
        echo "<pre>$(systemd-analyze blame 2>/dev/null | head -n10 || echo "Service analysis not available")</pre>" >> "$report_file"
    fi
    
    # 리소스 사용량
    if command -v xl >/dev/null && xl info >/dev/null 2>&1; then
        echo "<h3>Resource Usage</h3>" >> "$report_file"
        echo "<pre>" >> "$report_file"
        echo "Memory Usage:" >> "$report_file"
        xl info | grep -E "total_memory|free_memory" >> "$report_file" 2>/dev/null || true
        echo >> "$report_file"
        echo "Domain Resource Usage:" >> "$report_file"
        xl list >> "$report_file" 2>/dev/null || true
        echo "</pre>" >> "$report_file"
    fi
    
    echo "</div>" >> "$report_file"
}

# 메인 실행
main() {
    echo "Starting boot log analysis..."
    mkdir -p "$ANALYSIS_DIR"
    create_analysis_report
    echo "Analysis complete!"
}

main "$@"
EOF
    
    chmod +x "$LOG_BASE_DIR/analyze_boot_logs.sh"
    
    # 실시간 로그 모니터링 도구
    cat > "$LOG_BASE_DIR/monitor_realtime_logs.sh" << 'EOF'
#!/bin/bash

#####################################################################
# 실시간 로그 모니터링 도구
#####################################################################

LOG_BASE_DIR="/var/log/xen-boot-logging"

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Xen Real-time Log Monitor ===${NC}"
echo "Monitoring all Xen boot logs in real-time..."
echo "Press Ctrl+C to stop"
echo

# 실시간 로그 모니터링
tail -f "$LOG_BASE_DIR"/*/*.log 2>/dev/null | while read -r line; do
    # 오류 패턴 하이라이팅
    if echo "$line" | grep -qiE "error|fail|panic|fatal"; then
        echo -e "${RED}[ERROR] $line${NC}"
    elif echo "$line" | grep -qiE "warn|warning"; then
        echo -e "${YELLOW}[WARN] $line${NC}"
    elif echo "$line" | grep -qiE "success|ok|complete|done"; then
        echo -e "${GREEN}[INFO] $line${NC}"
    else
        echo "$line"
    fi
done
EOF
    
    chmod +x "$LOG_BASE_DIR/monitor_realtime_logs.sh"
    
    log_info "로그 분석 도구 설정 완료"
}

# 시스템 서비스 등록
install_systemd_services() {
    log_section "systemd 서비스 등록"
    
    # Xen 부팅 로그 수집 서비스
    cat > /etc/systemd/system/xen-boot-logging.service << 'EOF'
[Unit]
Description=Xen Boot Logging Service
After=xen.service xenconsoled.service
Wants=xen.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/xen-boot-logger.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 주 실행 스크립트 복사
    cp "$SCRIPT_DIR/$(basename "$0")" /usr/local/bin/xen-boot-logger.sh
    chmod +x /usr/local/bin/xen-boot-logger.sh
    
    # 서비스 활성화
    systemctl daemon-reload
    systemctl enable xen-boot-logging.service
    
    log_info "systemd 서비스 등록 완료"
}

# 로그 회전 설정
setup_log_rotation() {
    log_section "로그 회전 설정"
    
    cat > /etc/logrotate.d/xen-boot-logging << 'EOF'
/var/log/xen-boot-logging/*/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        # 로그 회전 후 처리 작업
        systemctl reload xen-boot-logging 2>/dev/null || true
    endscript
}
EOF
    
    log_info "로그 회전 설정 완료"
}

# 모든 로그 수집 실행
collect_all_logs() {
    log_section "전체 로그 수집 실행"
    
    # 각 모듈 실행
    "$CONFIG_DIR/dom0-journal-logging.sh" &
    "$CONFIG_DIR/guest-domain-logging.sh" &
    "$CONFIG_DIR/xen-continuous-logging.sh" &
    
    log_info "백그라운드 로그 수집 프로세스 시작됨"
}

# 상태 확인
check_logging_status() {
    log_section "로깅 시스템 상태 확인"
    
    echo "┌─────────────────────────────────────┬────────────┐"
    echo "│ 로깅 모듈                           │ 상태       │"
    echo "├─────────────────────────────────────┼────────────┤"
    
    for module in "${!LOGGING_MODULES[@]}"; do
        local status="${LOGGING_MODULES[$module]}"
        local module_name=""
        
        case "$module" in
            "bios_uefi") module_name="BIOS/UEFI 로그" ;;
            "bootloader") module_name="부트로더 로그" ;;
            "xen_hypervisor") module_name="Xen 하이퍼바이저 로그" ;;
            "dom0_kernel") module_name="Dom0 커널 로그" ;;
            "guest_domains") module_name="게스트 도메인 로그" ;;
            "system_services") module_name="시스템 서비스 로그" ;;
        esac
        
        case "$status" in
            "ACTIVE") 
                echo "│ $module_name" | awk '{printf "%-35s", $0}'
                echo " │ ${GREEN}활성${NC}      │"
                ;;
            "INACTIVE")
                echo "│ $module_name" | awk '{printf "%-35s", $0}'
                echo " │ ${YELLOW}비활성${NC}    │"
                ;;
        esac
    done
    
    echo "└─────────────────────────────────────┴────────────┘"
}

# 사용법 출력
show_usage() {
    echo "사용법: $0 [명령어] [옵션]"
    echo
    echo "명령어:"
    echo "  setup          전체 로깅 시스템 설정"
    echo "  collect        현재 로그 수집 실행"
    echo "  analyze        로그 분석 보고서 생성"
    echo "  monitor        실시간 로그 모니터링"
    echo "  status         로깅 시스템 상태 확인"
    echo "  install        systemd 서비스 설치"
    echo
    echo "옵션:"
    echo "  -h, --help     이 도움말 출력"
    echo
    echo "예시:"
    echo "  sudo $0 setup                    # 전체 시스템 설정"
    echo "  sudo $0 collect                  # 현재 상태 로그 수집"
    echo "  sudo $0 analyze                  # HTML 분석 보고서 생성"
    echo "  sudo $0 monitor                  # 실시간 로그 모니터링"
}

# 메인 함수
main() {
    local command="${1:-setup}"
    
    case "$command" in
        setup)
            init_logging_system
            setup_bios_uefi_logging
            setup_bootloader_logging
            setup_xen_hypervisor_logging
            setup_dom0_kernel_logging
            setup_guest_domain_logging
            setup_system_services_logging
            setup_log_analysis_tools
            setup_log_rotation
            check_logging_status
            log_info "Xen 부팅 로그 시스템 설정 완료!"
            ;;
        collect)
            collect_all_logs
            ;;
        analyze)
            if [[ -f "$LOG_BASE_DIR/analyze_boot_logs.sh" ]]; then
                "$LOG_BASE_DIR/analyze_boot_logs.sh"
            else
                log_error "분석 도구가 설치되지 않았습니다. 먼저 'setup'을 실행하세요."
            fi
            ;;
        monitor)
            if [[ -f "$LOG_BASE_DIR/monitor_realtime_logs.sh" ]]; then
                "$LOG_BASE_DIR/monitor_realtime_logs.sh"
            else
                log_error "모니터링 도구가 설치되지 않았습니다. 먼저 'setup'을 실행하세요."
            fi
            ;;
        status)
            check_logging_status
            ;;
        install)
            install_systemd_services
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