#!/bin/bash

# Ubuntu 22.04/24.04 드라이버 호환성 사전 진단 스크립트
# 작성자: MiniMax Agent
# 버전: 1.0
# 사용법: sudo ./pre_installation_check.sh

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수들
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 루트 권한 확인
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        exit 1
    fi
}

# Ubuntu 버전 확인
check_ubuntu_version() {
    log_info "Ubuntu 버전 확인 중..."
    
    if [[ -f /etc/lsb-release ]]; then
        source /etc/lsb-release
        log_info "배포판: $DISTRIB_DESCRIPTION"
        
        case $DISTRIB_RELEASE in
            "22.04")
                log_success "지원되는 Ubuntu 22.04 LTS 버전입니다."
                ;;
            "24.04")
                log_success "지원되는 Ubuntu 24.04 LTS 버전입니다."
                ;;
            *)
                log_warn "이 스크립트는 Ubuntu 22.04/24.04 LTS용으로 설계되었습니다."
                ;;
        esac
    else
        log_error "/etc/lsb-release 파일을 찾을 수 없습니다."
    fi
    
    # 커널 버전 확인
    KERNEL_VERSION=$(uname -r)
    log_info "현재 커널 버전: $KERNEL_VERSION"
}

# MegaRAID 컨트롤러 확인
check_megaraid() {
    log_info "MegaRAID 컨트롤러 검사 중..."
    
    # PCI 장치에서 MegaRAID 컨트롤러 찾기
    MEGARAID_DEVICES=$(lspci | grep -i -E "(megaraid|lsi|broadcom.*raid)" || true)
    
    if [[ -n "$MEGARAID_DEVICES" ]]; then
        log_warn "MegaRAID 컨트롤러가 감지되었습니다:"
        echo "$MEGARAID_DEVICES"
        
        # 드라이버 모듈 확인
        if lsmod | grep -q megaraid_sas; then
            DRIVER_VERSION=$(modinfo megaraid_sas | grep version | head -1 | awk '{print $2}')
            log_info "현재 megaraid_sas 드라이버 버전: $DRIVER_VERSION"
            
            # Ubuntu 24.04에서 문제가 될 수 있는 버전 확인
            if [[ "$DISTRIB_RELEASE" == "24.04" ]]; then
                log_warn "Ubuntu 24.04에서 MegaRAID 호환성 문제가 발생할 수 있습니다."
                log_info "권장 해결책: GRUB에 'intel_iommu=on iommu=pt' 추가"
            fi
        else
            log_warn "megaraid_sas 드라이버가 로드되지 않았습니다."
        fi
        
        # IOMMU 상태 확인
        if dmesg | grep -q "IOMMU enabled"; then
            log_success "IOMMU가 활성화되어 있습니다."
        else
            log_warn "IOMMU가 비활성화되어 있습니다. MegaRAID 문제가 발생할 수 있습니다."
        fi
    else
        log_success "MegaRAID 컨트롤러가 감지되지 않았습니다."
    fi
}

# 네트워크 브릿지 구성 확인
check_network_bridge() {
    log_info "네트워크 브릿지 구성 검사 중..."
    
    # 브릿지 인터페이스 확인
    BRIDGES=$(brctl show 2>/dev/null | grep -v "bridge name" | awk '{print $1}' | grep -v "^$" || true)
    
    if [[ -n "$BRIDGES" ]]; then
        log_info "감지된 브릿지 인터페이스:"
        brctl show
        
        # Netplan 구성 파일 확인
        NETPLAN_FILES=$(find /etc/netplan -name "*.yaml" -o -name "*.yml" 2>/dev/null || true)
        if [[ -n "$NETPLAN_FILES" ]]; then
            log_info "Netplan 구성 파일이 발견되었습니다:"
            echo "$NETPLAN_FILES"
            
            # 브릿지 구성이 포함된 파일 확인
            for file in $NETPLAN_FILES; do
                if grep -q "bridges:" "$file" 2>/dev/null; then
                    log_info "브릿지 구성이 포함된 파일: $file"
                fi
            done
        fi
        
        # systemd-networkd vs NetworkManager 확인
        if systemctl is-active --quiet systemd-networkd; then
            log_info "systemd-networkd가 활성화되어 있습니다."
        fi
        
        if systemctl is-active --quiet NetworkManager; then
            log_info "NetworkManager가 활성화되어 있습니다."
        fi
        
        # 잠재적 충돌 경고
        if systemctl is-active --quiet systemd-networkd && systemctl is-active --quiet NetworkManager; then
            log_warn "systemd-networkd와 NetworkManager가 모두 활성화되어 있습니다. 충돌 가능성이 있습니다."
        fi
    else
        log_success "브릿지 인터페이스가 감지되지 않았습니다."
    fi
}

# 그래픽 카드 확인
check_graphics() {
    log_info "그래픽 카드 검사 중..."
    
    # PCI 그래픽 장치 확인
    GPU_DEVICES=$(lspci | grep -i -E "(vga|3d|display)" || true)
    
    if [[ -n "$GPU_DEVICES" ]]; then
        log_info "감지된 그래픽 장치:"
        echo "$GPU_DEVICES"
        
        # AMD 그래픽 카드 확인
        if echo "$GPU_DEVICES" | grep -qi amd; then
            log_warn "AMD 그래픽 카드가 감지되었습니다."
            
            # AMDGPU 드라이버 확인
            if lsmod | grep -q amdgpu; then
                log_info "amdgpu 드라이버가 로드되어 있습니다."
            fi
            
            if lsmod | grep -q radeon; then
                log_info "radeon 드라이버가 로드되어 있습니다."
            fi
            
            log_info "AMD 그래픽에서 안정성 문제가 발생할 수 있습니다."
            log_info "권장 해결책: GRUB에 'nomodeset' 추가 또는 독점 드라이버 설치"
        fi
        
        # NVIDIA 그래픽 카드 확인
        if echo "$GPU_DEVICES" | grep -qi nvidia; then
            log_warn "NVIDIA 그래픽 카드가 감지되었습니다."
            
            if lsmod | grep -q nvidia; then
                NVIDIA_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null || echo "Unknown")
                log_info "NVIDIA 드라이버 버전: $NVIDIA_VERSION"
            else
                log_warn "NVIDIA 독점 드라이버가 설치되지 않았습니다."
                if lsmod | grep -q nouveau; then
                    log_info "nouveau 오픈소스 드라이버가 사용 중입니다."
                fi
            fi
        fi
        
        # Intel 통합 그래픽 확인
        if echo "$GPU_DEVICES" | grep -qi intel; then
            log_success "Intel 통합 그래픽이 감지되었습니다. 일반적으로 안정적입니다."
        fi
    else
        log_error "그래픽 장치를 찾을 수 없습니다."
    fi
}

# GRUB 구성 확인
check_grub_config() {
    log_info "GRUB 구성 검사 중..."
    
    if [[ -f /etc/default/grub ]]; then
        log_info "현재 GRUB 커널 매개변수:"
        grep "GRUB_CMDLINE_LINUX" /etc/default/grub || true
        
        # 문제 해결을 위해 필요할 수 있는 매개변수들 확인
        GRUB_CMDLINE=$(grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub | cut -d'"' -f2)
        
        if echo "$GRUB_CMDLINE" | grep -q "intel_iommu=on"; then
            log_success "IOMMU가 GRUB에서 활성화되어 있습니다."
        else
            log_info "IOMMU가 GRUB에서 비활성화되어 있습니다."
        fi
        
        if echo "$GRUB_CMDLINE" | grep -q "nomodeset"; then
            log_info "nomodeset이 설정되어 있습니다."
        fi
        
        # UEFI vs BIOS 부팅 모드 확인
        if [[ -d /sys/firmware/efi ]]; then
            log_success "시스템이 UEFI 모드로 부팅되었습니다."
        else
            log_info "시스템이 BIOS(레거시) 모드로 부팅되었습니다."
        fi
    else
        log_error "/etc/default/grub 파일을 찾을 수 없습니다."
    fi
}

# 시스템 로그에서 드라이버 오류 확인
check_system_logs() {
    log_info "시스템 로그에서 드라이버 관련 오류 검사 중..."
    
    # 최근 드라이버 관련 오류 확인
    DRIVER_ERRORS=$(dmesg | grep -i -E "(error|failed|timeout)" | grep -i -E "(megaraid|amdgpu|radeon|nouveau|nvidia)" | tail -10 || true)
    
    if [[ -n "$DRIVER_ERRORS" ]]; then
        log_warn "드라이버 관련 오류가 발견되었습니다:"
        echo "$DRIVER_ERRORS"
    else
        log_success "최근 드라이버 관련 심각한 오류가 발견되지 않았습니다."
    fi
    
    # 부팅 시간이 오래 걸리는지 확인
    BOOT_TIME=$(systemd-analyze | grep "Startup finished" | awk '{print $(NF-1), $NF}' || echo "Unknown")
    log_info "시스템 부팅 시간: $BOOT_TIME"
}

# 권장사항 출력
print_recommendations() {
    log_info "=== 권장사항 요약 ==="
    
    # MegaRAID 권장사항
    if lspci | grep -q -i -E "(megaraid|lsi|broadcom.*raid)"; then
        echo "• MegaRAID 컨트롤러 감지됨:"
        echo "  - Ubuntu 24.04에서 부팅 문제 발생 시: GRUB에 'intel_iommu=on iommu=pt' 추가"
        echo "  - BIOS를 UEFI 모드로 변경 검토"
        echo "  - 최신 펌웨어로 업데이트"
    fi
    
    # 그래픽 권장사항
    if lspci | grep -q -i amd; then
        echo "• AMD 그래픽 카드 감지됨:"
        echo "  - 부팅 문제 시: GRUB에 'nomodeset' 추가"
        echo "  - 안정성을 위해 AMDGPU-PRO 드라이버 설치 고려"
        echo "  - 외부 디스플레이 사용 시 주의"
    fi
    
    if lspci | grep -q -i nvidia; then
        echo "• NVIDIA 그래픽 카드 감지됨:"
        echo "  - 독점 드라이버 설치 권장: sudo ubuntu-drivers autoinstall"
        echo "  - Secure Boot 설정 확인"
    fi
    
    # 네트워크 권장사항
    if brctl show 2>/dev/null | grep -q -v "bridge name"; then
        echo "• 네트워크 브릿지 감지됨:"
        echo "  - Ubuntu 24.04 업그레이드 후 브릿지 구성 재확인 필요"
        echo "  - Netplan 구성 파일 백업 권장"
    fi
    
    echo "• 일반 권장사항:"
    echo "  - 업그레이드 전 전체 시스템 백업"
    echo "  - 테스트 환경에서 먼저 검증"
    echo "  - 중요한 작업 완료 후 업그레이드 수행"
}

# 메인 함수
main() {
    echo "=================================================="
    echo "Ubuntu 22.04/24.04 드라이버 호환성 사전 진단"
    echo "=================================================="
    
    check_root
    check_ubuntu_version
    echo
    
    check_megaraid
    echo
    
    check_network_bridge
    echo
    
    check_graphics
    echo
    
    check_grub_config
    echo
    
    check_system_logs
    echo
    
    print_recommendations
    
    echo
    log_success "사전 진단이 완료되었습니다."
    echo "세부 해결 방안은 driver_compatibility_solutions.md 문서를 참조하세요."
}

main "$@"