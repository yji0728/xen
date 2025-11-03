#!/bin/bash

#==============================================================================
# 하드웨어 환경별 Xen 호환성 테스트 스크립트
# 작성자: MiniMax Agent
# 버전: 1.0
# 날짜: 2025-10-29
#
# 목적:
# - 다양한 하드웨어 환경에서 Xen 설치 호환성 검증
# - Intel/AMD CPU별 최적화 옵션 테스트
# - 네트워크/스토리지/그래픽 하드웨어 호환성 확인
#==============================================================================

# 스크립트 설정
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# 색상 및 로깅 설정
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 로그 파일 설정
LOG_DIR="/tmp/xen_hardware_compatibility_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"
TEST_LOG="$LOG_DIR/hardware_compatibility.log"
ERROR_LOG="$LOG_DIR/hardware_errors.log"
HARDWARE_REPORT="$LOG_DIR/hardware_report.json"

# 테스트 카운터
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# 하드웨어 정보 저장
declare -A HARDWARE_INFO

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

log_hardware() {
    echo -e "${PURPLE}[HARDWARE]${NC} $1" | tee -a "$TEST_LOG"
}

#==============================================================================
# 테스트 함수들
#==============================================================================

run_test() {
    local test_name="$1"
    local test_command="$2"
    local optional="${3:-false}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_info "테스트 실행 중: $test_name"
    
    if eval "$test_command" >> "$TEST_LOG" 2>&1; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_success "$test_name: 통과"
        return 0
    else
        if [[ "$optional" == "true" ]]; then
            WARNING_TESTS=$((WARNING_TESTS + 1))
            log_warning "$test_name: 선택적 기능 실패"
            return 0
        else
            FAILED_TESTS=$((FAILED_TESTS + 1))
            log_error "$test_name: 실패"
            return 1
        fi
    fi
}

#==============================================================================
# 하드웨어 정보 수집
#==============================================================================

collect_hardware_info() {
    log_info "하드웨어 정보 수집 중"
    
    # CPU 정보
    HARDWARE_INFO[cpu_vendor]=$(lscpu | grep "Vendor ID" | awk '{print $3}' || echo "unknown")
    HARDWARE_INFO[cpu_model]=$(lscpu | grep "Model name" | cut -d: -f2 | xargs || echo "unknown")
    HARDWARE_INFO[cpu_cores]=$(nproc)
    HARDWARE_INFO[cpu_threads]=$(lscpu | grep "CPU(s):" | head -1 | awk '{print $2}')
    
    # 메모리 정보
    HARDWARE_INFO[total_memory]=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    HARDWARE_INFO[available_memory]=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    
    # 시스템 정보
    HARDWARE_INFO[system_vendor]=$(dmidecode -s system-manufacturer 2>/dev/null | head -1 || echo "unknown")
    HARDWARE_INFO[system_model]=$(dmidecode -s system-product-name 2>/dev/null | head -1 || echo "unknown")
    HARDWARE_INFO[bios_vendor]=$(dmidecode -s bios-vendor 2>/dev/null | head -1 || echo "unknown")
    HARDWARE_INFO[bios_version]=$(dmidecode -s bios-version 2>/dev/null | head -1 || echo "unknown")
    
    # 부팅 모드
    if [[ -d "/sys/firmware/efi" ]]; then
        HARDWARE_INFO[boot_mode]="UEFI"
    else
        HARDWARE_INFO[boot_mode]="BIOS"
    fi
    
    # 네트워크 어댑터
    HARDWARE_INFO[network_adapters]=$(lspci | grep -i ethernet | wc -l)
    HARDWARE_INFO[wifi_adapters]=$(lspci | grep -i wireless | wc -l)
    
    # 스토리지 컨트롤러
    HARDWARE_INFO[storage_controllers]=$(lspci | grep -i -E "(sata|scsi|raid)" | wc -l)
    
    # 그래픽 카드
    HARDWARE_INFO[graphics_cards]=$(lspci | grep -i vga | wc -l)
    
    # 가상화 기능
    if grep -q "vmx" /proc/cpuinfo; then
        HARDWARE_INFO[virtualization]="Intel VT-x"
    elif grep -q "svm" /proc/cpuinfo; then
        HARDWARE_INFO[virtualization]="AMD-V"
    else
        HARDWARE_INFO[virtualization]="none"
    fi
    
    log_hardware "CPU: ${HARDWARE_INFO[cpu_vendor]} ${HARDWARE_INFO[cpu_model]}"
    log_hardware "코어: ${HARDWARE_INFO[cpu_cores]}, 스레드: ${HARDWARE_INFO[cpu_threads]}"
    log_hardware "메모리: $((${HARDWARE_INFO[total_memory]} / 1024 / 1024))GB"
    log_hardware "시스템: ${HARDWARE_INFO[system_vendor]} ${HARDWARE_INFO[system_model]}"
    log_hardware "부팅 모드: ${HARDWARE_INFO[boot_mode]}"
    log_hardware "가상화: ${HARDWARE_INFO[virtualization]}"
    
    return 0
}

