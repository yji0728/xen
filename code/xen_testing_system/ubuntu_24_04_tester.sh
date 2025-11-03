#!/bin/bash

#==============================================================================
# Ubuntu 24.04 LTS 전용 Xen 설치 및 테스트 스크립트
# 작성자: MiniMax Agent
# 버전: 1.0
# 날짜: 2025-10-29
#
# 목적:
# - Ubuntu 24.04 LTS 환경에서 Xen 설치 전 과정 테스트
# - 최신 버전별 특수 요구사항 검증
# - 새로운 커널 및 시스템 변경사항 대응
#==============================================================================

# 스크립트 설정
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# 색상 및 로깅 설정
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 로그 파일 설정
LOG_DIR="/tmp/xen_ubuntu_2404_test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"
TEST_LOG="$LOG_DIR/ubuntu_2404_test.log"
ERROR_LOG="$LOG_DIR/ubuntu_2404_errors.log"

# 테스트 카운터
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

#==============================================================================
# 로깅 함수들
#==============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$TEST_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$TEST_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$TEST_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$TEST_LOG" "$ERROR_LOG"
}

#==============================================================================
# 테스트 함수들
#==============================================================================

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_info "테스트 실행 중: $test_name"
    
    if eval "$test_command" >> "$TEST_LOG" 2>&1; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_success "$test_name: 통과"
        return 0
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log_error "$test_name: 실패"
        return 1
    fi
}

#==============================================================================
# Ubuntu 24.04 특화 검증
#==============================================================================

test_ubuntu_2404_version() {
    log_info "Ubuntu 24.04 버전 확인"
    
    local version
    version=$(lsb_release -rs)
    
    if [[ "$version" == "24.04" ]]; then
        log_success "Ubuntu 24.04 LTS 확인됨"
        
        # 상세 버전 정보 로깅
        lsb_release -a >> "$TEST_LOG" 2>&1
        uname -a >> "$TEST_LOG" 2>&1
        
        # Ubuntu 24.04 특정 정보
        log_info "Noble Numbat 코드명 확인"
        lsb_release -cs >> "$TEST_LOG" 2>&1
        
        return 0
    else
        log_error "예상 버전(24.04)과 다름: $version"
        return 1
    fi
}

