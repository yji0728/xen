#!/bin/bash

#####################################################################
# Xen 설치 시스템 통합 테스트 및 검증 도구 v1.0
# Ubuntu 22.04/24.04에서 전체 시스템 검증
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
TEST_LOG_DIR="/var/log/xen-testing"
TEST_RESULTS_DIR="/var/log/xen-testing/results"
BACKUP_DIR="/var/backups/xen-testing"
TEST_VERSION="1.0"

# 테스트 구성 요소 경로
INSTALLER_PATH="../xen_installer"
LOGGING_PATH="../xen_logging_system"

# 테스트 결과 추적
declare -A TEST_RESULTS=(
    ["environment_detection"]="PENDING"
    ["system_diagnostic"]="PENDING"
    ["installer_functionality"]="PENDING"
    ["logging_system"]="PENDING"
    ["integration_test"]="PENDING"
    ["performance_test"]="PENDING"
    ["recovery_test"]="PENDING"
    ["compatibility_test"]="PENDING"
)

# 로깅 함수
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${CYAN}[DEBUG]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# 결과 업데이트
update_test_result() {
    local test="$1"
    local result="$2"
    local details="${3:-}"
    
    TEST_RESULTS["$test"]="$result"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $test: $result - $details" >> "$TEST_LOG_DIR/test-execution.log"
    
    case "$result" in
        "PASS") echo -e "${GREEN}✅ PASS${NC} - $test" ;;
        "FAIL") echo -e "${RED}❌ FAIL${NC} - $test" ;;
        "WARN") echo -e "${YELLOW}⚠️ WARNING${NC} - $test" ;;
        "SKIP") echo -e "${CYAN}⏭️ SKIPPED${NC} - $test" ;;
    esac
}

# 초기화
init_testing_system() {
    log_section "Xen 테스팅 시스템 초기화"
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        exit 1
    fi
    
    # 디렉토리 구조 생성
    mkdir -p "$TEST_LOG_DIR" "$TEST_RESULTS_DIR" "$BACKUP_DIR"
    mkdir -p "$TEST_RESULTS_DIR"/{environment,installer,logging,integration,performance}
    
    # 테스트 실행 로그 초기화
    echo "=== Xen Testing System Started: $(date) ===" > "$TEST_LOG_DIR/test-execution.log"
    
    log_info "테스팅 시스템 초기화 완료"
    log_info "테스트 로그: $TEST_LOG_DIR"
    log_info "테스트 결과: $TEST_RESULTS_DIR"
}

# 환경 감지 및 검증
test_environment_detection() {
    log_section "환경 감지 및 검증 테스트"
    
    local test_log="$TEST_RESULTS_DIR/environment/environment-detection-$(date +%Y%m%d-%H%M%S).log"
    
    {
        echo "=== Environment Detection Test ==="
        echo "Start Time: $(date)"
        echo
        
        # Ubuntu 버전 감지
        echo "Ubuntu Version Detection:"
        local ubuntu_version=$(lsb_release -rs 2>/dev/null || echo "unknown")
        local ubuntu_codename=$(lsb_release -cs 2>/dev/null || echo "unknown")
        echo "Detected: Ubuntu $ubuntu_version ($ubuntu_codename)"
        
        if [[ "$ubuntu_version" =~ ^(22\.04|24\.04)$ ]]; then
            echo "✓ Supported Ubuntu version"
            local env_result="PASS"
        else
            echo "✗ Unsupported Ubuntu version"
            local env_result="FAIL"
        fi
        
        # 하드웨어 가상화 확인
        echo
        echo "Hardware Virtualization Detection:"
        if grep -q "vmx\|svm" /proc/cpuinfo; then
            echo "✓ Hardware virtualization supported"
            grep -o "vmx\|svm" /proc/cpuinfo | head -n1
        else
            echo "✗ Hardware virtualization not detected"
            env_result="FAIL"
        fi
        
        # 메모리 확인
        echo
        echo "Memory Detection:"
        local mem_gb=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
        echo "Total Memory: ${mem_gb}GB"
        if [[ $mem_gb -ge 4 ]]; then
            echo "✓ Sufficient memory"
        else
            echo "✗ Insufficient memory (minimum 4GB required)"
            env_result="FAIL"
        fi
        
        # 디스크 공간 확인
        echo
        echo "Disk Space Detection:"
        local disk_gb=$(df / | tail -n1 | awk '{printf "%.0f", $4/1024/1024}')
        echo "Available Space: ${disk_gb}GB"
        if [[ $disk_gb -ge 10 ]]; then
            echo "✓ Sufficient disk space"
        else
            echo "✗ Insufficient disk space (minimum 10GB required)"
            env_result="FAIL"
        fi
        
        # UEFI/BIOS 감지
        echo
        echo "Boot Mode Detection:"
        if [[ -d /sys/firmware/efi ]]; then
            echo "✓ UEFI boot mode detected"
            
            # Secure Boot 확인
            if command -v mokutil >/dev/null; then
                local sb_state=$(mokutil --sb-state 2>/dev/null || echo "unknown")
                echo "Secure Boot Status: $sb_state"
            fi
        else
            echo "✓ Legacy BIOS boot mode detected"
        fi
        
        echo
        echo "End Time: $(date)"
        echo "Overall Result: $env_result"
        
    } > "$test_log"
    
    update_test_result "environment_detection" "$env_result" "Environment compatibility verified"
    log_info "환경 감지 테스트 완료: $test_log"
}