#==============================================================================
# CPU별 호환성 테스트
#==============================================================================

test_intel_cpu_compatibility() {
    log_info "Intel CPU 특화 기능 테스트"
    
    if [[ "${HARDWARE_INFO[cpu_vendor]}" != "GenuineIntel" ]]; then
        log_info "Intel CPU가 아님 - 테스트 스킵"
        return 0
    fi
    
    # Intel VT-x 확인
    if grep -q "vmx" /proc/cpuinfo; then
        log_success "Intel VT-x 지원 확인됨"
        
        # EPT (Extended Page Tables) 확인
        if grep -q "ept" /proc/cpuinfo; then
            log_success "Intel EPT 지원 - 메모리 가상화 성능 향상"
        else
            log_warning "Intel EPT 미지원 - 성능 제한 가능"
        fi
        
        # VPID (Virtual Processor Identifier) 확인
        if grep -q "vpid" /proc/cpuinfo; then
            log_success "Intel VPID 지원 - TLB 성능 향상"
        else
            log_warning "Intel VPID 미지원"
        fi
        
        # VT-d (Intel IOMMU) 확인
        if dmesg | grep -q -i "intel.*iommu"; then
            log_success "Intel VT-d (IOMMU) 지원"
            
            # IOMMU 그룹 확인
            if [[ -d "/sys/kernel/iommu_groups" ]]; then
                local iommu_groups
                iommu_groups=$(find /sys/kernel/iommu_groups -name "devices" | wc -l)
                log_info "IOMMU 그룹: $iommu_groups개"
            fi
        else
            log_warning "Intel VT-d 미활성화 - PCI 패스스루 제한"
        fi
        
        # Intel TSX 확인 (선택적)
        if grep -q "rtm" /proc/cpuinfo; then
            log_success "Intel TSX 지원 - 트랜잭션 메모리"
        fi
        
    else
        log_error "Intel VT-x 미지원 - Xen 설치 불가"
        return 1
    fi
    
    return 0
}

test_amd_cpu_compatibility() {
    log_info "AMD CPU 특화 기능 테스트"
    
    if [[ "${HARDWARE_INFO[cpu_vendor]}" != "AuthenticAMD" ]]; then
        log_info "AMD CPU가 아님 - 테스트 스킵"
        return 0
    fi
    
    # AMD-V (SVM) 확인
    if grep -q "svm" /proc/cpuinfo; then
        log_success "AMD-V (SVM) 지원 확인됨"
        
        # NPT (Nested Page Tables) 확인
        if grep -q "npt" /proc/cpuinfo; then
            log_success "AMD NPT 지원 - 메모리 가상화 성능 향상"
        else
            log_warning "AMD NPT 미지원 - 성능 제한 가능"
        fi
        
        # AVIC (Advanced Virtual Interrupt Controller) 확인
        if grep -q "avic" /proc/cpuinfo; then
            log_success "AMD AVIC 지원 - 인터럽트 가상화 성능 향상"
        else
            log_info "AMD AVIC 미지원 (최신 CPU에서 지원)"
        fi
        
        # AMD-Vi (AMD IOMMU) 확인
        if dmesg | grep -q -i "amd.*iommu"; then
            log_success "AMD-Vi (IOMMU) 지원"
        else
            log_warning "AMD-Vi 미활성화 - PCI 패스스루 제한"
        fi
        
        # AMD SME/SEV 확인 (선택적)
        if grep -q "sme" /proc/cpuinfo; then
            log_success "AMD SME (Secure Memory Encryption) 지원"
        fi
        
        if grep -q "sev" /proc/cpuinfo; then
            log_success "AMD SEV (Secure Encrypted Virtualization) 지원"
        fi
        
    else
        log_error "AMD-V 미지원 - Xen 설치 불가"
        return 1
    fi
    
    return 0
}

