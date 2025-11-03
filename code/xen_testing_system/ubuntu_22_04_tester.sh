#!/bin/bash

#==============================================================================
# Ubuntu 22.04 LTS 전용 Xen 설치 및 테스트 스크립트
# 작성자: MiniMax Agent
# 버전: 1.0
# 날짜: 2025-10-29
#
# 목적:
# - Ubuntu 22.04 LTS 환경에서 Xen 설치 전 과정 테스트
# - 버전별 특수 요구사항 검증
# - 커널 호환성 및 드라이버 이슈 확인
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
LOG_DIR="/tmp/xen_ubuntu_2204_test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"
TEST_LOG="$LOG_DIR/ubuntu_2204_test.log"
ERROR_LOG="$LOG_DIR/ubuntu_2204_errors.log"

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
# Ubuntu 22.04 특화 검증
#==============================================================================

test_ubuntu_2204_version() {
    log_info "Ubuntu 22.04 버전 확인"
    
    local version
    version=$(lsb_release -rs)
    
    if [[ "$version" == "22.04" ]]; then
        log_success "Ubuntu 22.04 LTS 확인됨"
        
        # 상세 버전 정보 로깅
        lsb_release -a >> "$TEST_LOG" 2>&1
        uname -a >> "$TEST_LOG" 2>&1
        
        return 0
    else
        log_error "예상 버전(22.04)과 다름: $version"
        return 1
    fi
}