# 시스템 진단 도구 테스트
test_system_diagnostic() {
    log_section "시스템 진단 도구 테스트"
    
    local test_log="$TEST_RESULTS_DIR/environment/system-diagnostic-$(date +%Y%m%d-%H%M%S).log"
    local diagnostic_script="$INSTALLER_PATH/system_diagnostic.sh"
    
    if [[ ! -f "$diagnostic_script" ]]; then
        update_test_result "system_diagnostic" "FAIL" "Diagnostic script not found"
        return 1
    fi
    
    {
        echo "=== System Diagnostic Tool Test ==="
        echo "Start Time: $(date)"
        echo "Script: $diagnostic_script"
        echo
        
        # 진단 스크립트 실행
        echo "Running system diagnostic..."
        if timeout 300 "$diagnostic_script" >> "$test_log" 2>&1; then
            local diag_result="PASS"
            echo "✓ System diagnostic completed successfully"
        else
            local diag_result="FAIL"
            echo "✗ System diagnostic failed or timed out"
        fi
        
        echo
        echo "End Time: $(date)"
        echo "Result: $diag_result"
        
    } >> "$test_log"
    
    update_test_result "system_diagnostic" "$diag_result" "System diagnostic tool verification"
    log_info "시스템 진단 테스트 완료: $test_log"
}

# 설치 시스템 기능 테스트
test_installer_functionality() {
    log_section "Xen 설치 시스템 기능 테스트"
    
    local test_log="$TEST_RESULTS_DIR/installer/installer-functionality-$(date +%Y%m%d-%H%M%S).log"
    local installer_script="$INSTALLER_PATH/xen_reliable_installer.sh"
    
    if [[ ! -f "$installer_script" ]]; then
        update_test_result "installer_functionality" "FAIL" "Installer script not found"
        return 1
    fi
    
    {
        echo "=== Installer Functionality Test ==="
        echo "Start Time: $(date)"
        echo "Script: $installer_script"
        echo
        
        # Dry-run 모드로 설치 테스트
        echo "Testing installer in dry-run mode..."
        if timeout 600 "$installer_script" --dry-run >> "$test_log" 2>&1; then
            echo "✓ Installer dry-run completed successfully"
            
            # 설치 구성 요소 확인
            echo
            echo "Checking installer components:"
            
            # 백업 디렉토리 확인
            if [[ -d /var/backups/xen-installer ]]; then
                echo "✓ Backup directory structure created"
            else
                echo "✗ Backup directory not created"
            fi
            
            # 로그 디렉토리 확인
            if [[ -d /var/log/xen-installer ]]; then
                echo "✓ Log directory structure created"
            else
                echo "✗ Log directory not created"
            fi
            
            local installer_result="PASS"
        else
            echo "✗ Installer dry-run failed or timed out"
            local installer_result="FAIL"
        fi
        
        echo
        echo "End Time: $(date)"
        echo "Result: $installer_result"
        
    } > "$test_log"
    
    update_test_result "installer_functionality" "$installer_result" "Installer dry-run verification"
    log_info "설치 시스템 테스트 완료: $test_log"
}