#==============================================================================
# 메모리 호환성 테스트
#==============================================================================

test_memory_compatibility() {
    log_info "메모리 호환성 테스트"
    
    local total_mem_gb=$((${HARDWARE_INFO[total_memory]} / 1024 / 1024))
    local available_mem_gb=$((${HARDWARE_INFO[available_memory]} / 1024 / 1024))
    
    # 최소 메모리 요구사항
    if [[ $total_mem_gb -ge 8 ]]; then
        log_success "메모리 충분: ${total_mem_gb}GB (권장: 8GB+)"
    elif [[ $total_mem_gb -ge 4 ]]; then
        log_warning "메모리 제한적: ${total_mem_gb}GB (최소: 4GB)"
    else
        log_error "메모리 부족: ${total_mem_gb}GB (Xen Dom0 + 게스트 VM 운영 어려움)"
        return 1
    fi
    
    # 대용량 페이지 지원 확인
    if grep -q "pdpe1gb" /proc/cpuinfo; then
        log_success "1GB 대용량 페이지 지원 - 메모리 성능 향상"
    else
        log_info "1GB 대용량 페이지 미지원"
    fi
    
    if grep -q "pse" /proc/cpuinfo; then
        log_success "2MB 대용량 페이지 지원"
    else
        log_warning "대용량 페이지 미지원 - 성능 저하 가능"
    fi
    
    # NUMA 토폴로지 확인
    if command -v numactl >/dev/null 2>&1; then
        local numa_nodes
        numa_nodes=$(numactl --hardware | grep "available:" | awk '{print $2}')
        
        if [[ $numa_nodes -gt 1 ]]; then
            log_success "NUMA 시스템: $numa_nodes 노드 - Xen NUMA 최적화 가능"
            
            # NUMA 밸런싱 확인
            if [[ -f "/proc/sys/kernel/numa_balancing" ]]; then
                local numa_balancing
                numa_balancing=$(cat /proc/sys/kernel/numa_balancing)
                if [[ $numa_balancing -eq 1 ]]; then
                    log_info "NUMA 자동 밸런싱 활성화"
                else
                    log_info "NUMA 자동 밸런싱 비활성화"
                fi
            fi
        else
            log_info "단일 NUMA 노드 시스템"
        fi
    else
        log_info "NUMA 도구 미설치 - 설치 권장: apt install numactl"
    fi
    
    # 메모리 오버커밋 설정 확인
    local overcommit_memory
    overcommit_memory=$(cat /proc/sys/vm/overcommit_memory)
    case $overcommit_memory in
        0) log_info "메모리 오버커밋: 휴리스틱 모드" ;;
        1) log_warning "메모리 오버커밋: 항상 허용 - Xen에서 주의 필요" ;;
        2) log_success "메모리 오버커밋: 엄격 모드 - Xen에 적합" ;;
        *) log_info "메모리 오버커밋: 알 수 없음 ($overcommit_memory)" ;;
    esac
    
    return 0
}

#==============================================================================
# 네트워크 하드웨어 호환성
#==============================================================================

