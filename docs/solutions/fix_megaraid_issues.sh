#!/bin/bash

# MegaRAID 드라이버 문제 해결 스크립트
# 작성자: MiniMax Agent
# 버전: 1.0
# 사용법: sudo ./fix_megaraid_issues.sh

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# 백업 디렉토리 생성
BACKUP_DIR="/root/driver-compatibility-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# GRUB 백업
backup_grub() {
    log_info "GRUB 구성 백업 중..."
    cp /etc/default/grub "$BACKUP_DIR/grub.backup"
    if [[ -f /boot/grub/grub.cfg ]]; then
        cp /boot/grub/grub.cfg "$BACKUP_DIR/grub.cfg.backup"
    fi
    log_success "GRUB 백업 완료: $BACKUP_DIR"
}

# MegaRAID 하드웨어 감지
detect_megaraid() {
    log_info "MegaRAID 컨트롤러 감지 중..."
    
    MEGARAID_DEVICES=$(lspci | grep -i -E "(megaraid|lsi|broadcom.*raid)" || true)
    
    if [[ -z "$MEGARAID_DEVICES" ]]; then
        log_error "MegaRAID 컨트롤러가 감지되지 않았습니다."
        exit 1
    fi
    
    log_success "MegaRAID 컨트롤러 감지됨:"
    echo "$MEGARAID_DEVICES"
    return 0
}

# IOMMU 지원 확인
check_iommu_support() {
    log_info "IOMMU 지원 확인 중..."
    
    # Intel VT-d 확인
    if grep -q "Intel VT-d" /proc/cpuinfo || dmesg | grep -q "Intel-IOMMU"; then
        log_success "Intel VT-d IOMMU 지원이 감지되었습니다."
        return 0
    fi
    
    # AMD IOMMU 확인
    if dmesg | grep -q "AMD-Vi"; then
        log_success "AMD-Vi IOMMU 지원이 감지되었습니다."
        return 0
    fi
    
    log_warn "IOMMU 지원을 확인할 수 없습니다. BIOS에서 VT-d/IOMMU가 활성화되어 있는지 확인하세요."
    return 1
}

# GRUB에 IOMMU 매개변수 추가
add_iommu_parameters() {
    log_info "GRUB에 IOMMU 매개변수 추가 중..."
    
    # 현재 GRUB_CMDLINE_LINUX_DEFAULT 확인
    CURRENT_CMDLINE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | cut -d'"' -f2)
    
    # 이미 IOMMU 설정이 있는지 확인
    if echo "$CURRENT_CMDLINE" | grep -q "intel_iommu=on"; then
        log_info "intel_iommu=on이 이미 설정되어 있습니다."
    else
        log_info "intel_iommu=on 추가 중..."
        CURRENT_CMDLINE="$CURRENT_CMDLINE intel_iommu=on"
    fi
    
    if echo "$CURRENT_CMDLINE" | grep -q "iommu=pt"; then
        log_info "iommu=pt가 이미 설정되어 있습니다."
    else
        log_info "iommu=pt 추가 중..."
        CURRENT_CMDLINE="$CURRENT_CMDLINE iommu=pt"
    fi
    
    # GRUB 파일 업데이트
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$CURRENT_CMDLINE\"|" /etc/default/grub
    
    log_success "GRUB 매개변수 업데이트 완료"
    log_info "새로운 커널 매개변수: $CURRENT_CMDLINE"
}

# GRUB 업데이트
update_grub() {
    log_info "GRUB 구성 업데이트 중..."
    
    if command -v update-grub >/dev/null 2>&1; then
        update-grub
    else
        grub-mkconfig -o /boot/grub/grub.cfg
    fi
    
    log_success "GRUB 업데이트 완료"
}

# 드라이버 정보 확인
check_driver_info() {
    log_info "MegaRAID 드라이버 정보 확인 중..."
    
    if lsmod | grep -q megaraid_sas; then
        DRIVER_VERSION=$(modinfo megaraid_sas | grep "^version:" | awk '{print $2}')
        log_info "현재 megaraid_sas 드라이버 버전: $DRIVER_VERSION"
        
        # 문제가 있는 버전 확인
        case "$DRIVER_VERSION" in
            "07.727.03.00-rc1")
                log_warn "이 드라이버 버전은 Ubuntu 24.04에서 IOMMU 문제를 일으킬 수 있습니다."
                ;;
            *)
                log_info "드라이버 버전은 일반적으로 안정적입니다."
                ;;
        esac
    else
        log_warn "megaraid_sas 드라이버가 로드되지 않았습니다."
    fi
}