# 로깅 시스템 테스트
test_logging_system() {
    log_section "부팅 로깅 시스템 테스트"
    
    local test_log="$TEST_RESULTS_DIR/logging/logging-system-$(date +%Y%m%d-%H%M%S).log"
    local boot_logger="$LOGGING_PATH/xen_boot_logger.sh"
    local serial_logger="$LOGGING_PATH/serial_console_logger.sh"
    local guest_logger="$LOGGING_PATH/guest_domain_logger.sh"
    
    {
        echo "=== Logging System Test ==="
        echo "Start Time: $(date)"
        echo
        
        local logging_result="PASS"
        
        # 부팅 로거 테스트
        echo "Testing boot logger..."
        if [[ -f "$boot_logger" ]]; then
            echo "✓ Boot logger script found"
            
            # 상태 확인 명령 테스트
            if timeout 60 "$boot_logger" status >> "$test_log" 2>&1; then
                echo "✓ Boot logger status command works"
            else
                echo "✗ Boot logger status command failed"
                logging_result="WARN"
            fi
        else
            echo "✗ Boot logger script not found"
            logging_result="FAIL"
        fi
        
        # 직렬 콘솔 로거 테스트
        echo
        echo "Testing serial console logger..."
        if [[ -f "$serial_logger" ]]; then
            echo "✓ Serial console logger script found"
            
            # 테스트 명령 실행
            if timeout 60 "$serial_logger" test >> "$test_log" 2>&1; then
                echo "✓ Serial console logger test command works"
            else
                echo "✗ Serial console logger test command failed"
                logging_result="WARN"
            fi
        else
            echo "✗ Serial console logger script not found"
            logging_result="FAIL"
        fi
        
        # 게스트 도메인 로거 테스트
        echo
        echo "Testing guest domain logger..."
        if [[ -f "$guest_logger" ]]; then
            echo "✓ Guest domain logger script found"
            
            # 스캔 명령 테스트
            if timeout 60 "$guest_logger" scan >> "$test_log" 2>&1; then
                echo "✓ Guest domain logger scan command works"
            else
                echo "✗ Guest domain logger scan command failed"
                logging_result="WARN"
            fi
        else
            echo "✗ Guest domain logger script not found"
            logging_result="FAIL"
        fi
        
        echo
        echo "End Time: $(date)"
        echo "Result: $logging_result"
        
    } > "$test_log"
    
    update_test_result "logging_system" "$logging_result" "Logging system components verification"
    log_info "로깅 시스템 테스트 완료: $test_log"
}

# 통합 테스트
test_integration() {
    log_section "시스템 통합 테스트"
    
    local test_log="$TEST_RESULTS_DIR/integration/integration-test-$(date +%Y%m%d-%H%M%S).log"
    
    {
        echo "=== Integration Test ==="
        echo "Start Time: $(date)"
        echo
        
        local integration_result="PASS"
        
        # 설치 시스템과 로깅 시스템 연동 테스트
        echo "Testing installer and logging system integration..."
        
        # 설치 시스템에서 로깅 시스템 참조 확인
        local installer_script="$INSTALLER_PATH/xen_reliable_installer.sh"
        if [[ -f "$installer_script" ]]; then
            if grep -q "collect-xen-logs" "$installer_script"; then
                echo "✓ Installer integrates with logging system"
            else
                echo "✗ Installer does not integrate with logging system"
                integration_result="WARN"
            fi
        fi
        
        # 로그 디렉토리 구조 일관성 확인
        echo
        echo "Checking log directory structure consistency..."
        
        local expected_dirs=(
            "/var/log/xen-installer"
            "/var/log/xen-boot-logging"
            "/var/log/xen-serial-console"
            "/var/log/xen-guest-logging"
        )
        
        for dir in "${expected_dirs[@]}"; do
            if mkdir -p "$dir" 2>/dev/null; then
                echo "✓ Can create log directory: $dir"
            else
                echo "✗ Cannot create log directory: $dir"
                integration_result="WARN"
            fi
        done
        
        # 백업 시스템 일관성 확인
        echo
        echo "Checking backup system consistency..."
        
        local backup_dirs=(
            "/var/backups/xen-installer"
            "/var/backups/xen-serial-console"
        )
        
        for dir in "${backup_dirs[@]}"; do
            if mkdir -p "$dir" 2>/dev/null; then
                echo "✓ Can create backup directory: $dir"
            else
                echo "✗ Cannot create backup directory: $dir"
                integration_result="WARN"
            fi
        done
        
        # 권한 및 접근성 테스트
        echo
        echo "Testing permissions and accessibility..."
        
        # 스크립트 실행 권한 확인
        local scripts=(
            "$INSTALLER_PATH/xen_reliable_installer.sh"
            "$INSTALLER_PATH/system_diagnostic.sh"
            "$INSTALLER_PATH/post_installation_verification.sh"
            "$LOGGING_PATH/xen_boot_logger.sh"
            "$LOGGING_PATH/serial_console_logger.sh"
            "$LOGGING_PATH/guest_domain_logger.sh"
        )
        
        for script in "${scripts[@]}"; do
            if [[ -f "$script" ]]; then
                if [[ -r "$script" ]]; then
                    echo "✓ Script is readable: $(basename "$script")"
                else
                    echo "✗ Script is not readable: $(basename "$script")"
                    integration_result="WARN"
                fi
            else
                echo "✗ Script not found: $(basename "$script")"
                integration_result="FAIL"
            fi
        done
        
        echo
        echo "End Time: $(date)"
        echo "Result: $integration_result"
        
    } > "$test_log"
    
    update_test_result "integration_test" "$integration_result" "System integration verification"
    log_info "통합 테스트 완료: $test_log"
}

# 성능 테스트
test_performance() {
    log_section "성능 테스트"
    
    local test_log="$TEST_RESULTS_DIR/performance/performance-test-$(date +%Y%m%d-%H%M%S).log"
    
    {
        echo "=== Performance Test ==="
        echo "Start Time: $(date)"
        echo
        
        local perf_result="PASS"
        
        # 진단 스크립트 실행 시간 측정
        echo "Testing diagnostic script performance..."
        local diagnostic_script="$INSTALLER_PATH/system_diagnostic.sh"
        
        if [[ -f "$diagnostic_script" ]]; then
            local start_time=$(date +%s)
            timeout 300 "$diagnostic_script" >/dev/null 2>&1
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            
            echo "Diagnostic script execution time: ${duration}s"
            if [[ $duration -lt 120 ]]; then
                echo "✓ Diagnostic script performance acceptable"
            else
                echo "⚠ Diagnostic script took longer than expected"
                perf_result="WARN"
            fi
        fi
        
        # 로그 수집 성능 테스트
        echo
        echo "Testing log collection performance..."
        
        # 임시 로그 파일 생성
        local temp_log_dir="/tmp/xen-perf-test"
        mkdir -p "$temp_log_dir"
        
        # 1MB 테스트 로그 파일 생성
        dd if=/dev/zero of="$temp_log_dir/test.log" bs=1M count=1 2>/dev/null
        
        # 로그 처리 시간 측정
        local start_time=$(date +%s)
        grep -c "test" "$temp_log_dir/test.log" >/dev/null 2>&1 || true
        local end_time=$(date +%s)
        local log_duration=$((end_time - start_time))
        
        echo "Log processing time for 1MB: ${log_duration}s"
        
        # 정리
        rm -rf "$temp_log_dir"
        
        # 메모리 사용량 테스트
        echo
        echo "Testing memory usage..."
        local mem_usage=$(ps aux | awk '{sum+=$6} END {printf "%.0f", sum/1024}')
        echo "Current memory usage: ${mem_usage}MB"
        
        # 디스크 I/O 테스트
        echo
        echo "Testing disk I/O performance..."
        local start_time=$(date +%s)
        dd if=/dev/zero of="/tmp/xen-io-test" bs=1M count=10 2>/dev/null
        local end_time=$(date +%s)
        local io_duration=$((end_time - start_time))
        
        echo "Disk I/O time for 10MB: ${io_duration}s"
        rm -f "/tmp/xen-io-test"
        
        if [[ $io_duration -lt 5 ]]; then
            echo "✓ Disk I/O performance acceptable"
        else
            echo "⚠ Disk I/O performance slower than expected"
            perf_result="WARN"
        fi
        
        echo
        echo "End Time: $(date)"
        echo "Result: $perf_result"
        
    } > "$test_log"
    
    update_test_result "performance_test" "$perf_result" "System performance verification"
    log_info "성능 테스트 완료: $test_log"
}