test_network_hardware_compatibility() {
    log_info "네트워크 하드웨어 호환성 테스트"
    
    # 네트워크 어댑터 목록
    log_info "네트워크 어댑터 탐지"
    lspci | grep -i ethernet >> "$TEST_LOG"
    
    local ethernet_adapters
    ethernet_adapters=$(lspci | grep -i ethernet)
    
    if [[ -z "$ethernet_adapters" ]]; then
        log_error "이더넷 어댑터를 찾을 수 없음"
        return 1
    fi
    
    log_success "${HARDWARE_INFO[network_adapters]}개 이더넷 어댑터 발견"
    
    # 브리지 지원 네트워크 드라이버 확인
    local bridge_compatible_drivers=(
        "e1000e"
        "igb"
        "ixgbe"
        "i40e"
        "ice"
        "virtio_net"
        "vmxnet3"
        "r8169"
        "tg3"
        "bnx2"
        "sky2"
    )
    
    local active_drivers=()
    for adapter in $(ls /sys/class/net/ | grep -v lo); do
        if [[ -d "/sys/class/net/$adapter/device/driver" ]]; then
            local driver
            driver=$(basename $(readlink /sys/class/net/$adapter/device/driver))
            active_drivers+=("$driver")
            
            log_info "네트워크 인터페이스 $adapter: 드라이버 $driver"
            
            # 브리지 호환성 확인
            if printf '%s\n' "${bridge_compatible_drivers[@]}" | grep -q "^$driver$"; then
                log_success "드라이버 $driver: Xen 브리지 호환"
            else
                log_warning "드라이버 $driver: 브리지 호환성 미확인 - 테스트 필요"
            fi
            
            # SR-IOV 지원 확인
            if [[ -f "/sys/class/net/$adapter/device/sriov_totalvfs" ]]; then
                local sriov_vfs
                sriov_vfs=$(cat "/sys/class/net/$adapter/device/sriov_totalvfs")
                if [[ $sriov_vfs -gt 0 ]]; then
                    log_success "인터페이스 $adapter: SR-IOV 지원 ($sriov_vfs VFs)"
                fi
            fi
        fi
    done
    
    # 무선 어댑터 확인 (일반적으로 Xen에서 사용 안함)
    if [[ ${HARDWARE_INFO[wifi_adapters]} -gt 0 ]]; then
        log_info "${HARDWARE_INFO[wifi_adapters]}개 무선 어댑터 발견 (Xen에서 일반적으로 미사용)"
    fi
    
    return 0
}

#==============================================================================
# 스토리지 하드웨어 호환성
#==============================================================================

test_storage_hardware_compatibility() {
    log_info "스토리지 하드웨어 호환성 테스트"
    
    # 스토리지 컨트롤러 목록
    log_info "스토리지 컨트롤러 탐지"
    lspci | grep -i -E "(sata|scsi|raid|nvme)" >> "$TEST_LOG"
    
    # RAID 컨트롤러 특별 확인
    local raid_controllers
    raid_controllers=$(lspci | grep -i raid)
    
    if [[ -n "$raid_controllers" ]]; then
        log_warning "RAID 컨트롤러 발견 - Xen 호환성 확인 필요"
        echo "RAID 컨트롤러:" >> "$TEST_LOG"
        echo "$raid_controllers" >> "$TEST_LOG"
        
        # MegaRAID 특별 확인
        if echo "$raid_controllers" | grep -q -i "megaraid\|lsi"; then
            log_warning "MegaRAID 컨트롤러 - 드라이버 호환성 이슈 가능"
            log_info "megasas 드라이버 확인 권장"
        fi
    fi
    
    # NVMe 드라이브 확인
    local nvme_drives
    nvme_drives=$(lspci | grep -i nvme | wc -l)
    
    if [[ $nvme_drives -gt 0 ]]; then
        log_success "$nvme_drives개 NVMe 드라이브 - 고성능 스토리지"
        
        # NVMe 네임스페이스 확인
        if command -v nvme >/dev/null 2>&1; then
            log_info "NVMe 세부 정보:"
            nvme list >> "$TEST_LOG" 2>&1 || true
        fi
    fi
    
    # 스토리지 드라이버 호환성
    local storage_drivers=(
        "ahci"
        "nvme"
        "megaraid_sas"
        "mpt3sas"
        "vmw_pvscsi"
        "virtio_blk"
        "xen-blkfront"
    )
    
    log_info "활성 스토리지 드라이버 확인"
    for driver in "${storage_drivers[@]}"; do
        if lsmod | grep -q "$driver"; then
            log_success "드라이버 로드됨: $driver"
        else
            log_info "드라이버 미로드: $driver"
        fi
    done
    
    # 가상 환경 스토리지 확인
    if lsmod | grep -q "xen-blkfront"; then
        log_success "Xen 블록 프론트엔드 드라이버 활성 - 가상 환경"
    elif lsmod | grep -q "virtio_blk"; then
        log_info "VirtIO 블록 드라이버 활성 - KVM/QEMU 환경"
    fi
    
    return 0
}

