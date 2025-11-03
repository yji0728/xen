#!/bin/bash

#####################################################################
# Xen 설치 전 시스템 진단 도구 v1.0
# 상세한 호환성 검사 및 문제 사전 감지
#####################################################################

set -euo pipefail

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 진단 결과 저장
declare -A DIAGNOSTICS=(
    ["os_compatibility"]="PENDING"
    ["hardware_virtualization"]="PENDING"
    ["memory_resources"]="PENDING"
    ["disk_space"]="PENDING"
    ["network_config"]="PENDING"
    ["conflicting_software"]="PENDING"
    ["driver_compatibility"]="PENDING"
    ["bios_settings"]="PENDING"
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
    DIAGNOSTICS["$test"]="$result"
    
    case "$result" in
        "PASS") echo -e "${GREEN}✅ PASS${NC}" ;;
        "WARN") echo -e "${YELLOW}⚠️ WARNING${NC}" ;;
        "FAIL") echo -e "${RED}❌ FAIL${NC}" ;;
    esac
}

# OS 호환성 검사
check_os_compatibility() {
    log_section "운영체제 호환성 검사"
    
    local os_name=$(lsb_release -si 2>/dev/null || echo "Unknown")
    local os_version=$(lsb_release -sr 2>/dev/null || echo "Unknown")
    local os_codename=$(lsb_release -sc 2>/dev/null || echo "Unknown")
    
    echo "운영체제: $os_name $os_version ($os_codename)"
    
    if [[ "$os_name" != "Ubuntu" ]]; then
        log_error "Ubuntu가 아닌 운영체제는 지원되지 않습니다."
        update_result "os_compatibility" "FAIL"
        return 1
    fi
    
    if [[ ! "$os_version" =~ ^(22\.04|24\.04)$ ]]; then
        log_error "지원하지 않는 Ubuntu 버전입니다."
        log_error "지원 버전: 22.04 LTS, 24.04 LTS"
        update_result "os_compatibility" "FAIL"
        return 1
    fi
    
    # 커널 버전 확인
    local kernel_version=$(uname -r)
    echo "커널 버전: $kernel_version"
    
    # Ubuntu 22.04 특별 검사
    if [[ "$os_version" == "22.04" ]]; then
        if dpkg --compare-versions "$kernel_version" lt "5.15"; then
            log_warn "Ubuntu 22.04에서는 커널 5.15 이상이 권장됩니다."
            update_result "os_compatibility" "WARN"
        else
            log_info "커널 버전이 적절합니다."
            update_result "os_compatibility" "PASS"
        fi
    # Ubuntu 24.04 특별 검사
    elif [[ "$os_version" == "24.04" ]]; then
        if dpkg --compare-versions "$kernel_version" lt "6.8"; then
            log_warn "Ubuntu 24.04에서는 커널 6.8 이상이 권장됩니다."
            update_result "os_compatibility" "WARN"
        else
            log_info "커널 버전이 적절합니다."
            update_result "os_compatibility" "PASS"
        fi
    fi
    
    # 아키텍처 확인
    local arch=$(uname -m)
    echo "시스템 아키텍처: $arch"
    
    if [[ "$arch" != "x86_64" ]]; then
        log_error "x86_64 아키텍처만 지원됩니다."
        update_result "os_compatibility" "FAIL"
        return 1
    fi
    
    return 0
}

# 하드웨어 가상화 지원 검사
check_hardware_virtualization() {
    log_section "하드웨어 가상화 지원 검사"
    
    local cpu_info=$(cat /proc/cpuinfo)
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)
    local cpu_cores=$(nproc)
    
    echo "CPU: $cpu_model"
    echo "CPU 코어 수: $cpu_cores"
    
    # Intel VT-x 지원 확인
    if echo "$cpu_info" | grep -q "vmx"; then
        log_info "Intel VT-x 지원 감지됨"
        
        # EPT (Extended Page Tables) 지원 확인
        if grep -q "ept" /proc/cpuinfo; then
            log_info "Intel EPT (Extended Page Tables) 지원됨"
        else
            log_warn "Intel EPT 지원이 감지되지 않았습니다. 성능에 영향이 있을 수 있습니다."
        fi
        
    # AMD-V 지원 확인
    elif echo "$cpu_info" | grep -q "svm"; then
        log_info "AMD-V 지원 감지됨"
        
        # NPT (Nested Page Tables) 지원 확인
        if grep -q "npt" /proc/cpuinfo; then
            log_info "AMD NPT (Nested Page Tables) 지원됨"
        else
            log_warn "AMD NPT 지원이 감지되지 않았습니다. 성능에 영향이 있을 수 있습니다."
        fi
    else
        log_error "하드웨어 가상화 지원이 감지되지 않았습니다."
        log_error "BIOS/UEFI에서 Intel VT-x 또는 AMD-V를 활성화해주세요."
        update_result "hardware_virtualization" "FAIL"
        return 1
    fi
    
    # IOMMU 지원 확인
    if [[ -d /sys/kernel/iommu_groups ]] && [[ $(find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 -type d | wc -l) -gt 0 ]]; then
        log_info "IOMMU 지원 감지됨"
        local iommu_groups=$(find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 -type d | wc -l)
        echo "IOMMU 그룹 수: $iommu_groups"
    else
        log_warn "IOMMU가 비활성화되어 있거나 지원되지 않습니다."
        log_warn "PCI 패스스루 기능을 사용하려면 BIOS에서 IOMMU를 활성화하세요."
    fi
    
    # 가상화 확장 기능 확인
    local virt_features=()
    grep -q "rdrand" /proc/cpuinfo && virt_features+=("RDRAND")
    grep -q "rdseed" /proc/cpuinfo && virt_features+=("RDSEED")
    grep -q "smap" /proc/cpuinfo && virt_features+=("SMAP")
    grep -q "smep" /proc/cpuinfo && virt_features+=("SMEP")
    
    if [[ ${#virt_features[@]} -gt 0 ]]; then
        echo "추가 보안 기능: ${virt_features[*]}"
    fi
    
    update_result "hardware_virtualization" "PASS"
    return 0
}

# 메모리 리소스 검사
check_memory_resources() {
    log_section "메모리 리소스 검사"
    
    local mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    local mem_total_gb=$((mem_total_kb / 1024 / 1024))
    local mem_available_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    local mem_available_gb=$((mem_available_kb / 1024 / 1024))
    
    echo "총 메모리: ${mem_total_gb}GB"
    echo "사용 가능한 메모리: ${mem_available_gb}GB"
    
    if [[ $mem_total_gb -lt 4 ]]; then
        log_error "메모리가 부족합니다. 최소 4GB 필요 (권장: 8GB 이상)"
        update_result "memory_resources" "FAIL"
        return 1
    elif [[ $mem_total_gb -lt 8 ]]; then
        log_warn "메모리가 제한적입니다. 권장 용량은 8GB 이상입니다."
        update_result "memory_resources" "WARN"
    else
        log_info "메모리 용량이 충분합니다."
        update_result "memory_resources" "PASS"
    fi
    
    # 스왑 확인
    local swap_total_kb=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
    local swap_total_gb=$((swap_total_kb / 1024 / 1024))
    
    echo "스왑 크기: ${swap_total_gb}GB"
    
    if [[ $swap_total_gb -eq 0 ]]; then
        log_warn "스왑이 설정되어 있지 않습니다. Dom0에서 메모리 부족 시 문제가 발생할 수 있습니다."
    fi
    
    return 0
}

# 디스크 공간 검사
check_disk_space() {
    log_section "디스크 공간 검사"
    
    # 루트 파티션 확인
    local root_info=$(df -h / | tail -n1)
    local root_total=$(echo "$root_info" | awk '{print $2}')
    local root_used=$(echo "$root_info" | awk '{print $3}')
    local root_available=$(echo "$root_info" | awk '{print $4}')
    local root_usage=$(echo "$root_info" | awk '{print $5}' | tr -d '%')
    
    echo "루트 파티션 (/):"
    echo "  총 용량: $root_total"
    echo "  사용량: $root_used"
    echo "  여유공간: $root_available"
    echo "  사용률: ${root_usage}%"
    
    # GB 단위로 변환하여 확인
    local available_gb=$(df / | tail -n1 | awk '{printf "%.0f", $4/1024/1024}')
    
    if [[ $available_gb -lt 10 ]]; then
        log_error "디스크 공간이 부족합니다. 최소 10GB 필요 (권장: 50GB 이상)"
        update_result "disk_space" "FAIL"
        return 1
    elif [[ $available_gb -lt 20 ]]; then
        log_warn "디스크 공간이 제한적입니다. 20GB 이상을 권장합니다."
        update_result "disk_space" "WARN"
    else
        log_info "디스크 공간이 충분합니다."
        update_result "disk_space" "PASS"
    fi
    
    # /boot 파티션 확인
    if mountpoint -q /boot; then
        local boot_info=$(df -h /boot | tail -n1)
        local boot_available=$(echo "$boot_info" | awk '{print $4}')
        echo "/boot 파티션 여유공간: $boot_available"
        
        local boot_available_mb=$(df /boot | tail -n1 | awk '{printf "%.0f", $4/1024}')
        if [[ $boot_available_mb -lt 200 ]]; then
            log_warn "/boot 파티션 공간이 부족할 수 있습니다. (여유공간: ${boot_available})"
        fi
    fi
    
    return 0
}

# 네트워크 구성 검사
check_network_config() {
    log_section "네트워크 구성 검사"
    
    # 네트워크 인터페이스 확인
    local interfaces=($(ip link show | grep -E "^[0-9]+:" | grep -v "lo:" | awk -F: '{print $2}' | tr -d ' '))
    
    echo "네트워크 인터페이스:"
    for iface in "${interfaces[@]}"; do
        local ip_addr=$(ip addr show "$iface" | grep "inet " | awk '{print $2}' | head -n1)
        local link_state=$(ip link show "$iface" | grep -o "state [A-Z]*" | awk '{print $2}')
        echo "  $iface: $link_state ${ip_addr:-"IP 없음"}"
    done
    
    # 브릿지 인터페이스 확인
    if command -v brctl >/dev/null; then
        local bridges=$(brctl show 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v "^$")
        if [[ -n "$bridges" ]]; then
            echo "기존 브릿지:"
            echo "$bridges"
        fi
    else
        log_warn "bridge-utils가 설치되어 있지 않습니다. Xen 설치 시 자동으로 설치됩니다."
    fi
    
    # NetworkManager 확인
    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        log_info "NetworkManager가 실행 중입니다."
        echo "NetworkManager 버전: $(NetworkManager --version 2>/dev/null || echo "Unknown")"
        
        # NetworkManager 브릿지 호환성 확인
        if [[ -f /etc/NetworkManager/NetworkManager.conf ]]; then
            if grep -q "unmanaged-devices.*bridge" /etc/NetworkManager/conf.d/* 2>/dev/null; then
                log_info "NetworkManager 브릿지 설정이 이미 구성되어 있습니다."
            else
                log_warn "NetworkManager가 브릿지 인터페이스를 관리할 수 있습니다. Xen 설치 시 설정이 조정됩니다."
            fi
        fi
    else
        log_info "NetworkManager가 비활성화되어 있습니다."
    fi
    
    # systemd-networkd 확인
    if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        log_info "systemd-networkd가 실행 중입니다."
    fi
    
    update_result "network_config" "PASS"
    return 0
}

# 충돌 소프트웨어 검사
check_conflicting_software() {
    log_section "충돌 가능한 소프트웨어 검사"
    
    local conflicts_found=false
    
    # KVM 확인
    if lsmod | grep -q "kvm"; then
        log_warn "KVM 모듈이 로드되어 있습니다:"
        lsmod | grep kvm
        log_warn "Xen과 KVM은 동시에 사용할 수 없습니다. KVM을 사용 중이라면 비활성화가 필요합니다."
        conflicts_found=true
    fi
    
    # VirtualBox 확인
    if command -v vboxmanage >/dev/null || lsmod | grep -q "vbox"; then
        log_warn "VirtualBox가 설치되어 있거나 실행 중입니다."
        log_warn "Xen과 VirtualBox는 동시에 사용할 수 없습니다."
        conflicts_found=true
    fi
    
    # VMware 확인
    if lsmod | grep -q "vmw\|vmx"; then
        log_warn "VMware 관련 모듈이 로드되어 있습니다:"
        lsmod | grep -E "vmw|vmx"
        log_warn "Xen과 VMware는 동시에 사용할 수 없습니다."
        conflicts_found=true
    fi
    
    # Docker 확인
    if systemctl is-active --quiet docker 2>/dev/null; then
        log_info "Docker가 실행 중입니다."
        log_info "Docker는 Xen과 함께 사용할 수 있지만, 리소스 사용량을 고려해야 합니다."
    fi
    
    # libvirt 확인
    if systemctl is-active --quiet libvirtd 2>/dev/null; then
        log_warn "libvirt 데몬이 실행 중입니다."
        log_warn "libvirt를 통한 KVM 사용과 충돌할 수 있습니다."
        conflicts_found=true
    fi
    
    # QEMU 프로세스 확인
    if pgrep -x qemu-system-x86_64 >/dev/null; then
        log_warn "QEMU 프로세스가 실행 중입니다."
        log_warn "기존 가상머신과 충돌할 수 있습니다."
        conflicts_found=true
    fi
    
    if [[ "$conflicts_found" == "true" ]]; then
        update_result "conflicting_software" "WARN"
    else
        log_info "충돌하는 소프트웨어가 감지되지 않았습니다."
        update_result "conflicting_software" "PASS"
    fi
    
    return 0
}

# 드라이버 호환성 검사
check_driver_compatibility() {
    log_section "드라이버 호환성 검사"
    
    local ubuntu_version=$(lsb_release -rs)
    local issues_found=false
    
    echo "Ubuntu 버전: $ubuntu_version"
    
    # MegaRAID 드라이버 검사 (Ubuntu 24.04에서 문제)
    if lspci | grep -qi "megaraid"; then
        log_info "MegaRAID 컨트롤러 감지됨:"
        lspci | grep -i megaraid
        
        if [[ "$ubuntu_version" == "24.04" ]]; then
            log_warn "Ubuntu 24.04에서 MegaRAID 호환성 문제가 알려져 있습니다."
            log_warn "설치 시 IOMMU 설정이 자동으로 적용됩니다."
            issues_found=true
        fi
    fi
    
    # AMD 그래픽 드라이버 검사 (Ubuntu 24.04에서 문제)
    if lspci | grep -i "amd.*vga\|radeon"; then
        log_info "AMD 그래픽 카드 감지됨:"
        lspci | grep -i -E "amd|radeon|ati"
        
        if [[ "$ubuntu_version" == "24.04" ]]; then
            log_warn "Ubuntu 24.04에서 AMD 그래픽 드라이버 호환성 문제가 알려져 있습니다."
            log_warn "설치 시 nomodeset 옵션이 자동으로 적용됩니다."
            issues_found=true
        fi
    fi
    
    # NVIDIA 그래픽 드라이버 검사
    if lspci | grep -i "nvidia"; then
        log_info "NVIDIA 그래픽 카드 감지됨:"
        lspci | grep -i nvidia
        
        if command -v nvidia-smi >/dev/null; then
            log_info "NVIDIA 드라이버가 설치되어 있습니다."
            local nvidia_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -n1)
            echo "NVIDIA 드라이버 버전: $nvidia_version"
        else
            log_warn "NVIDIA 그래픽 카드가 있지만 전용 드라이버가 설치되어 있지 않습니다."
        fi
    fi
    
    # 네트워크 카드 확인
    log_info "네트워크 컨트롤러:"
    lspci | grep -i "network\|ethernet" | head -n5
    
    # 브릿지 네트워킹 호환성 확인 (Ubuntu 24.04 특별 검사)
    if [[ "$ubuntu_version" == "24.04" ]]; then
        log_warn "Ubuntu 24.04에서 네트워크 브릿지 설정 변경이 필요할 수 있습니다."
        log_warn "설치 시 네트워크 설정이 자동으로 최적화됩니다."
        issues_found=true
    fi
    
    if [[ "$issues_found" == "true" ]]; then
        update_result "driver_compatibility" "WARN"
    else
        log_info "알려진 드라이버 호환성 문제가 감지되지 않았습니다."
        update_result "driver_compatibility" "PASS"
    fi
    
    return 0
}

# BIOS/UEFI 설정 검사
check_bios_settings() {
    log_section "BIOS/UEFI 설정 검사"
    
    # UEFI vs BIOS 확인
    if [[ -d /sys/firmware/efi ]]; then
        log_info "UEFI 부팅 모드 감지됨"
        
        # Secure Boot 상태 확인
        if command -v mokutil >/dev/null; then
            local sb_state=$(mokutil --sb-state 2>/dev/null || echo "unknown")
            echo "Secure Boot 상태: $sb_state"
            
            if echo "$sb_state" | grep -q "enabled"; then
                log_warn "Secure Boot이 활성화되어 있습니다."
                log_warn "Xen 부팅을 위해 추가 설정이 필요할 수 있습니다."
                update_result "bios_settings" "WARN"
            else
                log_info "Secure Boot이 비활성화되어 있습니다."
                update_result "bios_settings" "PASS"
            fi
        else
            log_warn "mokutil을 찾을 수 없어 Secure Boot 상태를 확인할 수 없습니다."
            update_result "bios_settings" "WARN"
        fi
        
        # UEFI 변수 접근 확인
        if [[ -w /sys/firmware/efi/efivars ]]; then
            log_info "UEFI 변수에 쓰기 권한이 있습니다."
        else
            log_warn "UEFI 변수에 쓰기 권한이 없습니다."
        fi
        
    else
        log_info "Legacy BIOS 부팅 모드 감지됨"
        update_result "bios_settings" "PASS"
    fi
    
    # 부팅 순서 및 설정 확인
    if command -v efibootmgr >/dev/null 2>&1; then
        echo "현재 부팅 항목:"
        efibootmgr | head -n10
    fi
    
    return 0
}

# 종합 결과 출력
show_summary() {
    log_section "진단 결과 요약"
    
    local pass_count=0
    local warn_count=0
    local fail_count=0
    
    echo "┌─────────────────────────────────────┬────────────┐"
    echo "│ 검사 항목                           │ 결과       │"
    echo "├─────────────────────────────────────┼────────────┤"
    
    for test in "${!DIAGNOSTICS[@]}"; do
        local result="${DIAGNOSTICS[$test]}"
        local test_name=""
        
        case "$test" in
            "os_compatibility") test_name="운영체제 호환성" ;;
            "hardware_virtualization") test_name="하드웨어 가상화 지원" ;;
            "memory_resources") test_name="메모리 리소스" ;;
            "disk_space") test_name="디스크 공간" ;;
            "network_config") test_name="네트워크 구성" ;;
            "conflicting_software") test_name="충돌 소프트웨어" ;;
            "driver_compatibility") test_name="드라이버 호환성" ;;
            "bios_settings") test_name="BIOS/UEFI 설정" ;;
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
        echo -e "${RED}⚠️ 실패한 항목들을 해결한 후 Xen 설치를 진행하세요.${NC}"
        return 1
    elif [[ $warn_count -gt 0 ]]; then
        echo -e "${YELLOW}⚠️ 경고 항목들을 검토한 후 설치를 진행하는 것을 권장합니다.${NC}"
        return 0
    else
        echo -e "${GREEN}✅ 모든 검사를 통과했습니다. Xen 설치를 진행할 수 있습니다.${NC}"
        return 0
    fi
}

# 메인 함수
main() {
    echo -e "${BLUE}=== Xen 설치 전 시스템 진단 v1.0 ===${NC}"
    echo -e "${BLUE}Ubuntu 22.04/24.04에서 Xen 호환성을 검사합니다.${NC}"
    echo
    
    local start_time=$(date +%s)
    
    # 순차적으로 모든 검사 실행
    check_os_compatibility
    check_hardware_virtualization  
    check_memory_resources
    check_disk_space
    check_network_config
    check_conflicting_software
    check_driver_compatibility
    check_bios_settings
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    echo "진단 완료 시간: ${duration}초"
    
    # 결과 요약 출력
    show_summary
    
    local exit_code=$?
    
    echo
    echo -e "${CYAN}진단 완료. Xen 설치를 진행하려면 다음 명령어를 실행하세요:${NC}"
    echo -e "${CYAN}sudo ./xen_reliable_installer.sh${NC}"
    
    exit $exit_code
}

# 사용법 출력
show_usage() {
    echo "사용법: $0 [옵션]"
    echo
    echo "옵션:"
    echo "  -h, --help     이 도움말 출력"
    echo
    echo "이 스크립트는 Xen 설치 전 시스템 호환성을 종합적으로 검사합니다."
    echo "검사 항목:"
    echo "  - 운영체제 호환성 (Ubuntu 22.04/24.04)"
    echo "  - 하드웨어 가상화 지원 (Intel VT-x/AMD-V)"
    echo "  - 시스템 리소스 (메모리, 디스크)"
    echo "  - 네트워크 구성"
    echo "  - 충돌 가능한 소프트웨어"
    echo "  - 드라이버 호환성"
    echo "  - BIOS/UEFI 설정"
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