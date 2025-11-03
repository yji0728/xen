#!/bin/bash

# Ubuntu 드라이버 호환성 롤백 및 복구 스크립트
# 작성자: MiniMax Agent
# 버전: 1.0
# 사용법: sudo ./rollback_recovery.sh [백업_디렉토리]

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

# 백업 디렉토리 찾기
find_backup_directories() {
    log_info "백업 디렉토리 검색 중..."
    
    # 가능한 백업 디렉토리들
    BACKUP_DIRS=(
        "/root/driver-compatibility-backup-"*
        "/root/network-backup-"*
        "/root/graphics-backup-"*
    )
    
    FOUND_BACKUPS=()
    for pattern in "${BACKUP_DIRS[@]}"; do
        for dir in $pattern; do
            if [[ -d "$dir" ]]; then
                FOUND_BACKUPS+=("$dir")
            fi
        done
    done
    
    if [[ ${#FOUND_BACKUPS[@]} -eq 0 ]]; then
        log_error "백업 디렉토리를 찾을 수 없습니다."
        return 1
    fi
    
    log_success "발견된 백업 디렉토리:"
    for i in "${!FOUND_BACKUPS[@]}"; do
        echo "  $((i+1)). ${FOUND_BACKUPS[i]}"
    done
    
    return 0
}

# 백업 디렉토리 선택
select_backup_directory() {
    if [[ $# -eq 1 ]] && [[ -d "$1" ]]; then
        SELECTED_BACKUP="$1"
        log_info "지정된 백업 디렉토리 사용: $SELECTED_BACKUP"
        return 0
    fi
    
    if ! find_backup_directories; then
        return 1
    fi
    
    echo
    read -p "복원할 백업을 선택하세요 (1-${#FOUND_BACKUPS[@]}): " -r selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#FOUND_BACKUPS[@]} ]]; then
        SELECTED_BACKUP="${FOUND_BACKUPS[$((selection-1))]}"
        log_success "선택된 백업: $SELECTED_BACKUP"
        return 0
    else
        log_error "잘못된 선택입니다."
        return 1
    fi
}

# 백업 내용 분석
analyze_backup() {
    log_info "백업 내용 분석 중..."
    
    if [[ ! -d "$SELECTED_BACKUP" ]]; then
        log_error "백업 디렉토리가 존재하지 않습니다: $SELECTED_BACKUP"
        return 1
    fi
    
    echo "=== 백업 디렉토리 내용 ==="
    ls -la "$SELECTED_BACKUP"
    echo
    
    # 백업 타입 확인
    BACKUP_TYPE=""
    if [[ -f "$SELECTED_BACKUP/grub.backup" ]]; then
        BACKUP_TYPE="${BACKUP_TYPE}grub "
        log_info "GRUB 백업이 발견되었습니다."
    fi
    
    if [[ -d "$SELECTED_BACKUP/netplan" ]]; then
        BACKUP_TYPE="${BACKUP_TYPE}network "
        log_info "네트워크 백업이 발견되었습니다."
    fi
    
    if [[ -f "$SELECTED_BACKUP/firefox_prefs.js.backup" ]]; then
        BACKUP_TYPE="${BACKUP_TYPE}browser "
        log_info "브라우저 설정 백업이 발견되었습니다."
    fi
    
    if [[ -f "$SELECTED_BACKUP/gdm3_custom.conf.backup" ]]; then
        BACKUP_TYPE="${BACKUP_TYPE}display "
        log_info "디스플레이 서버 백업이 발견되었습니다."
    fi
    
    if [[ -z "$BACKUP_TYPE" ]]; then
        log_warn "알려진 백업 파일을 찾을 수 없습니다."
        return 1
    fi
    
    log_success "감지된 백업 타입: $BACKUP_TYPE"
    return 0
}

# GRUB 복원
restore_grub() {
    if [[ -f "$SELECTED_BACKUP/grub.backup" ]]; then
        log_info "GRUB 구성 복원 중..."
        
        # 현재 GRUB 백업
        cp /etc/default/grub "/etc/default/grub.pre-restore-$(date +%Y%m%d-%H%M%S)"
        
        # 백업에서 복원
        cp "$SELECTED_BACKUP/grub.backup" /etc/default/grub
        
        # GRUB 업데이트
        if command -v update-grub >/dev/null 2>&1; then
            update-grub
        else
            grub-mkconfig -o /boot/grub/grub.cfg
        fi
        
        log_success "GRUB 구성이 복원되었습니다."
        
        # 복원된 내용 확인
        log_info "복원된 GRUB 커널 매개변수:"
        grep "GRUB_CMDLINE_LINUX" /etc/default/grub
    else
        log_warn "GRUB 백업 파일을 찾을 수 없습니다."
    fi
}

# 네트워크 설정 복원
restore_network() {
    if [[ -d "$SELECTED_BACKUP/netplan" ]]; then
        log_info "네트워크 설정 복원 중..."
        
        # 현재 설정 백업
        if [[ -d /etc/netplan ]]; then
            mv /etc/netplan "/etc/netplan.pre-restore-$(date +%Y%m%d-%H%M%S)"
        fi
        
        # 백업에서 복원
        cp -r "$SELECTED_BACKUP/netplan" /etc/netplan
        
        # 권한 설정
        chmod 600 /etc/netplan/*.yaml 2>/dev/null || true
        chmod 600 /etc/netplan/*.yml 2>/dev/null || true
        
        # 네트워크 서비스 재시작
        log_info "네트워크 서비스 재시작 중..."
        systemctl restart systemd-networkd
        
        # Netplan 적용
        if netplan try --timeout 30; then
            netplan apply
            log_success "네트워크 설정이 복원되었습니다."
        else
            log_error "네트워크 설정 복원에 실패했습니다."
            return 1
        fi
        
        # 연결성 테스트
        local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
        if ping -c 3 "$gateway" >/dev/null 2>&1; then
            log_success "네트워크 연결성 테스트 통과"
        else
            log_warn "네트워크 연결성 테스트 실패"
        fi
    else
        log_warn "네트워크 백업을 찾을 수 없습니다."
    fi
}

# 브라우저 설정 복원
restore_browser() {
    if [[ -f "$SELECTED_BACKUP/firefox_prefs.js.backup" ]]; then
        log_info "Firefox 설정 복원 중..."
        
        # Firefox 프로필 찾기
        local firefox_dirs=$(find /home -name ".mozilla" -type d 2>/dev/null || true)
        
        for firefox_dir in $firefox_dirs; do
            local profiles_dir="$firefox_dir/firefox"
            if [[ -d "$profiles_dir" ]]; then
                for profile in "$profiles_dir"/*.default*; do
                    if [[ -d "$profile" ]]; then
                        # user.js 파일 제거 (하드웨어 가속 설정)
                        if [[ -f "$profile/user.js" ]]; then
                            mv "$profile/user.js" "$profile/user.js.disabled-$(date +%Y%m%d-%H%M%S)"
                            log_info "Firefox user.js 파일이 비활성화되었습니다: $profile"
                        fi
                        
                        # prefs.js 복원 (백업이 있는 경우)
                        if [[ -f "$SELECTED_BACKUP/firefox_prefs.js.backup" ]]; then
                            cp "$SELECTED_BACKUP/firefox_prefs.js.backup" "$profile/prefs.js"
                            log_info "Firefox prefs.js가 복원되었습니다: $profile"
                        fi
                    fi
                done
            fi
        done
        
        log_success "Firefox 설정 복원이 완료되었습니다."
    else
        log_info "브라우저 설정 백업을 찾을 수 없습니다."
    fi
}

# 디스플레이 서버 설정 복원
restore_display_server() {
    if [[ -f "$SELECTED_BACKUP/gdm3_custom.conf.backup" ]]; then
        log_info "디스플레이 서버 설정 복원 중..."
        
        # 현재 설정 백업
        if [[ -f /etc/gdm3/custom.conf ]]; then
            cp /etc/gdm3/custom.conf "/etc/gdm3/custom.conf.pre-restore-$(date +%Y%m%d-%H%M%S)"
        fi
        
        # 백업에서 복원
        cp "$SELECTED_BACKUP/gdm3_custom.conf.backup" /etc/gdm3/custom.conf
        
        log_success "디스플레이 서버 설정이 복원되었습니다."
        log_warn "변경사항은 재로그인 후 적용됩니다."
    else
        log_info "디스플레이 서버 설정 백업을 찾을 수 없습니다."
    fi
}

# 모듈 블랙리스트 정리
cleanup_module_blacklists() {
    log_info "모듈 블랙리스트 정리 중..."
    
    # 자동 생성된 블랙리스트 파일들 찾기
    local blacklist_files=$(find /etc/modprobe.d -name "blacklist-*.conf" 2>/dev/null || true)
    
    for file in $blacklist_files; do
        if grep -q "자동 생성" "$file" 2>/dev/null; then
            read -p "자동 생성된 블랙리스트 파일을 제거하시겠습니까? $file (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                mv "$file" "$file.disabled-$(date +%Y%m%d-%H%M%S)"
                log_info "블랙리스트 파일이 비활성화되었습니다: $file"
            fi
        fi
    done
}

# initramfs 재생성
rebuild_initramfs() {
    log_info "initramfs 재생성 중..."
    
    local kernel_version=$(uname -r)
    update-initramfs -u -k "$kernel_version"
    
    log_success "initramfs가 재생성되었습니다."
}

# 시스템 상태 확인
verify_system_state() {
    log_info "시스템 상태 확인 중..."
    
    echo "=== 현재 시스템 상태 ==="
    echo "Ubuntu 버전: $(lsb_release -d | cut -f2)"
    echo "커널 버전: $(uname -r)"
    echo
    
    echo "=== GRUB 구성 ==="
    grep "GRUB_CMDLINE_LINUX" /etc/default/grub
    echo
    
    echo "=== 네트워크 인터페이스 ==="
    ip addr show | grep -E "^[0-9]+:" | awk '{print $2}' | tr -d ':'
    echo
    
    echo "=== 그래픽 모듈 ==="
    lsmod | grep -E "(nvidia|amdgpu|radeon|nouveau|i915)" || echo "그래픽 모듈 없음"
    echo
    
    echo "=== 활성 네트워크 서비스 ==="
    if systemctl is-active --quiet NetworkManager; then
        echo "NetworkManager: 활성"
    else
        echo "NetworkManager: 비활성"
    fi
    
    if systemctl is-active --quiet systemd-networkd; then
        echo "systemd-networkd: 활성"
    else
        echo "systemd-networkd: 비활성"
    fi
    echo
    
    log_success "시스템 상태 확인이 완료되었습니다."
}

# 완전 시스템 복원 (긴급 모드)
emergency_restore() {
    log_warn "긴급 복원 모드를 시작합니다..."
    
    # GRUB을 안전한 기본값으로 복원
    log_info "GRUB을 기본 상태로 복원 중..."
    
    cat > /etc/default/grub << 'EOF'
# GRUB 기본 구성 (긴급 복원)
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
EOF
    
    update-grub
    
    # 모든 자동 생성 모듈 블랙리스트 제거
    find /etc/modprobe.d -name "blacklist-*.conf" -exec grep -l "자동 생성" {} \; | while read file; do
        mv "$file" "$file.emergency-disabled"
        log_info "블랙리스트 파일이 비활성화되었습니다: $file"
    done
    
    # 네트워크를 DHCP로 복원
    cat > /etc/netplan/01-netcfg.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: true
    enp0s3:
      dhcp4: true
    enp0s8:
      dhcp4: true
    ens3:
      dhcp4: true
    ens18:
      dhcp4: true
EOF
    
    netplan apply
    
    # initramfs 재생성
    rebuild_initramfs
    
    log_success "긴급 복원이 완료되었습니다."
    log_warn "시스템을 재부팅하여 변경사항을 적용하세요."
}

# 백업 생성 (복원 전)
create_pre_restore_backup() {
    local pre_restore_backup="/root/pre-restore-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$pre_restore_backup"
    
    log_info "복원 전 현재 상태 백업 중: $pre_restore_backup"
    
    # 현재 설정들 백업
    cp /etc/default/grub "$pre_restore_backup/" 2>/dev/null || true
    
    if [[ -d /etc/netplan ]]; then
        cp -r /etc/netplan "$pre_restore_backup/" 2>/dev/null || true
    fi
    
    if [[ -f /etc/gdm3/custom.conf ]]; then
        cp /etc/gdm3/custom.conf "$pre_restore_backup/" 2>/dev/null || true
    fi
    
    # 시스템 상태 정보
    {
        echo "=== 복원 전 시스템 상태 ==="
        echo "날짜: $(date)"
        echo "Ubuntu 버전: $(lsb_release -d | cut -f2)"
        echo "커널 버전: $(uname -r)"
        echo
        ip addr show
        echo
        lsmod | grep -E "(nvidia|amdgpu|radeon|nouveau|i915)" || echo "그래픽 모듈 없음"
    } > "$pre_restore_backup/system_state.txt"
    
    log_success "복원 전 백업 완료: $pre_restore_backup"
}

# 메인 실행 함수
main() {
    echo "=================================================="
    echo "Ubuntu 드라이버 호환성 롤백 및 복구 스크립트"
    echo "=================================================="
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        exit 1
    fi
    
    echo "복원 모드를 선택하세요:"
    echo "1. 백업에서 선택적 복원 (권장)"
    echo "2. 긴급 시스템 복원 (모든 설정 초기화)"
    echo "3. 시스템 상태만 확인"
    echo
    read -p "선택 (1-3): " -n 1 -r mode
    echo
    
    case $mode in
        1)
            log_info "선택적 복원 모드"
            
            if ! select_backup_directory "$@"; then
                exit 1
            fi
            
            if ! analyze_backup; then
                exit 1
            fi
            
            # 복원 전 백업 생성
            create_pre_restore_backup
            
            echo
            log_warn "다음 항목들을 복원할 수 있습니다:"
            
            # 복원할 항목 선택
            if [[ -f "$SELECTED_BACKUP/grub.backup" ]]; then
                read -p "GRUB 구성을 복원하시겠습니까? (Y/n): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                    restore_grub
                fi
            fi
            
            if [[ -d "$SELECTED_BACKUP/netplan" ]]; then
                read -p "네트워크 설정을 복원하시겠습니까? (Y/n): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                    restore_network
                fi
            fi
            
            read -p "브라우저 설정을 복원하시겠습니까? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                restore_browser
            fi
            
            if [[ -f "$SELECTED_BACKUP/gdm3_custom.conf.backup" ]]; then
                read -p "디스플레이 서버 설정을 복원하시겠습니까? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    restore_display_server
                fi
            fi
            
            read -p "모듈 블랙리스트를 정리하시겠습니까? (Y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                cleanup_module_blacklists
            fi
            
            rebuild_initramfs
            ;;
            
        2)
            log_warn "긴급 시스템 복원 모드"
            log_warn "이 모드는 모든 드라이버 관련 설정을 기본값으로 복원합니다."
            
            read -p "정말로 계속하시겠습니까? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                create_pre_restore_backup
                emergency_restore
            else
                log_info "작업이 취소되었습니다."
                exit 0
            fi
            ;;
            
        3)
            log_info "시스템 상태 확인 모드"
            verify_system_state
            find_backup_directories || true
            exit 0
            ;;
            
        *)
            log_error "잘못된 선택입니다."
            exit 1
            ;;
    esac
    
    echo
    verify_system_state
    
    echo
    log_success "복원 작업이 완료되었습니다!"
    echo
    log_warn "변경사항을 완전히 적용하려면 시스템을 재부팅하세요."
    
    read -p "지금 재부팅하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "시스템을 재부팅합니다..."
        sleep 3
        reboot
    else
        log_info "재부팅은 수동으로 수행하세요: sudo reboot"
    fi
}

main "$@"