#==============================================================================
# 그래픽 하드웨어 호환성
#==============================================================================

test_graphics_hardware_compatibility() {
    log_info "그래픽 하드웨어 호환성 테스트"
    
    # 그래픽 카드 목록
    log_info "그래픽 카드 탐지"
    lspci | grep -i vga >> "$TEST_LOG"
    
    local graphics_cards
    graphics_cards=$(lspci | grep -i vga)
    
    if [[ -z "$graphics_cards" ]]; then
        log_warning "전용 그래픽 카드 없음 - 통합 그래픽 사용"
    else
        log_success "${HARDWARE_INFO[graphics_cards]}개 그래픽 카드 발견"
    fi
    
    # GPU 패스스루 지원 확인
    local gpu_passthrough_capable=false
    
    # NVIDIA GPU 확인
    if lspci | grep -qi nvidia; then
        log_info "NVIDIA GPU 발견"
        
        # NVIDIA 드라이버 확인
        if command -v nvidia-smi >/dev/null 2>&1; then
            log_success "NVIDIA 드라이버 설치됨"
            nvidia-smi >> "$TEST_LOG" 2>&1 || true
            
            # IOMMU 그룹 확인 (GPU 패스스루용)
            local nvidia_iommu_groups=0
            for gpu_device in $(lspci | grep -i nvidia | cut -d' ' -f1); do
                if [[ -L "/sys/bus/pci/devices/0000:$gpu_device/iommu_group" ]]; then
                    nvidia_iommu_groups=$((nvidia_iommu_groups + 1))
                fi
            done
            
            if [[ $nvidia_iommu_groups -gt 0 ]]; then
                log_success "NVIDIA GPU IOMMU 그룹 설정됨 - 패스스루 가능"
                gpu_passthrough_capable=true
            else
                log_warning "NVIDIA GPU IOMMU 그룹 없음 - 패스스루 제한"
            fi
        else
            log_warning "NVIDIA 드라이버 미설치 - nouveau 드라이버 사용 중"
        fi
    fi
    
    # AMD GPU 확인
    if lspci | grep -qi -E "(radeon|amd)"; then
        log_info "AMD GPU 발견"
        
        # AMD 드라이버 확인
        if lsmod | grep -q amdgpu; then
            log_success "AMDGPU 드라이버 로드됨"
        elif lsmod | grep -q radeon; then
            log_info "Radeon 레거시 드라이버 로드됨"
        else
            log_warning "AMD GPU 드라이버 미확인"
        fi
    fi
    
    # Intel 통합 그래픽 확인
    if lspci | grep -qi intel; then
        log_info "Intel 통합 그래픽 발견"
        
        if lsmod | grep -q i915; then
            log_success "Intel i915 드라이버 로드됨"
        else
            log_info "Intel 그래픽 드라이버 미확인"
        fi
    fi
    
    # 헤드리스 서버 모드 확인
    if ! command -v Xorg >/dev/null 2>&1 && [[ ! -f "/usr/bin/X" ]]; then
        log_success "헤드리스 서버 환경 - Xen Dom0에 적합"
    else
        log_info "GUI 환경 - Xen Dom0에서 리소스 사용량 고려 필요"
    fi
    
    return 0
}

#==============================================================================
# 가상화 환경 감지
#==============================================================================