test_ubuntu_2404_kernel_compatibility() {
    log_info "Ubuntu 24.04 커널 호환성 검사"
    
    local kernel_version
    kernel_version=$(uname -r)
    
    # Ubuntu 24.04 권장 커널 버전 (6.8.x, 6.11.x)
    if [[ "$kernel_version" =~ ^6\.8\. ]] || \
       [[ "$kernel_version" =~ ^6\.11\. ]] || \
       [[ "$kernel_version" =~ ^6\.1[0-9]\. ]]; then
        log_success "호환 가능한 커널 버전: $kernel_version"
        
        # 커널 컴파일 옵션 확인
        if [[ -f "/boot/config-$kernel_version" ]]; then
            log_info "커널 설정 파일 확인"
            
            # Xen 필수 옵션들 확인 (Ubuntu 24.04 업데이트)
            local required_options=(
                "CONFIG_PARAVIRT=y"
                "CONFIG_PARAVIRT_GUEST=y"
                "CONFIG_XEN=y"
                "CONFIG_XEN_DOM0=y"
                "CONFIG_XEN_PVHVM=y"
                "CONFIG_XEN_PVHVM_GUEST=y"
                "CONFIG_XEN_512GB=y"
                "CONFIG_XEN_SAVE_RESTORE=y"
            )
            
            local config_file="/boot/config-$kernel_version"
            local missing_options=()
            local available_options=()
            
            for option in "${required_options[@]}"; do
                if grep -q "^$option" "$config_file" 2>/dev/null; then
                    available_options+=("$option")
                else
                    missing_options+=("$option")
                fi
            done
            
            if [[ ${#missing_options[@]} -eq 0 ]]; then
                log_success "모든 필수 Xen 커널 옵션이 활성화됨"
            else
                log_warning "누락된 커널 옵션들: ${missing_options[*]}"
                log_info "사용 가능한 옵션들: ${available_options[*]}"
                log_info "사용자 정의 커널 컴파일이 필요할 수 있음"
            fi
            
            # Ubuntu 24.04 새로운 보안 기능 확인
            local security_options=(
                "CONFIG_KCONFIG_HARDENED_USERCOPY=y"
                "CONFIG_FORTIFY_SOURCE=y"
                "CONFIG_STACKPROTECTOR_STRONG=y"
            )
            
            log_info "보안 기능 확인"
            for option in "${security_options[@]}"; do
                if grep -q "^$option" "$config_file" 2>/dev/null; then
                    log_success "보안 기능 활성화: $option"
                else
                    log_info "보안 기능 미확인: $option"
                fi
            done
        fi
        
        return 0
    else
        log_warning "테스트되지 않은 커널 버전: $kernel_version"
        log_info "Ubuntu 24.04 권장 커널(6.8.x, 6.11.x)이 아님"
        log_info "Xen 호환성을 추가로 확인해야 할 수 있음"
        return 1
    fi
}

test_ubuntu_2404_package_repositories() {
    log_info "Ubuntu 24.04 패키지 저장소 검사"
    
    # 기본 저장소 확인 (Noble)
    if apt-cache policy | grep -q "noble"; then
        log_success "Ubuntu 24.04 (Noble) 저장소 확인됨"
    else
        log_error "Ubuntu 24.04 저장소 설정 오류"
        return 1
    fi
    
    # Universe 저장소 활성화 확인
    if apt-cache policy | grep -q "noble.*universe"; then
        log_success "Universe 저장소 활성화됨"
    else
        log_warning "Universe 저장소가 비활성화됨 - 활성화 중"
        add-apt-repository universe -y >> "$TEST_LOG" 2>&1
    fi
    
    # 백포트 저장소 확인 (Ubuntu 24.04 특화)
    if apt-cache policy | grep -q "noble-backports"; then
        log_success "Backports 저장소 활성화됨"
    else
        log_warning "Backports 저장소 비활성화 - 최신 Xen 패키지 제한됨"
    fi
    
    # 저장소 업데이트
    log_info "패키지 목록 업데이트 중"
    if apt update >> "$TEST_LOG" 2>&1; then
        log_success "패키지 목록 업데이트 완료"
    else
        log_error "패키지 목록 업데이트 실패"
        return 1
    fi
    
    # 패키지 관리자 버전 확인
    local apt_version
    apt_version=$(apt --version | head -1)
    log_info "APT 버전: $apt_version"
    
    return 0
}

test_ubuntu_2404_xen_packages() {
    log_info "Ubuntu 24.04 Xen 패키지 가용성 검사"
    
    # Ubuntu 24.04에서 가용한 최신 Xen 패키지들
    local xen_packages=(
        "xen-hypervisor-4.17-amd64"
        "xen-hypervisor-common"
        "xen-system-amd64"
        "xen-utils-4.17"
        "xen-utils-common"
        "libxen-dev"
        "libxenstore4"
        "libxentoollog1"
        "libxenmisc4.17"
        "xen-doc"
    )
    
    local unavailable_packages=()
    local available_packages=()
    
    for package in "${xen_packages[@]}"; do
        if apt-cache show "$package" > /dev/null 2>&1; then
            available_packages+=("$package")
            log_success "패키지 가용: $package"
            
            # 패키지 버전 정보 로깅
            echo "=== $package 정보 ===" >> "$TEST_LOG"
            apt-cache show "$package" | head -20 >> "$TEST_LOG"
            echo "" >> "$TEST_LOG"
        else
            unavailable_packages+=("$package")
            log_warning "패키지 불가용: $package"
        fi
    done
    
    # 백포트에서 최신 버전 확인
    log_info "백포트 저장소에서 최신 Xen 버전 확인"
    if apt-cache policy xen-hypervisor-amd64 | grep -q "noble-backports"; then
        log_success "백포트에서 최신 Xen 버전 제공됨"
    else
        log_info "백포트 버전 없음 - 기본 저장소 버전 사용"
    fi
    
    if [[ ${#available_packages[@]} -ge 6 ]]; then
        log_success "필수 Xen 패키지 대부분 가용 (${#available_packages[@]}/${#xen_packages[@]})"
        return 0
    else
        log_warning "일부 중요 패키지 불가용: ${unavailable_packages[*]}"
        log_info "대체 설치 방법 검토 필요"
        return 1
    fi
}

test_ubuntu_2404_hardware_compatibility() {
    log_info "Ubuntu 24.04 하드웨어 호환성 검사"
    
    # CPU 가상화 지원
    if grep -q -E "(vmx|svm)" /proc/cpuinfo; then
        log_success "CPU 가상화 지원 확인됨"
        
        local cpu_info
        cpu_info=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
        log_info "CPU: $cpu_info"
        
        # Intel VT-x 또는 AMD-V 확인
        if grep -q "vmx" /proc/cpuinfo; then
            log_info "Intel VT-x 지원"
            
            # Intel 특화 기능 확인
            if grep -q "ept" /proc/cpuinfo; then
                log_success "Intel EPT (Extended Page Tables) 지원"
            fi
            
            if grep -q "vpid" /proc/cpuinfo; then
                log_success "Intel VPID (Virtual Processor ID) 지원"
            fi
            
        elif grep -q "svm" /proc/cpuinfo; then
            log_info "AMD-V 지원"
            
            # AMD 특화 기능 확인
            if grep -q "npt" /proc/cpuinfo; then
                log_success "AMD NPT (Nested Page Tables) 지원"
            fi
        fi
    else
        log_error "CPU 가상화 지원 없음 - Xen 설치 불가"
        return 1
    fi
    
    # IOMMU 지원 확인 (Ubuntu 24.04에서 더 중요)
    if dmesg | grep -q -i "iommu.*enabled"; then
        log_success "IOMMU 지원 활성화됨"
        
        # IOMMU 그룹 확인
        if [[ -d "/sys/kernel/iommu_groups" ]]; then
            local iommu_groups
            iommu_groups=$(find /sys/kernel/iommu_groups -name "devices" | wc -l)
            log_info "IOMMU 그룹 수: $iommu_groups"
        fi
    else
        log_warning "IOMMU 미활성화 - PCI 패스스루 제한됨"
        log_info "BIOS/UEFI에서 VT-d/AMD-Vi 활성화 필요할 수 있음"
    fi
    
    # 메모리 크기 및 기능 확인
    local total_mem_kb
    total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$((total_mem_kb / 1024 / 1024))
    
    if [[ $total_mem_gb -ge 8 ]]; then
        log_success "충분한 메모리: ${total_mem_gb}GB"
    elif [[ $total_mem_gb -ge 4 ]]; then
        log_warning "메모리 제한적: ${total_mem_gb}GB (8GB 이상 권장)"
    else
        log_error "메모리 부족: ${total_mem_gb}GB (최소 4GB 필요)"
        return 1
    fi
    
    # Ubuntu 24.04 EFI 변수 접근 확인
    if [[ -d "/sys/firmware/efi" ]]; then
        log_success "UEFI 시스템 확인됨"
        
        if [[ -d "/sys/firmware/efi/efivars" ]]; then
            log_success "EFI 변수 접근 가능"
        else
            log_warning "EFI 변수 접근 제한됨"
        fi
    else
        log_info "BIOS 시스템 (Legacy Boot)"
    fi
    
    return 0
}

test_ubuntu_2404_network_bridge_setup() {
    log_info "Ubuntu 24.04 네트워크 브리지 설정 테스트"
    
    # Netplan 2.0+ 설정 확인 (Ubuntu 24.04 기본)
    if [[ -d "/etc/netplan" ]]; then
        log_success "Netplan 설정 디렉토리 확인됨"
        
        # Netplan 버전 확인
        local netplan_version
        netplan_version=$(netplan --version 2>/dev/null || echo "unknown")
        log_info "Netplan 버전: $netplan_version"
        
        # 기존 네트워크 설정 백업
        local backup_dir="/tmp/netplan_backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        cp -r /etc/netplan/* "$backup_dir/" 2>/dev/null || true
        log_info "기존 Netplan 설정 백업: $backup_dir"
        
        # Ubuntu 24.04 최신 브리지 설정 테스트
        local test_config="/etc/netplan/99-xen-bridge-test.yaml"
        
        cat > "$test_config" << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:
      dhcp4: false
      dhcp6: false
  bridges:
    xenbr0:
      interfaces: [enp0s3]
      dhcp4: true
      parameters:
        stp: false
        forward-delay: 0
        max-age: 0
        priority: 32768
EOF
        
        # 설정 구문 검사
        if netplan try --timeout=10 >> "$TEST_LOG" 2>&1; then
            log_success "브리지 네트워크 설정 테스트 성공"
            
            # 브리지 상태 확인
            if ip link show xenbr0 > /dev/null 2>&1; then
                log_success "브리지 인터페이스 생성됨"
                
                # 브리지 상세 정보
                ip addr show xenbr0 >> "$TEST_LOG" 2>&1
                bridge link show >> "$TEST_LOG" 2>&1
            fi
            
            # 설정 롤백
            rm -f "$test_config"
            netplan apply >> "$TEST_LOG" 2>&1
        else
            log_warning "브리지 네트워크 설정 테스트 실패"
            rm -f "$test_config"
            return 1
        fi
    else
        log_error "Netplan 설정 디렉토리 없음"
        return 1
    fi
    
    # NetworkManager vs Netplan 충돌 확인 (Ubuntu 24.04)
    if systemctl is-active --quiet NetworkManager; then
        log_warning "NetworkManager 활성화됨"
        
        # NetworkManager 버전 확인
        local nm_version
        nm_version=$(NetworkManager --version 2>/dev/null || echo "unknown")
        log_info "NetworkManager 버전: $nm_version"
        
        # Xen과 호환되는 설정 확인
        if nmcli connection show | grep -q bridge; then
            log_info "NetworkManager에 기존 브리지 설정 있음"
        else
            log_info "NetworkManager에 브리지 설정 없음"
        fi
    else
        log_success "NetworkManager 비활성화 - Netplan 브리지 안전"
    fi
    
    return 0
}

test_ubuntu_2404_grub_configuration() {
    log_info "Ubuntu 24.04 GRUB 설정 테스트"
    
    # GRUB 버전 확인 (Ubuntu 24.04 기본: GRUB 2.12+)
    local grub_version
    grub_version=$(grub-install --version 2>/dev/null | awk '{print $3}')
    log_info "GRUB 버전: $grub_version"
    
    # GRUB 2.12+ 새로운 기능 확인
    if [[ "$grub_version" =~ ^2\.1[2-9] ]] || [[ "$grub_version" =~ ^2\.[2-9] ]]; then
        log_success "최신 GRUB 버전 ($grub_version) - Xen 지원 향상"
    else
        log_warning "이전 GRUB 버전 ($grub_version) - 업데이트 권장"
    fi
    
    # GRUB 설정 파일 백업
    local grub_config="/etc/default/grub"
    local backup_file="/tmp/grub_backup_$(date +%Y%m%d_%H%M%S)"
    
    cp "$grub_config" "$backup_file"
    log_info "GRUB 설정 백업: $backup_file"
    
    # Ubuntu 24.04 최적화된 Xen 옵션
    local test_options="dom0_mem=2048M,max:2048M dom0_max_vcpus=2 dom0_vcpus_pin xen-pciback.hide=(01:00.0)"
    
    # 임시 설정 적용
    if grep -q "^GRUB_CMDLINE_XEN=" "$grub_config"; then
        sed -i "s/^GRUB_CMDLINE_XEN=.*/GRUB_CMDLINE_XEN=\"$test_options\"/" "$grub_config"
    else
        echo "GRUB_CMDLINE_XEN=\"$test_options\"" >> "$grub_config"
    fi
    
    # UEFI Secure Boot 고려사항 (Ubuntu 24.04)
    if [[ -d "/sys/firmware/efi" ]]; then
        log_info "UEFI 시스템 - Secure Boot 상태 확인"
        
        if bootctl status 2>/dev/null | grep -q "Secure Boot: enabled"; then
            log_warning "Secure Boot 활성화됨 - Xen 서명 확인 필요"
            log_info "mokutil을 사용하여 Xen 키 등록 필요할 수 있음"
        else
            log_success "Secure Boot 비활성화 - Xen 설치 제약 없음"
        fi
    fi
    
    # GRUB 설정 재생성 테스트
    if update-grub >> "$TEST_LOG" 2>&1; then
        log_success "GRUB 설정 업데이트 성공"
        
        # 생성된 설정 확인
        if grep -q "xen" /boot/grub/grub.cfg; then
            log_success "Xen 부팅 옵션이 GRUB에 추가됨"
            
            # Xen 메뉴 항목 수 확인
            local xen_entries
            xen_entries=$(grep -c "menuentry.*xen" /boot/grub/grub.cfg || echo "0")
            log_info "Xen 부팅 메뉴 항목: $xen_entries개"
        else
            log_warning "Xen 부팅 옵션이 GRUB에 없음"
        fi
    else
        log_error "GRUB 설정 업데이트 실패"
        cp "$backup_file" "$grub_config"
        return 1
    fi
    
    # 원본 설정 복원
    cp "$backup_file" "$grub_config"
    update-grub >> "$TEST_LOG" 2>&1
    
    return 0
}

test_ubuntu_2404_systemd_services() {
    log_info "Ubuntu 24.04 Systemd 서비스 호환성 테스트"
    
    # Systemd 버전 확인 (Ubuntu 24.04: systemd 255+)
    local systemd_version
    systemd_version=$(systemctl --version | head -1 | awk '{print $2}')
    log_info "Systemd 버전: $systemd_version"
    
    if [[ $systemd_version -ge 255 ]]; then
        log_success "최신 Systemd ($systemd_version) - Xen 서비스 지원 향상"
    else
        log_warning "이전 Systemd 버전 ($systemd_version)"
    fi
    
    # Xen 관련 서비스들 확인
    local xen_services=(
        "xen-qemu-dom0-disk-backend"
        "xen-init-dom0"
        "xenconsoled"
        "xenstored"
        "xendomains"
        "xen-watchdog"
    )
    
    local available_services=()
    local unavailable_services=()
    
    for service in "${xen_services[@]}"; do
        if systemctl list-unit-files | grep -q "$service"; then
            available_services+=("$service")
            log_success "서비스 가용: $service"
            
            # 서비스 의존성 확인
            systemctl show "$service" --property=Requires,After >> "$TEST_LOG" 2>&1
        else
            unavailable_services+=("$service")
            log_warning "서비스 불가용: $service"
        fi
    done
    
    # Ubuntu 24.04 새로운 네트워크 관리 확인
    if systemctl is-active --quiet systemd-networkd; then
        log_success "systemd-networkd 활성화 - Netplan과 잘 호환됨"
    else
        log_info "systemd-networkd 비활성화"
    fi
    
    if systemctl is-active --quiet NetworkManager; then
        log_warning "NetworkManager 활성화됨 - Xen 브리지와 충돌 가능"
        
        # NetworkManager Xen 플러그인 확인
        if dpkg -l | grep -q network-manager-xen; then
            log_success "NetworkManager Xen 플러그인 설치됨"
        else
            log_info "NetworkManager Xen 플러그인 없음"
        fi
    else
        log_success "NetworkManager 비활성화 - 브리지 설정 안전"
    fi
    
    # Ubuntu 24.04 보안 서비스 확인
    if systemctl is-active --quiet apparmor; then
        log_info "AppArmor 활성화 - Xen 프로파일 확인 필요"
        
        # Xen AppArmor 프로파일 확인
        if [[ -f "/etc/apparmor.d/usr.sbin.xend" ]] || \
           [[ -f "/etc/apparmor.d/abstractions/xen" ]]; then
            log_success "Xen AppArmor 프로파일 있음"
        else
            log_warning "Xen AppArmor 프로파일 없음 - 수동 설정 필요"
        fi
    fi
    
    return 0
}

test_ubuntu_2404_new_features() {
    log_info "Ubuntu 24.04 신규 기능 호환성 테스트"
    
    # Snap 패키지 시스템과 Xen 호환성
    if command -v snap >/dev/null 2>&1; then
        log_info "Snap 패키지 시스템 확인"
        
        if snap list | grep -q xen; then
            log_success "Xen Snap 패키지 설치됨"
        else
            log_info "Xen Snap 패키지 없음 - APT 패키지 사용 권장"
        fi
    fi
    
    # Ubuntu Pro 기능 확인
    if command -v pro >/dev/null 2>&1; then
        local pro_status
        pro_status=$(pro status --format=json 2>/dev/null | jq -r '.attached' 2>/dev/null || echo "unknown")
        
        if [[ "$pro_status" == "true" ]]; then
            log_success "Ubuntu Pro 활성화 - 확장 보안 업데이트 지원"
        else
            log_info "Ubuntu Pro 비활성화 - 일반 LTS 지원"
        fi
    fi
    
    # 새로운 패키지 형식 지원 (zstd 압축)
    if command -v zstd >/dev/null 2>&1; then
        log_success "zstd 압축 지원 - 패키지 설치 성능 향상"
    else
        log_warning "zstd 압축 미지원 - 설치 성능 제한"
    fi
    
    # 하드웨어 지원 개선 확인
    if lscpu | grep -q "AVX-512"; then
        log_success "AVX-512 지원 - 가상화 성능 향상"
    fi
    
    if lscpu | grep -q "SHA"; then
        log_success "SHA 확장 지원 - 암호화 성능 향상"
    fi
    
    return 0
}

#==============================================================================
# 메인 테스트 실행
#==============================================================================

main() {
    log_info "Ubuntu 24.04 LTS Xen 설치 테스트 시작"
    log_info "로그 디렉토리: $LOG_DIR"
    
    echo "======================================" >> "$TEST_LOG"
    echo "Ubuntu 24.04 LTS Xen 테스트 리포트" >> "$TEST_LOG"
    echo "시작 시간: $(date)" >> "$TEST_LOG"
    echo "======================================" >> "$TEST_LOG"
    
    # 테스트 실행
    run_test "Ubuntu 24.04 버전 확인" "test_ubuntu_2404_version"
    run_test "커널 호환성 검사" "test_ubuntu_2404_kernel_compatibility"
    run_test "패키지 저장소 검사" "test_ubuntu_2404_package_repositories"
    run_test "Xen 패키지 가용성" "test_ubuntu_2404_xen_packages"
    run_test "하드웨어 호환성" "test_ubuntu_2404_hardware_compatibility"
    run_test "네트워크 브리지 설정" "test_ubuntu_2404_network_bridge_setup"
    run_test "GRUB 설정 테스트" "test_ubuntu_2404_grub_configuration"
    run_test "Systemd 서비스 호환성" "test_ubuntu_2404_systemd_services"
    run_test "Ubuntu 24.04 신규 기능" "test_ubuntu_2404_new_features"
    
    # 테스트 결과 요약
    echo "" >> "$TEST_LOG"
    echo "======================================" >> "$TEST_LOG"
    echo "테스트 결과 요약" >> "$TEST_LOG"
    echo "총 테스트: $TOTAL_TESTS" >> "$TEST_LOG"
    echo "성공: $PASSED_TESTS" >> "$TEST_LOG"
    echo "실패: $FAILED_TESTS" >> "$TEST_LOG"
    echo "성공률: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%" >> "$TEST_LOG"
    echo "완료 시간: $(date)" >> "$TEST_LOG"
    echo "======================================" >> "$TEST_LOG"
    
    # 결과 출력
    echo ""
    log_info "=== Ubuntu 24.04 LTS Xen 테스트 완료 ==="
    log_info "총 테스트: $TOTAL_TESTS"
    log_success "성공: $PASSED_TESTS"
    log_error "실패: $FAILED_TESTS"
    log_info "성공률: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    
    echo ""
    log_info "상세 로그: $TEST_LOG"
    if [[ -s "$ERROR_LOG" ]]; then
        log_info "오류 로그: $ERROR_LOG"
    fi
    
    # 실패한 테스트가 있으면 에러 코드 반환
    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi