#!/bin/bash

#####################################################################
# Xen 신뢰성 높은 설치 시스템 v1.0
# Ubuntu 22.04/24.04 LTS에서 Xen 하이퍼바이저를 안정적으로 설치
#
# 기능:
# - 환경 자동 진단 및 사전 검증
# - 의존성 충돌 자동 해결 
# - 드라이버 호환성 문제 해결
# - 단계별 설치 검증
# - 오류 시 자동 롤백
#####################################################################

set -euo pipefail

# 색상 코드 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 전역 변수
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/xen-installer"
BACKUP_DIR="/var/backups/xen-installer"
TEMP_DIR="/tmp/xen-installer-$$"
INSTALLER_VERSION="1.0"
START_TIME=$(date +%s)

# 로그 레벨
LOG_LEVEL_ERROR=1
LOG_LEVEL_WARN=2
LOG_LEVEL_INFO=3
LOG_LEVEL_DEBUG=4
CURRENT_LOG_LEVEL=3

# 설치 상태 추적
declare -A INSTALL_PROGRESS=(
    ["environment_check"]="PENDING"
    ["dependency_resolution"]="PENDING"
    ["driver_compatibility"]="PENDING"
    ["xen_installation"]="PENDING"
    ["verification"]="PENDING"
    ["logging_setup"]="PENDING"
)

# 초기화 함수
init_installer() {
    echo -e "${BLUE}=== Xen 신뢰성 높은 설치 시스템 v${INSTALLER_VERSION} ===${NC}"
    echo -e "${CYAN}Ubuntu 22.04/24.04 LTS 환경에서 Xen 하이퍼바이저를 안정적으로 설치합니다.${NC}"
    echo

    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        echo -e "${RED}오류: sudo로 실행해주세요: sudo $0${NC}"
        exit 1
    fi

    # 디렉토리 생성
    mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$TEMP_DIR"

    # 로그 파일 초기화
    local log_file="${LOG_DIR}/xen-install-$(date +%Y%m%d-%H%M%S).log"
    exec 1> >(tee -a "$log_file")
    exec 2> >(tee -a "$log_file" >&2)

    log_info "설치 시작: $(date)"
    log_info "로그 파일: $log_file"
    log_info "백업 디렉토리: $BACKUP_DIR"
}

# 로깅 함수들
log_debug() { [[ $CURRENT_LOG_LEVEL -ge $LOG_LEVEL_DEBUG ]] && echo -e "${CYAN}[DEBUG]${NC} $1"; }
log_info() { [[ $CURRENT_LOG_LEVEL -ge $LOG_LEVEL_INFO ]] && echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { [[ $CURRENT_LOG_LEVEL -ge $LOG_LEVEL_WARN ]] && echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { [[ $CURRENT_LOG_LEVEL -ge $LOG_LEVEL_ERROR ]] && echo -e "${RED}[ERROR]${NC} $1"; }

# 진행 상황 업데이트
update_progress() {
    local step="$1"
    local status="$2"
    INSTALL_PROGRESS["$step"]="$status"
    
    case "$status" in
        "IN_PROGRESS") echo -e "${YELLOW}⏳ ${step}: 진행 중...${NC}" ;;
        "COMPLETED") echo -e "${GREEN}✅ ${step}: 완료${NC}" ;;
        "FAILED") echo -e "${RED}❌ ${step}: 실패${NC}" ;;
        "SKIPPED") echo -e "${CYAN}⏭️ ${step}: 스킵됨${NC}" ;;
    esac
}

# 진행 상황 출력
show_progress() {
    echo -e "\n${BLUE}=== 설치 진행 상황 ===${NC}"
    for step in "${!INSTALL_PROGRESS[@]}"; do
        local status="${INSTALL_PROGRESS[$step]}"
        case "$status" in
            "PENDING") echo -e "${YELLOW}⏸️ ${step}: 대기 중${NC}" ;;
            "IN_PROGRESS") echo -e "${YELLOW}⏳ ${step}: 진행 중${NC}" ;;
            "COMPLETED") echo -e "${GREEN}✅ ${step}: 완료${NC}" ;;
            "FAILED") echo -e "${RED}❌ ${step}: 실패${NC}" ;;
            "SKIPPED") echo -e "${CYAN}⏭️ ${step}: 스킵됨${NC}" ;;
        esac
    done
    echo
}

# 시스템 환경 검사
check_environment() {
    update_progress "environment_check" "IN_PROGRESS"
    log_info "시스템 환경 검사 시작"

    # Ubuntu 버전 확인
    local ubuntu_version=$(lsb_release -rs 2>/dev/null || echo "unknown")
    local ubuntu_codename=$(lsb_release -cs 2>/dev/null || echo "unknown")
    
    if [[ ! "$ubuntu_version" =~ ^(22\.04|24\.04)$ ]]; then
        log_error "지원하지 않는 Ubuntu 버전: $ubuntu_version"
        log_error "지원 버전: Ubuntu 22.04 LTS, 24.04 LTS"
        update_progress "environment_check" "FAILED"
        return 1
    fi

    log_info "Ubuntu 버전: $ubuntu_version ($ubuntu_codename)"

    # 아키텍처 확인
    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        log_error "지원하지 않는 아키텍처: $arch"
        log_error "x86_64 아키텍처만 지원됩니다."
        update_progress "environment_check" "FAILED"
        return 1
    fi

    # 하드웨어 가상화 지원 확인
    if ! grep -q "vmx\|svm" /proc/cpuinfo; then
        log_error "하드웨어 가상화 기능이 비활성화되어 있습니다."
        log_error "BIOS/UEFI에서 Intel VT-x 또는 AMD-V를 활성화해주세요."
        update_progress "environment_check" "FAILED"
        return 1
    fi

    # 메모리 확인 (최소 4GB)
    local mem_gb=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
    if [[ $mem_gb -lt 4 ]]; then
        log_warn "메모리가 부족합니다: ${mem_gb}GB (권장: 8GB 이상)"
    else
        log_info "메모리: ${mem_gb}GB"
    fi

    # 디스크 공간 확인 (최소 10GB)
    local free_space=$(df / | awk 'NR==2 {printf "%.0f", $4/1024/1024}')
    if [[ $free_space -lt 10 ]]; then
        log_error "디스크 공간이 부족합니다: ${free_space}GB (최소: 10GB)"
        update_progress "environment_check" "FAILED"
        return 1
    fi

    log_info "디스크 여유공간: ${free_space}GB"

    # UEFI 부팅 확인
    if [[ -d /sys/firmware/efi ]]; then
        log_info "UEFI 부팅 모드 감지"
        
        # Secure Boot 상태 확인
        if command -v mokutil >/dev/null 2>&1; then
            local secure_boot_status=$(mokutil --sb-state 2>/dev/null | grep -o "enabled\|disabled" || echo "unknown")
            log_info "Secure Boot 상태: $secure_boot_status"
            
            if [[ "$secure_boot_status" == "enabled" ]]; then
                log_warn "Secure Boot이 활성화되어 있습니다. Xen 설치 시 추가 설정이 필요할 수 있습니다."
            fi
        fi
    else
        log_info "Legacy BIOS 부팅 모드 감지"
    fi

    # 기존 하이퍼바이저 확인
    if systemctl is-active --quiet libvirtd 2>/dev/null; then
        log_warn "libvirt가 실행 중입니다. Xen과 충돌할 수 있습니다."
    fi

    if lsmod | grep -q kvm; then
        log_warn "KVM 모듈이 로드되어 있습니다. Xen과 동시 사용 시 문제가 발생할 수 있습니다."
    fi

    update_progress "environment_check" "COMPLETED"
    log_info "환경 검사 완료"
    return 0
}