test_virtualization_environment() {
    log_info "가상화 환경 감지"
    
    local virt_env="물리적 하드웨어"
    
    # systemd-detect-virt 사용
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        local detected_virt
        detected_virt=$(systemd-detect-virt 2>/dev/null || echo "none")
        
        case "$detected_virt" in
            "none") 
                log_success "물리적 하드웨어에서 실행 중"
                virt_env="물리적 하드웨어"
                ;;
            "xen")
                log_warning "Xen 게스트에서 실행 중 - 중첩 가상화"
                virt_env="Xen 게스트"
                ;;
            "kvm")
                log_warning "KVM 게스트에서 실행 중 - 중첩 가상화 제한"
                virt_env="KVM 게스트"
                ;;
            "vmware")
                log_warning "VMware 게스트에서 실행 중"
                virt_env="VMware 게스트"
                ;;
            "virtualbox")
                log_warning "VirtualBox 게스트에서 실행 중"
                virt_env="VirtualBox 게스트"
                ;;
            *)
                log_info "가상화 환경 감지됨: $detected_virt"
                virt_env="$detected_virt 게스트"
                ;;
        esac
    fi
    
    # DMI 정보로 추가 확인
    local system_vendor="${HARDWARE_INFO[system_vendor]}"
    case "$system_vendor" in
        *"VMware"*)
            log_info "DMI 정보: VMware 가상 머신"
            ;;
        *"innotek"*|*"VirtualBox"*)
            log_info "DMI 정보: VirtualBox 가상 머신"
            ;;
        *"Xen"*)
            log_info "DMI 정보: Xen 가상 머신"
            ;;
        *"QEMU"*)
            log_info "DMI 정보: QEMU/KVM 가상 머신"
            ;;
        *"Microsoft"*)
            log_info "DMI 정보: Hyper-V 가상 머신"
            ;;
    esac
    
    HARDWARE_INFO[virt_env]="$virt_env"
    
    # 중첩 가상화 경고
    if [[ "$virt_env" != "물리적 하드웨어" ]]; then
        log_warning "가상 환경에서 Xen 설치 시 중첩 가상화 제한 있음"
        log_info "호스트에서 중첩 가상화 활성화 필요할 수 있음"
    fi
    
    return 0
}

#==============================================================================
# 전력 관리 호환성
#==============================================================================

test_power_management_compatibility() {
    log_info "전력 관리 호환성 테스트"
    
    # CPU 주파수 조절 확인
    if [[ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]]; then
        log_success "CPU 주파수 조절 지원됨"
        
        local governor
        governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
        log_info "현재 CPU 거버너: $governor"
        
        # Xen에 적합한 거버너 확인
        case "$governor" in
            "performance")
                log_success "고성능 거버너 - Xen Dom0에 적합"
                ;;
            "powersave")
                log_warning "절전 거버너 - 성능 저하 가능"
                ;;
            "ondemand"|"conservative")
                log_info "동적 거버너 - 적절한 설정"
                ;;
            *)
                log_info "알 수 없는 거버너: $governor"
                ;;
        esac
    else
        log_info "CPU 주파수 조절 미지원"
    fi
    
    # C-states 확인
    if [[ -f "/proc/cpuinfo" ]] && grep -q "cx" /proc/cpuinfo; then
        log_success "CPU C-states 지원"
        
        # Xen에서 C-states 제어 확인
        if dmesg | grep -q "xen.*c-state"; then
            log_success "Xen C-states 제어 활성화"
        else
            log_info "Xen C-states 제어 미확인"
        fi
    fi
    
    # ACPI 지원 확인
    if [[ -d "/sys/firmware/acpi" ]]; then
        log_success "ACPI 지원됨"
        
        # ACPI 테이블 확인
        if [[ -d "/sys/firmware/acpi/tables" ]]; then
            local acpi_tables
            acpi_tables=$(ls /sys/firmware/acpi/tables/ | wc -l)
            log_info "ACPI 테이블: $acpi_tables개"
        fi
    else
        log_warning "ACPI 미지원 - 전력 관리 제한"
    fi
    
    return 0
}

#==============================================================================
# JSON 리포트 생성
#==============================================================================