# initramfs 재생성
rebuild_initramfs() {
    log_info "initramfs 재생성 중..."
    
    KERNEL_VERSION=$(uname -r)
    update-initramfs -u -k "$KERNEL_VERSION"
    
    log_success "initramfs 재생성 완료"
}

# 추가 문제 해결 옵션
additional_fixes() {
    log_info "추가 문제 해결 옵션 적용 중..."
    
    # 필요시 추가 커널 매개변수
    read -p "PCI 구성 문제가 있는 경우 pci=nommconf를 추가하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        CURRENT_CMDLINE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | cut -d'"' -f2)
        if ! echo "$CURRENT_CMDLINE" | grep -q "pci=nommconf"; then
            CURRENT_CMDLINE="$CURRENT_CMDLINE pci=nommconf"
            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$CURRENT_CMDLINE\"|" /etc/default/grub
            log_info "pci=nommconf 매개변수가 추가되었습니다."
        fi
    fi
    
    # ACPI 관련 문제 해결
    read -p "ACPI 관련 문제가 있는 경우 acpi=ht를 추가하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        CURRENT_CMDLINE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | cut -d'"' -f2)
        if ! echo "$CURRENT_CMDLINE" | grep -q "acpi=ht"; then
            CURRENT_CMDLINE="$CURRENT_CMDLINE acpi=ht"
            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$CURRENT_CMDLINE\"|" /etc/default/grub
            log_info "acpi=ht 매개변수가 추가되었습니다."
        fi
    fi
}

# 시스템 정보 수집
collect_system_info() {
    log_info "시스템 정보 수집 중..."
    
    INFO_FILE="$BACKUP_DIR/system_info.txt"
    
    {
        echo "=== 시스템 정보 ==="
        echo "날짜: $(date)"
        echo "Ubuntu 버전: $(lsb_release -d | cut -f2)"
        echo "커널 버전: $(uname -r)"
        echo
        echo "=== MegaRAID 장치 ==="
        lspci | grep -i -E "(megaraid|lsi|broadcom.*raid)"
        echo
        echo "=== 로드된 드라이버 ==="
        lsmod | grep -E "(megaraid|mpt)"
        echo
        echo "=== GRUB 구성 ==="
        grep "GRUB_CMDLINE_LINUX" /etc/default/grub
        echo
        echo "=== IOMMU 상태 ==="
        dmesg | grep -i iommu | tail -10
        echo
        echo "=== 부팅 로그 ==="
        dmesg | grep -i megaraid | tail -10
    } > "$INFO_FILE"
    
    log_success "시스템 정보가 $INFO_FILE에 저장되었습니다."
}

# 테스트 및 검증
verify_fix() {
    log_info "수정사항 검증 중..."
    
    # GRUB 구성 확인
    CURRENT_CMDLINE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | cut -d'"' -f2)
    log_info "현재 GRUB 커널 매개변수: $CURRENT_CMDLINE"
    
    if echo "$CURRENT_CMDLINE" | grep -q "intel_iommu=on" && echo "$CURRENT_CMDLINE" | grep -q "iommu=pt"; then
        log_success "IOMMU 매개변수가 올바르게 설정되었습니다."
    else
        log_warn "IOMMU 매개변수 설정을 확인하세요."
    fi
    
    # 백업 정보 표시
    log_info "백업 파일들:"
    ls -la "$BACKUP_DIR"
}

# 메인 실행 함수
main() {
    echo "=================================================="
    echo "MegaRAID 드라이버 문제 해결 스크립트"
    echo "=================================================="
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        exit 1
    fi
    
    # 경고 메시지
    log_warn "이 스크립트는 시스템 부팅 구성을 수정합니다."
    log_warn "실행 전 중요한 데이터를 백업하세요."
    
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "스크립트 실행이 취소되었습니다."
        exit 0
    fi
    
    # 단계별 실행
    backup_grub
    detect_megaraid
    check_iommu_support
    check_driver_info
    add_iommu_parameters
    additional_fixes
    update_grub
    rebuild_initramfs
    collect_system_info
    verify_fix
    
    echo
    log_success "MegaRAID 문제 해결 완료!"
    echo
    log_warn "시스템을 재부팅하여 변경사항을 적용하세요."
    log_info "문제가 지속되는 경우 BIOS에서 다음을 확인하세요:"
    echo "  - Intel VT-d 또는 AMD IOMMU 활성화"
    echo "  - UEFI 부팅 모드 사용 (권장)"
    echo "  - Secure Boot 설정 확인"
    echo
    log_info "롤백이 필요한 경우: $BACKUP_DIR/grub.backup 파일을 /etc/default/grub로 복원하세요."
    
    read -p "지금 재부팅하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "시스템을 재부팅합니다..."
        sleep 3
        reboot
    fi
}

main "$@"