# 의존성 해결
resolve_dependencies() {
    update_progress "dependency_resolution" "IN_PROGRESS"
    log_info "패키지 의존성 해결 시작"

    # 패키지 목록 업데이트
    log_info "패키지 목록 업데이트 중..."
    apt update || {
        log_error "패키지 목록 업데이트 실패"
        update_progress "dependency_resolution" "FAILED"
        return 1
    }

    # Ubuntu 버전별 의존성 패키지 설치
    local ubuntu_version=$(lsb_release -rs)
    local packages_to_install=()

    # 공통 패키지
    packages_to_install+=(
        "build-essential"
        "bcc"
        "bin86"
        "bison"
        "libc6-dev"
        "curl"
        "flex"
        "python3-dev"
        "python3-setuptools"
        "python3-pip"
        "python3-lxml"
        "zlib1g-dev"
        "libncurses5-dev"
        "patch"
        "libssl-dev"
        "libx11-dev"
        "pkg-config"
        "libaio-dev"
        "libglib2.0-dev"
        "libpixman-1-dev"
        "bridge-utils"
        "udev"
        "gettext"
        "iasl"
        "libbz2-dev"
        "e2fslibs-dev"
        "libfdt-dev"
        "liblzma-dev"
        "uuid-dev"
        "libyajl-dev"
    )

    # Ubuntu 22.04 특별 패키지
    if [[ "$ubuntu_version" == "22.04" ]]; then
        packages_to_install+=(
            "libzstd-dev"
            "libzstd1"
            "python3-distutils"
        )
        log_info "Ubuntu 22.04: zstd 지원 패키지 추가"
    fi

    # Ubuntu 24.04 특별 패키지
    if [[ "$ubuntu_version" == "24.04" ]]; then
        packages_to_install+=(
            "libzstd-dev"
            "libzstd1"
            "python-is-python3"
        )
        log_info "Ubuntu 24.04: Python 호환성 패키지 추가"
    fi

    # 패키지 설치
    log_info "필수 패키지 설치 중... (총 ${#packages_to_install[@]}개)"
    if ! apt install -y "${packages_to_install[@]}"; then
        log_error "패키지 설치 실패"
        update_progress "dependency_resolution" "FAILED"
        return 1
    fi

    # 패키지 상태 확인
    local failed_packages=()
    for package in "${packages_to_install[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$package "; then
            failed_packages+=("$package")
        fi
    done

    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_error "다음 패키지들이 제대로 설치되지 않았습니다: ${failed_packages[*]}"
        update_progress "dependency_resolution" "FAILED"
        return 1
    fi

    update_progress "dependency_resolution" "COMPLETED"
    log_info "의존성 해결 완료"
    return 0
}

# 드라이버 호환성 처리
handle_driver_compatibility() {
    update_progress "driver_compatibility" "IN_PROGRESS"
    log_info "드라이버 호환성 확인 및 처리 시작"

    local ubuntu_version=$(lsb_release -rs)
    local issues_found=false

    # MegaRAID 드라이버 확인 (Ubuntu 24.04에서 문제 발생)
    if [[ "$ubuntu_version" == "24.04" ]] && lspci | grep -qi "megaraid"; then
        log_warn "MegaRAID 컨트롤러가 감지되었습니다. Ubuntu 24.04에서 호환성 문제가 있을 수 있습니다."
        
        # GRUB에 IOMMU 설정 추가
        if ! grep -q "intel_iommu=on" /etc/default/grub; then
            log_info "GRUB에 IOMMU 설정 추가 중..."
            cp /etc/default/grub "$BACKUP_DIR/grub.backup.$(date +%s)"
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&intel_iommu=on iommu=pt /' /etc/default/grub
            update-grub
            issues_found=true
        fi
    fi

    # AMD 그래픽 드라이버 확인 (Ubuntu 24.04에서 문제 발생)  
    if [[ "$ubuntu_version" == "24.04" ]] && lspci | grep -i "amd.*vga\|radeon"; then
        log_warn "AMD 그래픽 카드가 감지되었습니다. Ubuntu 24.04에서 호환성 문제가 있을 수 있습니다."
        
        # nomodeset 옵션 확인 및 추가
        if ! grep -q "nomodeset" /etc/default/grub; then
            log_info "GRUB에 nomodeset 옵션 추가 중..."
            if [[ ! -f "$BACKUP_DIR/grub.backup."* ]]; then
                cp /etc/default/grub "$BACKUP_DIR/grub.backup.$(date +%s)"
            fi
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&nomodeset /' /etc/default/grub
            update-grub
            issues_found=true
        fi
    fi

    # 네트워크 브릿지 설정 확인
    if ! command -v brctl >/dev/null; then
        log_info "브릿지 유틸리티 설치 중..."
        apt install -y bridge-utils
    fi

    # 네트워크 매니저 설정 확인
    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        log_info "NetworkManager가 감지되었습니다. 브릿지 설정 최적화 중..."
        
        # NetworkManager의 브릿지 관리 비활성화
        cat > /etc/NetworkManager/conf.d/99-unmanage-bridge.conf << 'EOF'
[keyfile]
unmanaged-devices=type:bridge
EOF
        systemctl reload NetworkManager
    fi

    if [[ "$issues_found" == "true" ]]; then
        log_warn "드라이버 호환성 이슈가 발견되어 시스템 설정을 변경했습니다."
        log_warn "설치 완료 후 시스템 재부팅이 필요합니다."
    fi

    update_progress "driver_compatibility" "COMPLETED"
    log_info "드라이버 호환성 처리 완료"
    return 0
}