generate_hardware_report() {
    log_info "하드웨어 호환성 리포트 생성"
    
    cat > "$HARDWARE_REPORT" << EOF
{
  "test_info": {
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "kernel": "$(uname -r)",
    "distribution": "$(lsb_release -ds 2>/dev/null || echo 'Unknown')"
  },
  "hardware_info": {
    "cpu": {
      "vendor": "${HARDWARE_INFO[cpu_vendor]}",
      "model": "${HARDWARE_INFO[cpu_model]}",
      "cores": ${HARDWARE_INFO[cpu_cores]},
      "threads": ${HARDWARE_INFO[cpu_threads]},
      "virtualization": "${HARDWARE_INFO[virtualization]}"
    },
    "memory": {
      "total_gb": $((${HARDWARE_INFO[total_memory]} / 1024 / 1024)),
      "available_gb": $((${HARDWARE_INFO[available_memory]} / 1024 / 1024))
    },
    "system": {
      "vendor": "${HARDWARE_INFO[system_vendor]}",
      "model": "${HARDWARE_INFO[system_model]}",
      "bios_vendor": "${HARDWARE_INFO[bios_vendor]}",
      "bios_version": "${HARDWARE_INFO[bios_version]}",
      "boot_mode": "${HARDWARE_INFO[boot_mode]}",
      "virtualization_environment": "${HARDWARE_INFO[virt_env]}"
    },
    "network": {
      "ethernet_adapters": ${HARDWARE_INFO[network_adapters]},
      "wifi_adapters": ${HARDWARE_INFO[wifi_adapters]}
    },
    "storage": {
      "controllers": ${HARDWARE_INFO[storage_controllers]}
    },
    "graphics": {
      "cards": ${HARDWARE_INFO[graphics_cards]}
    }
  },
  "test_results": {
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "warning_tests": $WARNING_TESTS,
    "success_rate": $(( (PASSED_TESTS + WARNING_TESTS) * 100 / TOTAL_TESTS ))
  }
}
EOF

    log_success "하드웨어 리포트 생성됨: $HARDWARE_REPORT"
}

#==============================================================================
# 메인 테스트 실행
#==============================================================================

main() {
    log_info "하드웨어 호환성 테스트 시작"
    log_info "로그 디렉토리: $LOG_DIR"
    
    echo "======================================" >> "$TEST_LOG"
    echo "하드웨어 호환성 테스트 리포트" >> "$TEST_LOG"
    echo "시작 시간: $(date)" >> "$TEST_LOG"
    echo "======================================" >> "$TEST_LOG"
    
    # 하드웨어 정보 수집
    collect_hardware_info
    
    # 테스트 실행
    run_test "Intel CPU 호환성" "test_intel_cpu_compatibility" "true"
    run_test "AMD CPU 호환성" "test_amd_cpu_compatibility" "true"
    run_test "메모리 호환성" "test_memory_compatibility"
    run_test "네트워크 하드웨어" "test_network_hardware_compatibility"
    run_test "스토리지 하드웨어" "test_storage_hardware_compatibility"
    run_test "그래픽 하드웨어" "test_graphics_hardware_compatibility" "true"
    run_test "가상화 환경 감지" "test_virtualization_environment"
    run_test "전력 관리" "test_power_management_compatibility" "true"
    
    # 리포트 생성
    generate_hardware_report
    
    # 테스트 결과 요약
    echo "" >> "$TEST_LOG"
    echo "======================================" >> "$TEST_LOG"
    echo "테스트 결과 요약" >> "$TEST_LOG"
    echo "총 테스트: $TOTAL_TESTS" >> "$TEST_LOG"
    echo "성공: $PASSED_TESTS" >> "$TEST_LOG"
    echo "실패: $FAILED_TESTS" >> "$TEST_LOG"
    echo "경고: $WARNING_TESTS" >> "$TEST_LOG"
    echo "성공률: $(( (PASSED_TESTS + WARNING_TESTS) * 100 / TOTAL_TESTS ))%" >> "$TEST_LOG"
    echo "완료 시간: $(date)" >> "$TEST_LOG"
    echo "======================================" >> "$TEST_LOG"
    
    # 결과 출력
    echo ""
    log_info "=== 하드웨어 호환성 테스트 완료 ==="
    log_info "총 테스트: $TOTAL_TESTS"
    log_success "성공: $PASSED_TESTS"
    log_error "실패: $FAILED_TESTS"
    log_warning "경고: $WARNING_TESTS"
    log_info "성공률: $(( (PASSED_TESTS + WARNING_TESTS) * 100 / TOTAL_TESTS ))%"
    
    echo ""
    log_info "상세 로그: $TEST_LOG"
    log_info "하드웨어 리포트: $HARDWARE_REPORT"
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