test_ubuntu_2204_kernel_compatibility() {
    log_info "Ubuntu 22.04 커널 호환성 검사"
    
    local kernel_version
    kernel_version=$(uname -r)
    
    # Ubuntu 22.04 권장 커널 버전 (5.15.x, 5.19.x, 6.2.x)
    if [[ "$kernel_version" =~ ^5\.15\. ]] || \
       [[ "$kernel_version" =~ ^5\.19\. ]] || \
       [[ "$kernel_version" =~ ^6\.2\. ]] || \
       [[ "$kernel_version" =~ ^6\.5\. ]]; then
        log_success "호환 가능한 커널 버전: $kernel_version"
        
        # 커널 컴파일 옵션 확인
        if [[ -f "/boot/config-$kernel_version" ]]; then
            log_info "커널 설정 파일 확인"
            
            # Xen 필수 옵션들 확인
            local required_options=(
                "CONFIG_PARAVIRT=y"
                "CONFIG_PARAVIRT_GUEST=y"
                "CONFIG_XEN=y"
                "CONFIG_XEN_DOM0=y"
                "CONFIG_XEN_PVHVM=y"
            )
            
            local config_file="/boot/config-$kernel_version"
            local missing_options=()
            
            for option in "${required_options[@]}"; do
                if ! grep -q "^$option" "$config_file" 2>/dev/null; then
                    missing_options+=("$option")
                fi
            done
            
            if [[ ${#missing_options[@]} -eq 0 ]]; then
                log_success "모든 필수 Xen 커널 옵션이 활성화됨"
            else
                log_warning "누락된 커널 옵션들: ${missing_options[*]}"
                log_info "사용자 정의 커널 컴파일이 필요할 수 있음"
            fi
        fi
        
        return 0
    else
        log_warning "테스트되지 않은 커널 버전: $kernel_version"
        log_info "Xen 호환성을 추가로 확인해야 할 수 있음"
        return 1
    fi
}

test_ubuntu_2204_package_repositories() {
    log_info "Ubuntu 22.04 패키지 저장소 검사"
    
    # 기본 저장소 확인
    if apt-cache policy | grep -q "jammy"; then
        log_success "Ubuntu 22.04 (Jammy) 저장소 확인됨"
    else
        log_error "Ubuntu 22.04 저장소 설정 오류"
        return 1
    fi
    
    # Universe 저장소 활성화 확인
    if apt-cache policy | grep -q "jammy.*universe"; then
        log_success "Universe 저장소 활성화됨"
    else
        log_warning "Universe 저장소가 비활성화됨 - 활성화 중"
        add-apt-repository universe -y >> "$TEST_LOG" 2>&1
    fi
    
    # 저장소 업데이트
    log_info "패키지 목록 업데이트 중"
    if apt update >> "$TEST_LOG" 2>&1; then
        log_success "패키지 목록 업데이트 완료"
    else
        log_error "패키지 목록 업데이트 실패"
        return 1
    fi
    
    return 0
}

test_ubuntu_2204_xen_packages() {
    log_info "Ubuntu 22.04 Xen 패키지 가용성 검사"
    
    local xen_packages=(
        "xen-hypervisor-4.16-amd64"
        "xen-hypervisor-common"
        "xen-system-amd64"
        "xen-utils-4.16"
        "xen-utils-common"
        "libxen-dev"
        "libxenstore4"
    )
    
    local unavailable_packages=()
    
    for package in "${xen_packages[@]}"; do
        if apt-cache show "$package" > /dev/null 2>&1; then
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
    
    if [[ ${#unavailable_packages[@]} -eq 0 ]]; then
        log_success "모든 Xen 패키지 가용"
        return 0
    else
        log_warning "일부 패키지 불가용: ${unavailable_packages[*]}"
        log_info "대체 설치 방법 검토 필요"
        return 1
    fi
}

test_ubuntu_2204_hardware_compatibility() {
    log_info "Ubuntu 22.04 하드웨어 호환성 검사"
    
    # CPU 가상화 지원
    if grep -q -E "(vmx|svm)" /proc/cpuinfo; then
        log_success "CPU 가상화 지원 확인됨"
        
        local cpu_info
        cpu_info=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
        log_info "CPU: $cpu_info"
        
        # Intel VT-x 또는 AMD-V 확인
        if grep -q "vmx" /proc/cpuinfo; then
            log_info "Intel VT-x 지원"
        elif grep -q "svm" /proc/cpuinfo; then
            log_info "AMD-V 지원"
        fi
    else
        log_error "CPU 가상화 지원 없음 - Xen 설치 불가"
        return 1
    fi
    
    # IOMMU 지원 확인 (선택사항)
    if dmesg | grep -q -i "iommu.*enabled"; then
        log_success "IOMMU 지원 활성화됨"
    else
        log_warning "IOMMU 미활성화 - PCI 패스스루 제한됨"
    fi
    
    # 메모리 크기 확인
    local total_mem_kb
    total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$((total_mem_kb / 1024 / 1024))
    
    if [[ $total_mem_gb -ge 4 ]]; then
        log_success "충분한 메모리: ${total_mem_gb}GB"
    else
        log_warning "메모리 부족: ${total_mem_gb}GB (최소 4GB 권장)"
    fi
    
    return 0
}

test_ubuntu_2204_network_bridge_setup() {
    log_info "Ubuntu 22.04 네트워크 브리지 설정 테스트"
    
    # Netplan 설정 확인 (Ubuntu 22.04는 Netplan 사용)
    if [[ -d "/etc/netplan" ]]; then
        log_success "Netplan 설정 디렉토리 확인됨"
        
        # 기존 네트워크 설정 백업
        local backup_dir="/tmp/netplan_backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        cp -r /etc/netplan/* "$backup_dir/" 2>/dev/null || true
        log_info "기존 Netplan 설정 백업: $backup_dir"
        
        # 브리지 네트워크 테스트 설정 생성
        local test_config="/etc/netplan/99-xen-bridge-test.yaml"
        
        cat > "$test_config" << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: false
      dhcp6: false
  bridges:
    xenbr0:
      interfaces: [eth0]
      dhcp4: true
      parameters:
        stp: false
        forward-delay: 0
EOF
        
        # 설정 구문 검사
        if netplan try --timeout=5 >> "$TEST_LOG" 2>&1; then
            log_success "브리지 네트워크 설정 테스트 성공"
            
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
    
    return 0
}

test_ubuntu_2204_grub_configuration() {
    log_info "Ubuntu 22.04 GRUB 설정 테스트"
    
    # GRUB 버전 확인
    local grub_version
    grub_version=$(grub-install --version 2>/dev/null | awk '{print $3}')
    log_info "GRUB 버전: $grub_version"
    
    # GRUB 설정 파일 백업
    local grub_config="/etc/default/grub"
    local backup_file="/tmp/grub_backup_$(date +%Y%m%d_%H%M%S)"
    
    cp "$grub_config" "$backup_file"
    log_info "GRUB 설정 백업: $backup_file"
    
    # Xen 관련 GRUB 옵션 테스트
    local test_options="dom0_mem=1024M,max:1024M dom0_max_vcpus=1 dom0_vcpus_pin"
    
    # 임시 설정 적용
    if grep -q "^GRUB_CMDLINE_XEN=" "$grub_config"; then
        sed -i "s/^GRUB_CMDLINE_XEN=.*/GRUB_CMDLINE_XEN=\"$test_options\"/" "$grub_config"
    else
        echo "GRUB_CMDLINE_XEN=\"$test_options\"" >> "$grub_config"
    fi
    
    # GRUB 설정 재생성 테스트
    if update-grub >> "$TEST_LOG" 2>&1; then
        log_success "GRUB 설정 업데이트 성공"
        
        # 생성된 설정 확인
        if grep -q "xen" /boot/grub/grub.cfg; then
            log_success "Xen 부팅 옵션이 GRUB에 추가됨"
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

test_ubuntu_2204_systemd_services() {
    log_info "Ubuntu 22.04 Systemd 서비스 호환성 테스트"
    
    # Xen 관련 서비스들 확인
    local xen_services=(
        "xen-qemu-dom0-disk-backend"
        "xen-init-dom0"
        "xenconsoled"
        "xenstored"
        "xendomains"
    )
    
    local available_services=()
    local unavailable_services=()
    
    for service in "${xen_services[@]}"; do
        if systemctl list-unit-files | grep -q "$service"; then
            available_services+=("$service")
            log_success "서비스 가용: $service"
        else
            unavailable_services+=("$service")
            log_warning "서비스 불가용: $service"
        fi
    done
    
    # NetworkManager와 Netplan 충돌 확인
    if systemctl is-active --quiet NetworkManager; then
        log_warning "NetworkManager 활성화됨 - Xen 브리지와 충돌 가능"
        log_info "Netplan 사용 권장"
    else
        log_success "NetworkManager 비활성화 - 브리지 설정 안전"
    fi
    
    return 0
}

#==============================================================================
# 메인 테스트 실행
#==============================================================================

main() {
    log_info "Ubuntu 22.04 LTS Xen 설치 테스트 시작"
    log_info "로그 디렉토리: $LOG_DIR"
    
    echo "======================================" >> "$TEST_LOG"
    echo "Ubuntu 22.04 LTS Xen 테스트 리포트" >> "$TEST_LOG"
    echo "시작 시간: $(date)" >> "$TEST_LOG"
    echo "======================================" >> "$TEST_LOG"
    
    # 테스트 실행
    run_test "Ubuntu 22.04 버전 확인" "test_ubuntu_2204_version"
    run_test "커널 호환성 검사" "test_ubuntu_2204_kernel_compatibility"
    run_test "패키지 저장소 검사" "test_ubuntu_2204_package_repositories"
    run_test "Xen 패키지 가용성" "test_ubuntu_2204_xen_packages"
    run_test "하드웨어 호환성" "test_ubuntu_2204_hardware_compatibility"
    run_test "네트워크 브리지 설정" "test_ubuntu_2204_network_bridge_setup"
    run_test "GRUB 설정 테스트" "test_ubuntu_2204_grub_configuration"
    run_test "Systemd 서비스 호환성" "test_ubuntu_2204_systemd_services"
    
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
    log_info "=== Ubuntu 22.04 LTS Xen 테스트 완료 ==="
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