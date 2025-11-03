#!/bin/bash

#####################################################################
# Xen 설치 후 검증 도구 v1.0
# Xen 하이퍼바이저 설치 상태 및 기능 검증
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

# 검증 결과 저장
declare -A VERIFICATIONS=(
    ["xen_packages"]="PENDING"
    ["xen_hypervisor"]="PENDING"
    ["grub_configuration"]="PENDING"
    ["xen_tools"]="PENDING"
    ["dom0_status"]="PENDING"
    ["virtualization_features"]="PENDING"
    ["networking"]="PENDING"
    ["logging_system"]="PENDING"
    ["performance"]="PENDING"
)

# 로깅 함수
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# 결과 업데이트
update_result() {
    local test="$1"
    local result="$2"
    VERIFICATIONS["$test"]="$result"
    
    case "$result" in
        "PASS") echo -e "${GREEN}✅ PASS${NC}" ;;
        "WARN") echo -e "${YELLOW}⚠️ WARNING${NC}" ;;
        "FAIL") echo -e "${RED}❌ FAIL${NC}" ;;
    esac
}

# Xen 패키지 설치 확인
check_xen_packages() {
    log_section "Xen 패키지 설치 확인"
    
    local required_packages=(
        "xen-hypervisor"
        "xen-utils"
        "xen-tools"
    )
    
    local missing_packages=()
    local installed_packages=()
    
    for package in "${required_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$package"; then
            local version=$(dpkg -l | grep "^ii.*$package" | awk '{print $3}' | head -n1)
            echo "✓ $package: $version"
            installed_packages+=("$package")
        else
            echo "✗ $package: 설치되지 않음"
            missing_packages+=("$package")
        fi
    done
    
    # 선택적 패키지 확인
    local optional_packages=("xenstore-utils" "xen-docs")
    for package in "${optional_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$package"; then
            local version=$(dpkg -l | grep "^ii.*$package" | awk '{print $3}' | head -n1)
            echo "✓ $package: $version (선택적)"
        fi
    done
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log_error "누락된 패키지: ${missing_packages[*]}"
        update_result "xen_packages" "FAIL"
        return 1
    else
        log_info "모든 필수 Xen 패키지가 설치되어 있습니다."
        update_result "xen_packages" "PASS"
        return 0
    fi
}

# Xen 하이퍼바이저 상태 확인
check_xen_hypervisor() {
    log_section "Xen 하이퍼바이저 상태 확인"
    
    # Xen 바이너리 파일 확인
    local xen_binary=""
    if [[ -f /boot/xen.gz ]]; then
        xen_binary="/boot/xen.gz"
    elif ls /boot/xen-*.gz >/dev/null 2>&1; then
        xen_binary=$(ls -t /boot/xen-*.gz | head -n1)
    else
        log_error "Xen 하이퍼바이저 바이너리를 찾을 수 없습니다."
        update_result "xen_hypervisor" "FAIL"
        return 1
    fi
    
    echo "Xen 하이퍼바이저 바이너리: $xen_binary"
    
    # 현재 Xen에서 부팅되었는지 확인
    if [[ -f /sys/hypervisor/type ]] && grep -q "xen" /sys/hypervisor/type; then
        log_info "현재 Xen 하이퍼바이저에서 부팅되었습니다."
        
        # Xen 버전 확인
        if [[ -f /sys/hypervisor/version/major ]] && [[ -f /sys/hypervisor/version/minor ]]; then
            local xen_major=$(cat /sys/hypervisor/version/major)
            local xen_minor=$(cat /sys/hypervisor/version/minor)
            echo "Xen 버전: ${xen_major}.${xen_minor}"
        fi
        
        # Xen capabilities 확인
        if [[ -f /sys/hypervisor/properties/capabilities ]]; then
            echo "Xen 기능:"
            cat /sys/hypervisor/properties/capabilities
        fi
        
        update_result "xen_hypervisor" "PASS"
        return 0
    else
        log_warn "현재 Xen 하이퍼바이저에서 부팅되지 않았습니다."
        log_warn "시스템을 재부팅하고 GRUB에서 Xen 항목을 선택하세요."
        update_result "xen_hypervisor" "WARN"
        return 0
    fi
}

# GRUB 구성 확인
check_grub_configuration() {
    log_section "GRUB 구성 확인"
    
    # GRUB 설정 파일 확인
    if [[ ! -f /boot/grub/grub.cfg ]]; then
        log_error "GRUB 설정 파일을 찾을 수 없습니다."
        update_result "grub_configuration" "FAIL"
        return 1
    fi
    
    # Xen 부팅 항목 확인
    local xen_entries=$(grep -c "menuentry.*Xen" /boot/grub/grub.cfg || echo "0")
    echo "Xen 부팅 항목 수: $xen_entries"
    
    if [[ $xen_entries -eq 0 ]]; then
        log_error "GRUB에 Xen 부팅 항목이 없습니다."
        update_result "grub_configuration" "FAIL"
        return 1
    fi
    
    # Xen 부팅 옵션 확인
    echo "Xen 부팅 옵션:"
    grep -A5 -B1 "menuentry.*Xen" /boot/grub/grub.cfg | head -n20
    
    # Dom0 메모리 설정 확인
    if grep -q "dom0_mem" /boot/grub/grub.cfg; then
        local dom0_mem=$(grep "dom0_mem" /boot/grub/grub.cfg | grep -o "dom0_mem=[^[:space:]]*" | head -n1)
        echo "Dom0 메모리 설정: $dom0_mem"
    else
        log_warn "Dom0 메모리 제한이 설정되지 않았습니다."
    fi
    
    # 로깅 설정 확인
    if grep -q "loglvl\|guest_loglvl" /boot/grub/grub.cfg; then
        echo "Xen 로깅 설정이 활성화되어 있습니다."
    else
        log_warn "Xen 로깅 설정이 없습니다."
    fi
    
    update_result "grub_configuration" "PASS"
    return 0
}

# Xen 도구 기능 확인
check_xen_tools() {
    log_section "Xen 도구 기능 확인"
    
    # xl 명령어 확인
    if command -v xl >/dev/null; then
        echo "xl 도구: 사용 가능"
        
        # Xen에서 부팅된 경우에만 xl 명령어 테스트
        if [[ -f /sys/hypervisor/type ]] && grep -q "xen" /sys/hypervisor/type; then
            # xl info 실행
            echo "xl info 출력:"
            if xl info >/dev/null 2>&1; then
                xl info | head -n15
            else
                log_warn "xl info 명령어 실행에 실패했습니다."
            fi
            
            # 도메인 목록 확인
            echo -e "\n현재 도메인 목록:"
            if xl list >/dev/null 2>&1; then
                xl list
            else
                log_warn "xl list 명령어 실행에 실패했습니다."
            fi
        else
            log_warn "Xen에서 부팅하지 않아 xl 명령어를 테스트할 수 없습니다."
        fi
    else
        log_error "xl 도구를 찾을 수 없습니다."
        update_result "xen_tools" "FAIL"
        return 1
    fi
    
    # xen-create-image 확인
    if command -v xen-create-image >/dev/null; then
        echo "xen-create-image: 사용 가능"
    else
        log_warn "xen-create-image를 찾을 수 없습니다."
    fi
    
    # xenstore 도구 확인
    if command -v xenstore-ls >/dev/null; then
        echo "xenstore 도구: 사용 가능"
        
        # Xen에서 부팅된 경우에만 xenstore 테스트
        if [[ -f /sys/hypervisor/type ]] && grep -q "xen" /sys/hypervisor/type; then
            if xenstore-ls / >/dev/null 2>&1; then
                echo "XenStore 연결: 정상"
            else
                log_warn "XenStore에 연결할 수 없습니다."
            fi
        fi
    else
        log_warn "xenstore 도구를 찾을 수 없습니다."
    fi
    
    update_result "xen_tools" "PASS"
    return 0
}

# Dom0 상태 확인
check_dom0_status() {
    log_section "Dom0 상태 확인"
    
    # Xen에서 부팅되지 않은 경우 스킵
    if [[ ! -f /sys/hypervisor/type ]] || ! grep -q "xen" /sys/hypervisor/type; then
        log_warn "Xen에서 부팅하지 않아 Dom0 상태를 확인할 수 없습니다."
        update_result "dom0_status" "WARN"
        return 0
    fi
    
    # Dom0 메모리 사용량 확인
    local total_mem=$(xl info | grep "total_memory" | awk '{print $3}')
    local free_mem=$(xl info | grep "free_memory" | awk '{print $3}')
    
    if [[ -n "$total_mem" ]] && [[ -n "$free_mem" ]]; then
        echo "총 메모리: ${total_mem}MB"
        echo "여유 메모리: ${free_mem}MB"
        echo "사용 메모리: $((total_mem - free_mem))MB"
    fi
    
    # Dom0 CPU 할당 확인
    local dom0_vcpus=$(xl list | grep "Domain-0" | awk '{print $4}')
    echo "Dom0 vCPU 수: $dom0_vcpus"
    
    # Dom0 상태 확인
    local dom0_state=$(xl list | grep "Domain-0" | awk '{print $5}')
    echo "Dom0 상태: $dom0_state"
    
    if [[ "$dom0_state" == "r-----" ]]; then
        log_info "Dom0가 정상적으로 실행 중입니다."
    else
        log_warn "Dom0 상태가 비정상입니다: $dom0_state"
    fi
    
    # Xen 서비스 상태 확인
    local xen_services=("xenconsoled" "xen-qemu-dom0-disk-backend")
    for service in "${xen_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "✓ $service: 실행 중"
        else
            echo "✗ $service: 실행되지 않음"
        fi
    done
    
    update_result "dom0_status" "PASS"
    return 0
}

# 가상화 기능 확인
check_virtualization_features() {
    log_section "가상화 기능 확인"
    
    # Xen에서 부팅되지 않은 경우 하드웨어 기능만 확인
    if [[ ! -f /sys/hypervisor/type ]] || ! grep -q "xen" /sys/hypervisor/type; then
        log_warn "Xen에서 부팅하지 않아 전체 가상화 기능을 확인할 수 없습니다."
        
        # 하드웨어 가상화 지원 확인
        if grep -q "vmx\|svm" /proc/cpuinfo; then
            echo "✓ 하드웨어 가상화 지원됨"
        else
            log_error "하드웨어 가상화가 지원되지 않습니다."
            update_result "virtualization_features" "FAIL"
            return 1
        fi
        
        update_result "virtualization_features" "WARN"
        return 0
    fi
    
    # HVM 지원 확인
    if xl info | grep -q "hvm.*1"; then
        echo "✓ HVM (Hardware Virtual Machine) 지원됨"
    else
        log_warn "HVM 지원이 활성화되지 않았습니다."
    fi
    
    # HAP (Hardware Assisted Paging) 확인
    if xl info | grep -q "hap.*1"; then
        echo "✓ HAP (Hardware Assisted Paging) 지원됨"
    else
        log_warn "HAP 지원이 활성화되지 않았습니다."
    fi
    
    # IOMMU 확인
    if xl info | grep -q "iommu.*enabled"; then
        echo "✓ IOMMU 활성화됨"
    else
        log_warn "IOMMU가 비활성화되어 있습니다."
    fi
    
    # 가상화 모드 확인
    echo "지원하는 가상화 모드:"
    xl info | grep -E "xen_caps|xen_commandline" | head -n5
    
    update_result "virtualization_features" "PASS"
    return 0
}

# 네트워킹 확인
check_networking() {
    log_section "네트워킹 확인"
    
    # 브릿지 인터페이스 확인
    if command -v brctl >/dev/null; then
        echo "브릿지 인터페이스:"
        if brctl show 2>/dev/null | grep -q bridge; then
            brctl show
        else
            log_warn "설정된 브릿지 인터페이스가 없습니다."
        fi
    else
        log_warn "bridge-utils가 설치되어 있지 않습니다."
    fi
    
    # Xen 네트워크 설정 확인
    if [[ -f /etc/xen/xl.conf ]]; then
        echo "Xen 네트워크 설정:"
        grep -E "vif\.|bridge" /etc/xen/xl.conf | head -n5
    else
        log_warn "/etc/xen/xl.conf 파일이 없습니다."
    fi
    
    # NetworkManager 설정 확인
    if [[ -f /etc/NetworkManager/conf.d/99-unmanage-bridge.conf ]]; then
        echo "✓ NetworkManager 브릿지 설정이 구성되어 있습니다."
    else
        log_warn "NetworkManager 브릿지 설정이 없습니다."
    fi
    
    # 기본 네트워크 연결 확인
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo "✓ 인터넷 연결 정상"
    else
        log_warn "인터넷 연결에 문제가 있을 수 있습니다."
    fi
    
    update_result "networking" "PASS"
    return 0
}