# Xen 설치
install_xen() {
    update_progress "xen_installation" "IN_PROGRESS"
    log_info "Xen 하이퍼바이저 설치 시작"

    local ubuntu_version=$(lsb_release -rs)

    # Ubuntu 버전별 최적 Xen 버전 선택
    local xen_version
    case "$ubuntu_version" in
        "22.04")
            xen_version="4.16"
            log_info "Ubuntu 22.04: Xen 4.16 설치 (zstd 압축 지원)"
            ;;
        "24.04")
            xen_version="4.17"
            log_info "Ubuntu 24.04: Xen 4.17 설치 (최신 호환성)"
            ;;
        *)
            log_error "지원하지 않는 Ubuntu 버전: $ubuntu_version"
            update_progress "xen_installation" "FAILED"
            return 1
            ;;
    esac

    # 기존 Xen 설치 확인 및 정리
    if dpkg -l | grep -q xen-hypervisor; then
        log_info "기존 Xen 설치가 감지되었습니다. 정리 중..."
        
        # 백업 생성
        mkdir -p "$BACKUP_DIR/xen-config"
        [[ -f /etc/xen/xl.conf ]] && cp /etc/xen/xl.conf "$BACKUP_DIR/xen-config/"
        [[ -d /etc/xen/auto ]] && cp -r /etc/xen/auto "$BACKUP_DIR/xen-config/"
        
        # 기존 Xen 제거
        apt remove --purge -y xen-hypervisor-* xen-utils-* || true
        apt autoremove -y || true
    fi

    # Xen 패키지 설치
    local xen_packages=(
        "xen-hypervisor-${xen_version}-amd64"
        "xen-utils-${xen_version}"
        "xen-tools"
        "xenstore-utils"
    )

    log_info "Xen 패키지 설치 중... (${xen_packages[*]})"
    if ! apt install -y "${xen_packages[@]}"; then
        log_error "Xen 패키지 설치 실패"
        update_progress "xen_installation" "FAILED"
        return 1
    fi

    # GRUB 설정 업데이트
    log_info "GRUB 설정 업데이트 중..."
    
    # GRUB 백업
    if [[ ! -f "$BACKUP_DIR/grub.backup."* ]]; then
        cp /etc/default/grub "$BACKUP_DIR/grub.backup.$(date +%s)"
    fi

    # Xen 최적화 GRUB 설정
    local grub_cmdline=""
    
    # 기본 Xen 옵션
    grub_cmdline+="dom0_mem=4096M,max:4096M "
    grub_cmdline+="dom0_max_vcpus=4 "
    grub_cmdline+="xen.dom0_mem=4096M "
    
    # 로깅 옵션 (4단계에서 구현할 내용을 미리 준비)
    grub_cmdline+="loglvl=all guest_loglvl=all "
    grub_cmdline+="conring_size=64k "
    
    # 하드웨어별 추가 옵션
    if grep -q "vmx" /proc/cpuinfo; then
        grub_cmdline+="hap=1 "  # Intel VT-x
    fi
    
    if grep -q "svm" /proc/cpuinfo; then
        grub_cmdline+="hap=1 "  # AMD-V
    fi

    # IOMMU 설정 (이미 추가되어 있을 수 있음)
    if ! grep -q "iommu=pt" /etc/default/grub; then
        grub_cmdline+="iommu=pt "
    fi

    # GRUB_CMDLINE_LINUX_DEFAULT에 Xen 옵션 추가
    if ! grep -q "dom0_mem" /etc/default/grub; then
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/&${grub_cmdline}/" /etc/default/grub
    fi

    # GRUB 업데이트
    update-grub || {
        log_error "GRUB 업데이트 실패"
        update_progress "xen_installation" "FAILED"
        return 1
    }

    # Xen 서비스 설정
    systemctl enable xen-qemu-dom0-disk-backend.service
    systemctl enable xen-init-dom0.service
    systemctl enable xenconsoled.service

    update_progress "xen_installation" "COMPLETED"
    log_info "Xen 설치 완료"
    return 0
}

