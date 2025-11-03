#!/bin/bash

#####################################################################
# Xen 설치 긴급 복구 도구 v1.0
# 설치 실패 시 시스템을 원래 상태로 복구
#####################################################################

set -euo pipefail

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 백업 디렉토리
BACKUP_DIR="/var/backups/xen-installer"
LOG_DIR="/var/log/xen-installer"

# 복구 단계
declare -A RECOVERY_STEPS=(
    ["grub_config"]="PENDING"
    ["xen_packages"]="PENDING"
    ["network_config"]="PENDING"
    ["services"]="PENDING"
    ["cleanup"]="PENDING"
)

# 로깅 함수
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# 결과 업데이트
update_result() {
    local step="$1"
    local result="$2"
    RECOVERY_STEPS["$step"]="$result"
    
    case "$result" in
        "SUCCESS") echo -e "${GREEN}✅ 성공${NC}" ;;
        "FAILED") echo -e "${RED}❌ 실패${NC}" ;;
        "SKIPPED") echo -e "${YELLOW}⏭️ 스킵됨${NC}" ;;
    esac
}

# 초기화
init_recovery() {
    echo -e "${BLUE}=== Xen 설치 긴급 복구 도구 v1.0 ===${NC}"
    echo -e "${RED}⚠️ 이 도구는 Xen 설치를 완전히 제거하고 시스템을 원래 상태로 복구합니다.${NC}"
    echo

    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        echo -e "${RED}sudo $0${NC}"
        exit 1
    fi

    # 백업 디렉토리 확인
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_warn "백업 디렉토리를 찾을 수 없습니다: $BACKUP_DIR"
        log_warn "일부 복구 작업이 제한될 수 있습니다."
    else
        log_info "백업 디렉토리 확인됨: $BACKUP_DIR"
        echo "백업 파일 목록:"
        ls -la "$BACKUP_DIR" 2>/dev/null || echo "  (백업 파일 없음)"
    fi

    # 사용자 확인
    echo
    read -p "정말로 Xen 설치를 완전히 제거하고 시스템을 복구하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "복구가 취소되었습니다."
        exit 0
    fi

    log_info "시스템 복구를 시작합니다..."
}

# GRUB 설정 복구
restore_grub_config() {
    log_section "GRUB 설정 복구"
    
    # 백업된 GRUB 설정 찾기
    local grub_backup=""
    if [[ -d "$BACKUP_DIR" ]]; then
        grub_backup=$(find "$BACKUP_DIR" -name "grub.backup.*" -type f | head -n1)
    fi
    
    if [[ -n "$grub_backup" ]] && [[ -f "$grub_backup" ]]; then
        log_info "백업된 GRUB 설정을 복원합니다: $grub_backup"
        
        # 현재 설정 백업 (복구용)
        cp /etc/default/grub /etc/default/grub.recovery.backup.$(date +%s) || true
        
        # 백업 설정 복원
        if cp "$grub_backup" /etc/default/grub; then
            log_info "GRUB 설정 복원 완료"
            
            # GRUB 업데이트
            log_info "GRUB 업데이트 중..."
            if update-grub; then
                log_info "GRUB 업데이트 완료"
                update_result "grub_config" "SUCCESS"
            else
                log_error "GRUB 업데이트 실패"
                update_result "grub_config" "FAILED"
            fi
        else
            log_error "GRUB 설정 복원 실패"
            update_result "grub_config" "FAILED"
        fi
    else
        log_warn "백업된 GRUB 설정을 찾을 수 없습니다."
        log_info "기본 GRUB 설정으로 복원을 시도합니다..."
        
        # 기본 GRUB 설정 생성
        cat > /etc/default/grub << 'EOF'
# Ubuntu 기본 GRUB 설정
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
EOF
        
        if update-grub; then
            log_info "기본 GRUB 설정으로 복원 완료"
            update_result "grub_config" "SUCCESS"
        else
            log_error "GRUB 복원 실패"
            update_result "grub_config" "FAILED"
        fi
    fi
}