# 로깅 시스템 확인
check_logging_system() {
    log_section "로깅 시스템 확인"
    
    # Xen 로그 디렉토리 확인
    if [[ -d /var/log/xen ]]; then
        echo "✓ Xen 로그 디렉토리 존재: /var/log/xen"
        local log_count=$(find /var/log/xen -name "*.log" | wc -l)
        echo "로그 파일 수: $log_count"
    else
        log_warn "Xen 로그 디렉토리가 없습니다."
    fi
    
    # 로그 수집 스크립트 확인
    if [[ -f /usr/local/bin/collect-xen-logs.sh ]]; then
        echo "✓ Xen 로그 수집 스크립트 설치됨"
        if [[ -x /usr/local/bin/collect-xen-logs.sh ]]; then
            echo "✓ 실행 권한 있음"
        else
            log_warn "로그 수집 스크립트에 실행 권한이 없습니다."
        fi
    else
        log_warn "Xen 로그 수집 스크립트가 설치되지 않았습니다."
    fi
    
    # Xen에서 부팅된 경우 실제 로그 확인
    if [[ -f /sys/hypervisor/type ]] && grep -q "xen" /sys/hypervisor/type; then
        echo "Xen 하이퍼바이저 로그 (최근 10줄):"
        if xl dmesg 2>/dev/null | tail -n10; then
            echo "✓ Xen 로그 수집 가능"
        else
            log_warn "Xen 로그를 수집할 수 없습니다."
        fi
    else
        log_warn "Xen에서 부팅하지 않아 로그를 확인할 수 없습니다."
    fi
    
    # 직렬 콘솔 설정 확인
    if grep -q "console=ttyS0" /proc/cmdline 2>/dev/null; then
        echo "✓ 직렬 콘솔 로깅 활성화됨"
    else
        log_warn "직렬 콘솔 로깅이 설정되지 않았습니다."
    fi
    
    update_result "logging_system" "PASS"
    return 0
}

# 성능 확인
check_performance() {
    log_section "성능 확인"
    
    # Xen에서 부팅되지 않은 경우 스킵
    if [[ ! -f /sys/hypervisor/type ]] || ! grep -q "xen" /sys/hypervisor/type; then
        log_warn "Xen에서 부팅하지 않아 성능을 확인할 수 없습니다."
        update_result "performance" "WARN"
        return 0
    fi
    
    # CPU 정보
    local host_cpu_count=$(xl info | grep "nr_cpus" | awk '{print $3}')
    local dom0_vcpu_count=$(xl list | grep "Domain-0" | awk '{print $4}')
    echo "물리 CPU 수: $host_cpu_count"
    echo "Dom0 할당 vCPU 수: $dom0_vcpu_count"
    
    # 메모리 정보
    local total_memory=$(xl info | grep "total_memory" | awk '{print $3}')
    local dom0_memory=$(xl list | grep "Domain-0" | awk '{print $3}')
    echo "총 메모리: ${total_memory}MB"
    echo "Dom0 할당 메모리: ${dom0_memory}MB"
    
    # 메모리 사용률 계산
    if [[ -n "$total_memory" ]] && [[ -n "$dom0_memory" ]]; then
        local dom0_memory_percent=$((dom0_memory * 100 / total_memory))
        echo "Dom0 메모리 사용률: ${dom0_memory_percent}%"
        
        if [[ $dom0_memory_percent -gt 80 ]]; then
            log_warn "Dom0 메모리 할당이 과도합니다 (${dom0_memory_percent}%)"
        elif [[ $dom0_memory_percent -lt 10 ]]; then
            log_warn "Dom0 메모리 할당이 부족할 수 있습니다 (${dom0_memory_percent}%)"
        fi
    fi
    
    # 간단한 성능 테스트
    echo "CPU 성능 테스트 (1초간):"
    local cpu_test_start=$(date +%s%N)
    dd if=/dev/zero of=/dev/null bs=1M count=100 2>/dev/null
    local cpu_test_end=$(date +%s%N)
    local cpu_test_duration=$(((cpu_test_end - cpu_test_start) / 1000000))
    echo "CPU 테스트 시간: ${cpu_test_duration}ms"
    
    update_result "performance" "PASS"
    return 0
}

# 종합 결과 출력
show_summary() {
    log_section "검증 결과 요약"
    
    local pass_count=0
    local warn_count=0
    local fail_count=0
    
    echo "┌─────────────────────────────────────┬────────────┐"
    echo "│ 검증 항목                           │ 결과       │"
    echo "├─────────────────────────────────────┼────────────┤"
    
    for test in "${!VERIFICATIONS[@]}"; do
        local result="${VERIFICATIONS[$test]}"
        local test_name=""
        
        case "$test" in
            "xen_packages") test_name="Xen 패키지 설치" ;;
            "xen_hypervisor") test_name="Xen 하이퍼바이저 상태" ;;
            "grub_configuration") test_name="GRUB 구성" ;;
            "xen_tools") test_name="Xen 도구" ;;
            "dom0_status") test_name="Dom0 상태" ;;
            "virtualization_features") test_name="가상화 기능" ;;
            "networking") test_name="네트워킹" ;;
            "logging_system") test_name="로깅 시스템" ;;
            "performance") test_name="성능" ;;
        esac
        
        case "$result" in
            "PASS") 
                echo "│ $test_name" | awk '{printf "%-35s", $0}'
                echo " │ ${GREEN}✅ PASS${NC}    │"
                ((pass_count++))
                ;;
            "WARN")
                echo "│ $test_name" | awk '{printf "%-35s", $0}'
                echo " │ ${YELLOW}⚠️ WARNING${NC} │"
                ((warn_count++))
                ;;
            "FAIL")
                echo "│ $test_name" | awk '{printf "%-35s", $0}'
                echo " │ ${RED}❌ FAIL${NC}    │"
                ((fail_count++))
                ;;
        esac
    done
    
    echo "└─────────────────────────────────────┴────────────┘"
    echo
    echo "결과 통계:"
    echo "  - 통과: ${pass_count}개"
    echo "  - 경고: ${warn_count}개"
    echo "  - 실패: ${fail_count}개"
    echo
    
    # 권장 사항
    if [[ $fail_count -gt 0 ]]; then
        echo -e "${RED}⚠️ 실패한 항목들을 확인하고 문제를 해결하세요.${NC}"
        return 1
    elif [[ $warn_count -gt 0 ]]; then
        echo -e "${YELLOW}⚠️ 경고 항목들을 검토하세요.${NC}"
        
        # Xen에서 부팅하지 않은 경우 특별 안내
        if [[ "${VERIFICATIONS[xen_hypervisor]}" == "WARN" ]]; then
            echo
            echo -e "${CYAN}다음 단계:${NC}"
            echo -e "  1. 시스템을 재부팅하세요: ${CYAN}sudo reboot${NC}"
            echo -e "  2. GRUB 메뉴에서 Xen 항목을 선택하세요"
            echo -e "  3. 재부팅 후 이 스크립트를 다시 실행하세요"
        fi
        
        return 0
    else
        echo -e "${GREEN}✅ 모든 검증을 통과했습니다! Xen이 정상적으로 설치되고 작동합니다.${NC}"
        return 0
    fi
}

# 추가 정보 출력
show_additional_info() {
    log_section "추가 정보"
    
    echo -e "${CYAN}Xen 관리 명령어:${NC}"
    echo "  - xl info                    # Xen 시스템 정보"
    echo "  - xl list                    # 도메인 목록"
    echo "  - xl dmesg                   # Xen 로그"
    echo "  - xl top                     # 도메인 리소스 모니터링"
    echo "  - xl vcpu-list               # vCPU 할당 상태"
    echo
    echo -e "${CYAN}로그 수집:${NC}"
    echo "  - /usr/local/bin/collect-xen-logs.sh  # 모든 Xen 로그 수집"
    echo "  - journalctl -u xen*                  # Xen 서비스 로그"
    echo
    echo -e "${CYAN}설정 파일:${NC}"
    echo "  - /etc/xen/xl.conf           # Xen 기본 설정"
    echo "  - /etc/xen/auto/             # 자동 시작 도메인"
    echo "  - /etc/default/grub          # GRUB 설정"
    echo
    echo -e "${CYAN}문서:${NC}"
    echo "  - man xl                     # xl 명령어 매뉴얼"
    echo "  - /usr/share/doc/xen-*       # Xen 문서"
}

# 메인 함수
main() {
    echo -e "${BLUE}=== Xen 설치 후 검증 v1.0 ===${NC}"
    echo -e "${BLUE}Xen 하이퍼바이저 설치 상태와 기능을 검증합니다.${NC}"
    echo
    
    local start_time=$(date +%s)
    
    # 순차적으로 모든 검증 실행
    check_xen_packages
    check_xen_hypervisor
    check_grub_configuration
    check_xen_tools
    check_dom0_status
    check_virtualization_features
    check_networking
    check_logging_system
    check_performance
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    echo "검증 완료 시간: ${duration}초"
    
    # 결과 요약 출력
    show_summary
    local exit_code=$?
    
    # 추가 정보 출력
    show_additional_info
    
    exit $exit_code
}

# 사용법 출력
show_usage() {
    echo "사용법: $0 [옵션]"
    echo
    echo "옵션:"
    echo "  -h, --help     이 도움말 출력"
    echo
    echo "이 스크립트는 Xen 설치 후 시스템 상태를 종합적으로 검증합니다."
    echo "검증 항목:"
    echo "  - Xen 패키지 설치 상태"
    echo "  - Xen 하이퍼바이저 작동 상태"
    echo "  - GRUB 부팅 구성"
    echo "  - Xen 관리 도구"
    echo "  - Dom0 상태"
    echo "  - 가상화 기능"
    echo "  - 네트워킹 설정"
    echo "  - 로깅 시스템"
    echo "  - 기본 성능"
}

# 옵션 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "알 수 없는 옵션: $1"
            show_usage
            exit 1
            ;;
    esac
done

# 메인 함수 실행
main