# 설치 검증
verify_installation() {
    update_progress "verification" "IN_PROGRESS"
    log_info "설치 검증 시작"

    # Xen 패키지 설치 확인
    local required_packages=("xen-hypervisor" "xen-utils" "xen-tools")
    for package in "${required_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$package"; then
            log_error "$package 패키지가 제대로 설치되지 않았습니다."
            update_progress "verification" "FAILED"
            return 1
        fi
    done

    # GRUB 설정 확인
    if ! grep -q "xen" /boot/grub/grub.cfg; then
        log_error "GRUB 설정에 Xen 항목이 없습니다."
        update_progress "verification" "FAILED"
        return 1
    fi

    # Xen 바이너리 확인
    if [[ ! -f /boot/xen.gz ]] && [[ ! -f /boot/xen-*.gz ]]; then
        log_error "Xen 하이퍼바이저 바이너리가 /boot에 없습니다."
        update_progress "verification" "FAILED"
        return 1
    fi

    # 도구 실행 가능성 확인
    if ! command -v xl >/dev/null; then
        log_error "xl 도구를 찾을 수 없습니다."
        update_progress "verification" "FAILED"
        return 1
    fi

    # 설정 파일 확인
    if [[ ! -f /etc/xen/xl.conf ]]; then
        log_warn "/etc/xen/xl.conf 파일이 없습니다. 기본 설정을 생성합니다."
        
        cat > /etc/xen/xl.conf << 'EOF'
# Xen 기본 설정
autoballoon="auto"
run_hotplug_scripts=1
lockfile="/var/lock/xl"
vif.default.script="vif-bridge"
vif.default.bridge="xenbr0"
EOF
    fi

    update_progress "verification" "COMPLETED"
    log_info "설치 검증 완료"
    return 0
}

# 로깅 시스템 설정 (4단계 기능의 기본 설정)
setup_logging() {
    update_progress "logging_setup" "IN_PROGRESS"
    log_info "부팅 로깅 시스템 기본 설정"

    # 로그 디렉토리 생성
    mkdir -p /var/log/xen
    chmod 755 /var/log/xen

    # 직렬 콘솔 설정 (선택사항)
    read -p "직렬 콘솔 로깅을 설정하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "직렬 콘솔 설정 추가 중..."
        
        # GRUB에 직렬 콘솔 설정 추가
        if ! grep -q "console=ttyS0" /etc/default/grub; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&console=ttyS0,115200 /' /etc/default/grub
            update-grub
        fi
        
        log_info "직렬 콘솔 설정 완료. COM1 포트(115200 baud)로 로그를 수집할 수 있습니다."
    fi

    # Xen 로그 수집 스크립트 생성
    cat > /usr/local/bin/collect-xen-logs.sh << 'EOF'
#!/bin/bash
# Xen 로그 수집 스크립트

LOG_DIR="/var/log/xen"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "Xen 로그 수집 시작: $(date)"

# Xen 하이퍼바이저 로그
if command -v xl >/dev/null; then
    xl dmesg > "${LOG_DIR}/xen-dmesg-${TIMESTAMP}.log" 2>/dev/null || true
    xl info > "${LOG_DIR}/xen-info-${TIMESTAMP}.log" 2>/dev/null || true
    xl list > "${LOG_DIR}/xen-list-${TIMESTAMP}.log" 2>/dev/null || true
fi

# 시스템 로그
dmesg > "${LOG_DIR}/system-dmesg-${TIMESTAMP}.log"
journalctl -u xen* > "${LOG_DIR}/xen-services-${TIMESTAMP}.log" 2>/dev/null || true

echo "로그 수집 완료: ${LOG_DIR}/"
EOF

    chmod +x /usr/local/bin/collect-xen-logs.sh

    update_progress "logging_setup" "COMPLETED"
    log_info "기본 로깅 시스템 설정 완료"
    return 0
}