# Xen 패키지 제거
remove_xen_packages() {
    log_section "Xen 패키지 제거"
    
    # 설치된 Xen 패키지 확인
    local xen_packages=$(dpkg -l | grep -E "^ii.*xen" | awk '{print $2}' | tr '\n' ' ')
    
    if [[ -n "$xen_packages" ]]; then
        log_info "다음 Xen 패키지들을 제거합니다:"
        echo "$xen_packages"
        
        # Xen 서비스 중지
        log_info "Xen 서비스 중지 중..."
        systemctl stop xenconsoled 2>/dev/null || true
        systemctl stop xen-qemu-dom0-disk-backend 2>/dev/null || true
        systemctl stop xenstored 2>/dev/null || true
        
        # 서비스 비활성화
        systemctl disable xenconsoled 2>/dev/null || true
        systemctl disable xen-qemu-dom0-disk-backend 2>/dev/null || true
        systemctl disable xenstored 2>/dev/null || true
        
        # 패키지 제거
        log_info "Xen 패키지 제거 중..."
        if apt remove --purge -y $xen_packages; then
            log_info "Xen 패키지 제거 완료"
            
            # 의존성 정리
            apt autoremove -y || true
            apt autoclean || true
            
            update_result "xen_packages" "SUCCESS"
        else
            log_error "Xen 패키지 제거 실패"
            update_result "xen_packages" "FAILED"
        fi
    else
        log_info "제거할 Xen 패키지가 없습니다."
        update_result "xen_packages" "SKIPPED"
    fi
    
    # /boot에서 Xen 파일 제거
    log_info "/boot에서 Xen 관련 파일 제거 중..."
    rm -f /boot/xen*.gz 2>/dev/null || true
    rm -f /boot/xen-* 2>/dev/null || true
    
    # Xen 설정 디렉토리 백업 후 제거
    if [[ -d /etc/xen ]]; then
        log_info "Xen 설정 디렉토리 백업 중..."
        if [[ -d "$BACKUP_DIR" ]]; then
            cp -r /etc/xen "$BACKUP_DIR/xen-config-backup-$(date +%s)" 2>/dev/null || true
        fi
        rm -rf /etc/xen 2>/dev/null || true
    fi
}

# 네트워크 설정 복구
restore_network_config() {
    log_section "네트워크 설정 복구"
    
    # NetworkManager 설정 제거
    local nm_bridge_config="/etc/NetworkManager/conf.d/99-unmanage-bridge.conf"
    if [[ -f "$nm_bridge_config" ]]; then
        log_info "NetworkManager 브릿지 설정 제거 중..."
        rm -f "$nm_bridge_config"
        systemctl reload NetworkManager 2>/dev/null || true
    fi
    
    # 기존 Xen 브릿지 제거
    if command -v brctl >/dev/null; then
        local bridges=$(brctl show 2>/dev/null | grep -E "xenbr|virbr" | awk '{print $1}' | grep -v "bridge")
        for bridge in $bridges; do
            if [[ -n "$bridge" ]]; then
                log_info "브릿지 제거 중: $bridge"
                ip link set "$bridge" down 2>/dev/null || true
                brctl delbr "$bridge" 2>/dev/null || true
            fi
        done
    fi
    
    # 네트워크 재시작
    log_info "네트워크 서비스 재시작 중..."
    systemctl restart networking 2>/dev/null || true
    systemctl restart NetworkManager 2>/dev/null || true
    
    update_result "network_config" "SUCCESS"
}

# 서비스 정리
cleanup_services() {
    log_section "서비스 정리"
    
    # Xen 관련 서비스 확인 및 제거
    local xen_services=(
        "xenconsoled"
        "xen-qemu-dom0-disk-backend"
        "xenstored"
        "xen-init-dom0"
        "xen-watchdog"
    )
    
    for service in "${xen_services[@]}"; do
        if systemctl list-unit-files | grep -q "$service"; then
            log_info "서비스 비활성화: $service"
            systemctl disable "$service" 2>/dev/null || true
            systemctl stop "$service" 2>/dev/null || true
            systemctl mask "$service" 2>/dev/null || true
        fi
    done
    
    # systemd 데몬 리로드
    systemctl daemon-reload
    
    update_result "services" "SUCCESS"
}

# 시스템 정리
system_cleanup() {
    log_section "시스템 정리"
    
    # 로그 파일 정리 (오래된 것만)
    if [[ -d "$LOG_DIR" ]]; then
        log_info "오래된 로그 파일 정리 중..."
        find "$LOG_DIR" -name "*.log" -mtime +7 -delete 2>/dev/null || true
    fi
    
    # Xen 관련 임시 파일 정리
    rm -rf /tmp/xen-* 2>/dev/null || true
    rm -rf /var/run/xen* 2>/dev/null || true
    rm -rf /var/lib/xen 2>/dev/null || true
    
    # 패키지 캐시 정리
    apt clean || true
    
    # depmod 업데이트
    log_info "커널 모듈 의존성 업데이트 중..."
    depmod -a 2>/dev/null || true
    
    # initramfs 재생성
    log_info "initramfs 재생성 중..."
    update-initramfs -u 2>/dev/null || true
    
    update_result "cleanup" "SUCCESS"
}