# 복구 시스템 테스트
test_recovery_system() {
    log_section "복구 시스템 테스트"
    
    local test_log="$TEST_RESULTS_DIR/integration/recovery-test-$(date +%Y%m%d-%H%M%S).log"
    local recovery_script="$INSTALLER_PATH/utils/emergency_recovery.sh"
    
    {
        echo "=== Recovery System Test ==="
        echo "Start Time: $(date)"
        echo "Script: $recovery_script"
        echo
        
        local recovery_result="PASS"
        
        if [[ -f "$recovery_script" ]]; then
            echo "✓ Recovery script found"
            
            # 도움말 명령 테스트
            echo "Testing recovery script help command..."
            if timeout 30 "$recovery_script" --help >> "$test_log" 2>&1; then
                echo "✓ Recovery script help command works"
            else
                echo "✗ Recovery script help command failed"
                recovery_result="WARN"
            fi
            
            # 백업 디렉토리 확인
            echo
            echo "Checking backup capabilities..."
            local backup_dir="/var/backups/xen-installer"
            if mkdir -p "$backup_dir" 2>/dev/null; then
                echo "✓ Backup directory accessible"
                
                # 테스트 백업 파일 생성
                echo "test backup" > "$backup_dir/test-backup.txt"
                if [[ -f "$backup_dir/test-backup.txt" ]]; then
                    echo "✓ Can create backup files"
                    rm -f "$backup_dir/test-backup.txt"
                else
                    echo "✗ Cannot create backup files"
                    recovery_result="WARN"
                fi
            else
                echo "✗ Backup directory not accessible"
                recovery_result="FAIL"
            fi
        else
            echo "✗ Recovery script not found"
            recovery_result="FAIL"
        fi
        
        echo
        echo "End Time: $(date)"
        echo "Result: $recovery_result"
        
    } > "$test_log"
    
    update_test_result "recovery_test" "$recovery_result" "Recovery system verification"
    log_info "복구 시스템 테스트 완료: $test_log"
}

# 호환성 테스트
test_compatibility() {
    log_section "호환성 테스트"
    
    local test_log="$TEST_RESULTS_DIR/environment/compatibility-test-$(date +%Y%m%d-%H%M%S).log"
    
    {
        echo "=== Compatibility Test ==="
        echo "Start Time: $(date)"
        echo
        
        local compat_result="PASS"
        
        # Ubuntu 버전 호환성
        echo "Testing Ubuntu version compatibility..."
        local ubuntu_version=$(lsb_release -rs 2>/dev/null || echo "unknown")
        
        case "$ubuntu_version" in
            "22.04")
                echo "✓ Ubuntu 22.04 LTS - Fully supported"
                echo "  - zstd compression support available"
                echo "  - Xen 4.16+ recommended"
                ;;
            "24.04")
                echo "✓ Ubuntu 24.04 LTS - Fully supported"
                echo "  - Known driver compatibility issues handled"
                echo "  - Xen 4.17+ recommended"
                ;;
            *)
                echo "✗ Ubuntu $ubuntu_version - Not officially supported"
                compat_result="WARN"
                ;;
        esac
        
        # 커널 호환성
        echo
        echo "Testing kernel compatibility..."
        local kernel_version=$(uname -r)
        echo "Current kernel: $kernel_version"
        
        if [[ "$ubuntu_version" == "22.04" ]]; then
            if [[ "$kernel_version" =~ ^5\.15 ]]; then
                echo "✓ Kernel version compatible with Ubuntu 22.04"
            else
                echo "⚠ Unexpected kernel version for Ubuntu 22.04"
                compat_result="WARN"
            fi
        elif [[ "$ubuntu_version" == "24.04" ]]; then
            if [[ "$kernel_version" =~ ^6\.[0-9] ]]; then
                echo "✓ Kernel version compatible with Ubuntu 24.04"
            else
                echo "⚠ Unexpected kernel version for Ubuntu 24.04"
                compat_result="WARN"
            fi
        fi
        
        # 하드웨어 호환성
        echo
        echo "Testing hardware compatibility..."
        
        # CPU 기능 확인
        local cpu_features=$(grep "^flags" /proc/cpuinfo | head -n1)
        
        if echo "$cpu_features" | grep -q "vmx"; then
            echo "✓ Intel VT-x supported"
        elif echo "$cpu_features" | grep -q "svm"; then
            echo "✓ AMD-V supported"
        else
            echo "✗ Hardware virtualization not supported"
            compat_result="FAIL"
        fi
        
        if echo "$cpu_features" | grep -q "ept"; then
            echo "✓ Intel EPT supported"
        elif echo "$cpu_features" | grep -q "npt"; then
            echo "✓ AMD NPT supported"
        else
            echo "⚠ Hardware assisted paging not detected"
            compat_result="WARN"
        fi
        
        # 드라이버 호환성 확인
        echo
        echo "Testing driver compatibility..."
        
        # MegaRAID 확인 (Ubuntu 24.04 이슈)
        if lspci | grep -qi "megaraid"; then
            echo "⚠ MegaRAID controller detected"
            if [[ "$ubuntu_version" == "24.04" ]]; then
                echo "  - Known compatibility issue in Ubuntu 24.04"
                echo "  - Automatic IOMMU configuration will be applied"
            fi
        fi
        
        # AMD 그래픽 확인 (Ubuntu 24.04 이슈)
        if lspci | grep -i "amd.*vga\|radeon"; then
            echo "⚠ AMD graphics detected"
            if [[ "$ubuntu_version" == "24.04" ]]; then
                echo "  - Known compatibility issue in Ubuntu 24.04"
                echo "  - nomodeset option will be applied"
            fi
        fi
        
        # 패키지 관리자 호환성
        echo
        echo "Testing package manager compatibility..."
        
        if command -v apt >/dev/null; then
            echo "✓ APT package manager available"
        else
            echo "✗ APT package manager not found"
            compat_result="FAIL"
        fi
        
        if command -v systemctl >/dev/null; then
            echo "✓ systemd service manager available"
        else
            echo "✗ systemd service manager not found"
            compat_result="FAIL"
        fi
        
        echo
        echo "End Time: $(date)"
        echo "Result: $compat_result"
        
    } > "$test_log"
    
    update_test_result "compatibility_test" "$compat_result" "Platform compatibility verification"
    log_info "호환성 테스트 완료: $test_log"
}

# 테스트 결과 요약
generate_test_summary() {
    log_section "테스트 결과 요약 생성"
    
    local summary_file="$TEST_RESULTS_DIR/test-summary-$(date +%Y%m%d-%H%M%S).html"
    
    cat > "$summary_file" << 'HTML_START'
<!DOCTYPE html>
<html>
<head>
    <title>Xen Installation System Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .pass { color: green; font-weight: bold; }
        .fail { color: red; font-weight: bold; }
        .warn { color: orange; font-weight: bold; }
        .skip { color: blue; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        pre { background: #f5f5f5; padding: 10px; overflow-x: auto; }
        .summary-stats { display: flex; justify-content: space-around; margin: 20px 0; }
        .stat-box { text-align: center; padding: 15px; border: 2px solid #ddd; border-radius: 5px; }
    </style>
</head>
<body>
HTML_START

    echo "<div class='header'>" >> "$summary_file"
    echo "<h1>Xen Installation System Test Report</h1>" >> "$summary_file"
    echo "<p><strong>Generated:</strong> $(date)</p>" >> "$summary_file"
    echo "<p><strong>Test Version:</strong> $TEST_VERSION</p>" >> "$summary_file"
    echo "<p><strong>Ubuntu Version:</strong> $(lsb_release -ds 2>/dev/null || echo 'Unknown')</p>" >> "$summary_file"
    echo "<p><strong>Kernel Version:</strong> $(uname -r)</p>" >> "$summary_file"
    echo "</div>" >> "$summary_file"
    
    # 테스트 통계
    local pass_count=0
    local fail_count=0
    local warn_count=0
    local skip_count=0
    
    for test in "${!TEST_RESULTS[@]}"; do
        case "${TEST_RESULTS[$test]}" in
            "PASS") ((pass_count++)) ;;
            "FAIL") ((fail_count++)) ;;
            "WARN") ((warn_count++)) ;;
            "SKIP") ((skip_count++)) ;;
        esac
    done
    
    echo "<div class='summary-stats'>" >> "$summary_file"
    echo "<div class='stat-box' style='border-color: green;'><h3>$pass_count</h3><p>PASSED</p></div>" >> "$summary_file"
    echo "<div class='stat-box' style='border-color: red;'><h3>$fail_count</h3><p>FAILED</p></div>" >> "$summary_file"
    echo "<div class='stat-box' style='border-color: orange;'><h3>$warn_count</h3><p>WARNINGS</p></div>" >> "$summary_file"
    echo "<div class='stat-box' style='border-color: blue;'><h3>$skip_count</h3><p>SKIPPED</p></div>" >> "$summary_file"
    echo "</div>" >> "$summary_file"
    
    # 테스트 결과 테이블
    echo "<div class='section'>" >> "$summary_file"
    echo "<h2>Test Results</h2>" >> "$summary_file"
    echo "<table>" >> "$summary_file"
    echo "<tr><th>Test Category</th><th>Result</th><th>Description</th></tr>" >> "$summary_file"
    
    declare -A test_descriptions=(
        ["environment_detection"]="Environment Detection and Validation"
        ["system_diagnostic"]="System Diagnostic Tool Test"
        ["installer_functionality"]="Xen Installer Functionality Test"
        ["logging_system"]="Boot Logging System Test"
        ["integration_test"]="System Integration Test"
        ["performance_test"]="Performance Test"
        ["recovery_test"]="Recovery System Test"
        ["compatibility_test"]="Platform Compatibility Test"
    )
    
    for test in "${!TEST_RESULTS[@]}"; do
        local result="${TEST_RESULTS[$test]}"
        local description="${test_descriptions[$test]:-$test}"
        local css_class=""
        
        case "$result" in
            "PASS") css_class="pass" ;;
            "FAIL") css_class="fail" ;;
            "WARN") css_class="warn" ;;
            "SKIP") css_class="skip" ;;
        esac
        
        echo "<tr><td>$description</td><td class='$css_class'>$result</td><td>Automated test execution</td></tr>" >> "$summary_file"
    done
    
    echo "</table>" >> "$summary_file"
    echo "</div>" >> "$summary_file"
    
    # 시스템 정보
    echo "<div class='section'>" >> "$summary_file"
    echo "<h2>System Information</h2>" >> "$summary_file"
    echo "<pre>" >> "$summary_file"
    {
        echo "Hardware Information:"
        lscpu | head -n10
        echo
        echo "Memory Information:"
        free -h
        echo
        echo "Disk Information:"
        df -h / /var /tmp 2>/dev/null | head -n4
        echo
        echo "Network Interfaces:"
        ip addr show | grep -E "^[0-9]+:|inet " | head -n10
    } >> "$summary_file"
    echo "</pre>" >> "$summary_file"
    echo "</div>" >> "$summary_file"
    
    # 권장사항
    echo "<div class='section'>" >> "$summary_file"
    echo "<h2>Recommendations</h2>" >> "$summary_file"
    
    if [[ $fail_count -gt 0 ]]; then
        echo "<p class='fail'>⚠️ Critical issues found. Please resolve failed tests before proceeding with Xen installation.</p>" >> "$summary_file"
    elif [[ $warn_count -gt 0 ]]; then
        echo "<p class='warn'>⚠️ Some warnings detected. Review test logs and consider addressing issues before installation.</p>" >> "$summary_file"
    else
        echo "<p class='pass'>✅ All tests passed! System is ready for Xen installation.</p>" >> "$summary_file"
    fi
    
    echo "<h3>Next Steps:</h3>" >> "$summary_file"
    echo "<ol>" >> "$summary_file"
    echo "<li>Review individual test logs in <code>$TEST_RESULTS_DIR</code></li>" >> "$summary_file"
    echo "<li>Address any failed or warning conditions</li>" >> "$summary_file"
    echo "<li>Run the Xen installer with: <code>sudo $INSTALLER_PATH/xen_reliable_installer.sh</code></li>" >> "$summary_file"
    echo "<li>Setup logging system with: <code>sudo $LOGGING_PATH/xen_boot_logger.sh setup</code></li>" >> "$summary_file"
    echo "</ol>" >> "$summary_file"
    echo "</div>" >> "$summary_file"
    
    echo "</body></html>" >> "$summary_file"
    
    log_info "테스트 요약 보고서 생성: $summary_file"
    echo
    echo -e "${BLUE}=== 테스트 완료 요약 ===${NC}"
    echo "✅ 통과: $pass_count개"
    echo "❌ 실패: $fail_count개"  
    echo "⚠️ 경고: $warn_count개"
    echo "⏭️ 스킵: $skip_count개"
    echo
    echo "📄 상세 보고서: $summary_file"
}

# 전체 테스트 실행
run_all_tests() {
    log_section "전체 테스트 실행"
    
    local start_time=$(date +%s)
    
    # 테스트 실행 순서
    test_environment_detection
    test_system_diagnostic
    test_installer_functionality
    test_logging_system
    test_integration
    test_performance
    test_recovery_system
    test_compatibility
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))
    
    log_info "전체 테스트 완료 시간: ${duration_min}분 ${duration_sec}초"
    
    # 요약 보고서 생성
    generate_test_summary
}

# 사용법 출력
show_usage() {
    echo "사용법: $0 [명령어] [옵션]"
    echo
    echo "명령어:"
    echo "  test-all           전체 테스트 실행"
    echo "  test-env           환경 감지 테스트만 실행"
    echo "  test-installer     설치 시스템 테스트만 실행"
    echo "  test-logging       로깅 시스템 테스트만 실행"
    echo "  test-integration   통합 테스트만 실행"
    echo "  test-performance   성능 테스트만 실행"
    echo "  test-recovery      복구 시스템 테스트만 실행"
    echo "  test-compatibility 호환성 테스트만 실행"
    echo "  summary            기존 테스트 결과 요약 생성"
    echo
    echo "옵션:"
    echo "  -h, --help         이 도움말 출력"
    echo
    echo "예시:"
    echo "  sudo $0 test-all                 # 전체 테스트 실행"
    echo "  sudo $0 test-env                 # 환경 테스트만 실행"
    echo "  sudo $0 summary                  # 요약 보고서 생성"
}

# 메인 함수
main() {
    local command="${1:-test-all}"
    
    case "$command" in
        test-all)
            init_testing_system
            run_all_tests
            ;;
        test-env)
            init_testing_system
            test_environment_detection
            ;;
        test-installer)
            init_testing_system
            test_installer_functionality
            ;;
        test-logging)
            init_testing_system
            test_logging_system
            ;;
        test-integration)
            init_testing_system
            test_integration
            ;;
        test-performance)
            init_testing_system
            test_performance
            ;;
        test-recovery)
            init_testing_system
            test_recovery_system
            ;;
        test-compatibility)
            init_testing_system
            test_compatibility
            ;;
        summary)
            generate_test_summary
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