# 롤백 기능
rollback_installation() {
    log_error "설치 중 오류가 발생했습니다. 롤백을 시작합니다..."

    # GRUB 설정 복원
    if [[ -f "$BACKUP_DIR/grub.backup."* ]]; then
        local grub_backup=$(ls -t "$BACKUP_DIR"/grub.backup.* | head -n1)
        log_info "GRUB 설정 복원 중: $grub_backup"
        cp "$grub_backup" /etc/default/grub
        update-grub
    fi

    # Xen 패키지 제거
    log_info "Xen 패키지 제거 중..."
    apt remove --purge -y xen-hypervisor-* xen-utils-* xen-tools || true
    apt autoremove -y || true

    # 설치 상태 초기화
    for step in "${!INSTALL_PROGRESS[@]}"; do
        INSTALL_PROGRESS["$step"]="FAILED"
    done

    log_error "롤백이 완료되었습니다. 문제를 해결한 후 다시 시도해주세요."
}

# 설치 완료 안내
show_completion_message() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))

    echo
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}    Xen 설치가 성공적으로 완료되었습니다!    ${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo
    echo -e "${CYAN}설치 정보:${NC}"
    echo -e "  - 설치 시간: ${duration_min}분 ${duration_sec}초"
    echo -e "  - 로그 디렉토리: $LOG_DIR"
    echo -e "  - 백업 디렉토리: $BACKUP_DIR"
    echo
    echo -e "${YELLOW}다음 단계:${NC}"
    echo -e "  1. 시스템을 재부팅하세요: ${CYAN}sudo reboot${NC}"
    echo -e "  2. 재부팅 후 GRUB에서 Xen 항목을 선택하세요"
    echo -e "  3. Xen 상태 확인: ${CYAN}sudo xl info${NC}"
    echo -e "  4. 로그 수집: ${CYAN}sudo /usr/local/bin/collect-xen-logs.sh${NC}"
    echo
    echo -e "${PURPLE}추가 정보:${NC}"
    echo -e "  - Xen 관리 도구: xl, xe 명령어 사용"
    echo -e "  - 설정 파일: /etc/xen/xl.conf"
    echo -e "  - 도메인 설정: /etc/xen/auto/"
    echo
    
    # 재부팅 필요성 확인
    if [[ "${INSTALL_PROGRESS[driver_compatibility]}" == "COMPLETED" ]]; then
        echo -e "${RED}⚠️ 드라이버 호환성 설정이 변경되었습니다. 재부팅이 필요합니다.${NC}"
    fi
    
    # 사용자에게 재부팅 확인
    read -p "지금 재부팅하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "시스템을 재부팅합니다..."
        reboot
    else
        echo -e "${YELLOW}수동으로 재부팅해주세요: sudo reboot${NC}"
    fi
}

# 메인 설치 함수
main_install() {
    local step_functions=(
        "check_environment"
        "resolve_dependencies" 
        "handle_driver_compatibility"
        "install_xen"
        "verify_installation"
        "setup_logging"
    )

    for func in "${step_functions[@]}"; do
        if ! $func; then
            log_error "$func 단계에서 실패했습니다."
            rollback_installation
            return 1
        fi
        show_progress
    done

    return 0
}

# 사용법 출력
show_usage() {
    echo "사용법: $0 [옵션]"
    echo
    echo "옵션:"
    echo "  -h, --help     이 도움말 출력"
    echo "  -v, --verbose  상세한 로그 출력"
    echo "  -q, --quiet    오류만 출력"
    echo "  --dry-run      설치하지 않고 검사만 수행"
    echo
    echo "예시:"
    echo "  sudo $0                # 표준 설치"
    echo "  sudo $0 --verbose      # 상세 로그와 함께 설치"
    echo "  sudo $0 --dry-run      # 설치 가능성만 확인"
}

# 메인 함수
main() {
    # 옵션 파싱
    local dry_run=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                CURRENT_LOG_LEVEL=4
                shift
                ;;
            -q|--quiet)
                CURRENT_LOG_LEVEL=1
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                echo "알 수 없는 옵션: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # 설치 시작
    init_installer

    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN 모드: 실제 설치하지 않고 검사만 수행합니다."
        check_environment
        exit $?
    fi

    # 메인 설치 실행
    if main_install; then
        show_completion_message
    else
        log_error "설치가 실패했습니다."
        exit 1
    fi
}

# 스크립트 실행
main "$@"