# 복구 결과 요약
show_recovery_summary() {
    log_section "복구 결과 요약"
    
    local success_count=0
    local failed_count=0
    local skipped_count=0
    
    echo "┌─────────────────────────────────────┬────────────┐"
    echo "│ 복구 항목                           │ 결과       │"
    echo "├─────────────────────────────────────┼────────────┤"
    
    for step in "${!RECOVERY_STEPS[@]}"; do
        local result="${RECOVERY_STEPS[$step]}"
        local step_name=""
        
        case "$step" in
            "grub_config") step_name="GRUB 설정 복구" ;;
            "xen_packages") step_name="Xen 패키지 제거" ;;
            "network_config") step_name="네트워크 설정 복구" ;;
            "services") step_name="서비스 정리" ;;
            "cleanup") step_name="시스템 정리" ;;
        esac
        
        case "$result" in
            "SUCCESS") 
                echo "│ $step_name" | awk '{printf "%-35s", $0}'
                echo " │ ${GREEN}✅ 성공${NC}    │"
                ((success_count++))
                ;;
            "FAILED")
                echo "│ $step_name" | awk '{printf "%-35s", $0}'
                echo " │ ${RED}❌ 실패${NC}    │"
                ((failed_count++))
                ;;
            "SKIPPED")
                echo "│ $step_name" | awk '{printf "%-35s", $0}'
                echo " │ ${YELLOW}⏭️ 스킵됨${NC}  │"
                ((skipped_count++))
                ;;
        esac
    done
    
    echo "└─────────────────────────────────────┴────────────┘"
    echo
    echo "복구 통계:"
    echo "  - 성공: ${success_count}개"
    echo "  - 실패: ${failed_count}개"
    echo "  - 스킵됨: ${skipped_count}개"
    echo
    
    if [[ $failed_count -gt 0 ]]; then
        echo -e "${RED}⚠️ 일부 복구 작업이 실패했습니다. 수동으로 확인이 필요할 수 있습니다.${NC}"
    else
        echo -e "${GREEN}✅ 모든 복구 작업이 성공적으로 완료되었습니다.${NC}"
    fi
}

# 복구 후 안내사항
show_post_recovery_info() {
    log_section "복구 완료 안내"
    
    echo -e "${CYAN}다음 단계:${NC}"
    echo "  1. 시스템을 재부팅하세요: ${CYAN}sudo reboot${NC}"
    echo "  2. 정상 커널로 부팅되는지 확인하세요"
    echo "  3. 네트워크 연결을 확인하세요"
    echo
    
    echo -e "${YELLOW}확인 사항:${NC}"
    echo "  - GRUB 메뉴에서 Xen 항목이 제거되었는지 확인"
    echo "  - 네트워크 인터페이스가 정상적으로 작동하는지 확인"
    echo "  - 시스템 서비스가 정상적으로 시작되는지 확인"
    echo
    
    echo -e "${PURPLE}백업 파일 위치:${NC}"
    if [[ -d "$BACKUP_DIR" ]]; then
        echo "  - 백업 디렉토리: $BACKUP_DIR"
        echo "  - 복구 로그: $LOG_DIR"
        echo "  - 필요시 백업 파일을 사용하여 수동 복구 가능"
    fi
    echo
    
    echo -e "${GREEN}복구가 완료되었습니다. 시스템을 재부팅하세요.${NC}"
    
    # 재부팅 확인
    read -p "지금 재부팅하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "시스템을 재부팅합니다..."
        reboot
    else
        echo -e "${YELLOW}수동으로 재부팅해주세요: sudo reboot${NC}"
    fi
}

# 메인 복구 함수
main_recovery() {
    local recovery_functions=(
        "restore_grub_config"
        "remove_xen_packages"
        "restore_network_config"
        "cleanup_services"
        "system_cleanup"
    )
    
    for func in "${recovery_functions[@]}"; do
        $func
    done
}

# 사용법 출력
show_usage() {
    echo "사용법: $0 [옵션]"
    echo
    echo "옵션:"
    echo "  -h, --help     이 도움말 출력"
    echo "  -f, --force    확인 없이 강제 복구 실행"
    echo
    echo "이 스크립트는 Xen 설치를 완전히 제거하고 시스템을 원래 상태로 복구합니다."
    echo
    echo "복구 항목:"
    echo "  - GRUB 설정 복원"
    echo "  - Xen 패키지 완전 제거"
    echo "  - 네트워크 설정 복구"
    echo "  - Xen 서비스 정리"
    echo "  - 시스템 임시 파일 정리"
}

# 메인 함수
main() {
    local force_mode=false
    
    # 옵션 파싱
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -f|--force)
                force_mode=true
                shift
                ;;
            *)
                echo "알 수 없는 옵션: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 초기화 (force 모드가 아닌 경우에만 사용자 확인)
    if [[ "$force_mode" == "false" ]]; then
        init_recovery
    else
        echo -e "${BLUE}=== Xen 설치 긴급 복구 도구 v1.0 (강제 모드) ===${NC}"
        log_info "강제 모드로 복구를 시작합니다..."
    fi
    
    # 복구 실행
    main_recovery
    
    # 결과 요약
    show_recovery_summary
    
    # 복구 후 안내
    show_post_recovery_info
}

# 스크립트 실행
main "$@"