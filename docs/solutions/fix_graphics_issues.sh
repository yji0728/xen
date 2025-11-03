#!/bin/bash

# Ubuntu 그래픽 드라이버 문제 해결 스크립트
# 작성자: MiniMax Agent
# 버전: 1.0
# 사용법: sudo ./fix_graphics_issues.sh

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
BACKUP_DIR="/root/graphics-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# 그래픽 하드웨어 정보 수집
detect_graphics_hardware() {
    log_info "그래픽 하드웨어 감지 중..."
    
    # PCI 그래픽 장치 확인
    GPU_INFO=$(lspci | grep -i -E "(vga|3d|display)" || true)
    
    if [[ -z "$GPU_INFO" ]]; then
        log_error "그래픽 장치를 찾을 수 없습니다."
        exit 1
    fi
    
    log_success "감지된 그래픽 장치:"
    echo "$GPU_INFO"
    
    # 그래픽 벤더 확인
    if echo "$GPU_INFO" | grep -qi nvidia; then
        GRAPHICS_VENDOR="nvidia"
        log_info "NVIDIA 그래픽 카드가 감지되었습니다."
    elif echo "$GPU_INFO" | grep -qi amd; then
        GRAPHICS_VENDOR="amd"
        log_info "AMD 그래픽 카드가 감지되었습니다."
    elif echo "$GPU_INFO" | grep -qi intel; then
        GRAPHICS_VENDOR="intel"
        log_info "Intel 통합 그래픽이 감지되었습니다."
    else
        GRAPHICS_VENDOR="unknown"
        log_warn "알 수 없는 그래픽 벤더입니다."
    fi
}

# 현재 드라이버 상태 확인
check_current_drivers() {
    log_info "현재 그래픽 드라이버 상태 확인 중..."
    
    echo "=== 로드된 그래픽 모듈 ==="
    lsmod | grep -E "(nvidia|amdgpu|radeon|nouveau|i915)" || echo "그래픽 모듈이 로드되지 않았습니다."
    echo
    
    # NVIDIA 드라이버 확인
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo "=== NVIDIA 드라이버 정보 ==="
        nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null || true
        echo
    fi
    
    # X11 vs Wayland 확인
    if [[ -n "${XDG_SESSION_TYPE:-}" ]]; then
        log_info "현재 세션 타입: $XDG_SESSION_TYPE"
    fi
    
    # 현재 GPU 사용 중인지 확인
    if command -v glxinfo >/dev/null 2>&1; then
        echo "=== OpenGL 정보 ==="
        glxinfo | grep -E "(OpenGL vendor|OpenGL renderer|OpenGL version)" || true
        echo
    fi
}

# GRUB 백업 및 수정
backup_and_modify_grub() {
    log_info "GRUB 구성 백업 및 수정 중..."
    
    # GRUB 백업
    cp /etc/default/grub "$BACKUP_DIR/grub.backup"
    
    # 현재 GRUB 설정 확인
    CURRENT_CMDLINE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | cut -d'"' -f2)
    log_info "현재 커널 매개변수: $CURRENT_CMDLINE"
    
    # 그래픽 관련 문제 해결 매개변수 추가
    NEW_CMDLINE="$CURRENT_CMDLINE"
    
    case "$GRAPHICS_VENDOR" in
        "amd")
            handle_amd_graphics
            ;;
        "nvidia")
            handle_nvidia_graphics
            ;;
        "intel")
            handle_intel_graphics
            ;;
        *)
            handle_generic_graphics
            ;;
    esac
    
    # GRUB 구성 업데이트
    if [[ "$NEW_CMDLINE" != "$CURRENT_CMDLINE" ]]; then
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_CMDLINE\"|" /etc/default/grub
        log_success "GRUB 커널 매개변수 업데이트: $NEW_CMDLINE"
        
        # GRUB 업데이트
        update-grub
        log_success "GRUB 구성이 업데이트되었습니다."
    fi
}

# AMD 그래픽 문제 처리
handle_amd_graphics() {
    log_info "AMD 그래픽 문제 해결 중..."
    
    # nomodeset 추가 (부팅 안정성을 위해)
    if ! echo "$NEW_CMDLINE" | grep -q "nomodeset"; then
        read -p "부팅 시 화면 프리징 문제가 있나요? nomodeset을 추가하시겠습니까? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            NEW_CMDLINE="$NEW_CMDLINE nomodeset"
            log_info "nomodeset 매개변수가 추가되었습니다."
        fi
    fi
    
    # AMD 특정 매개변수
    read -p "AMDGPU 디스플레이 코어 문제가 있나요? amdgpu.dc=0을 추가하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if ! echo "$NEW_CMDLINE" | grep -q "amdgpu.dc=0"; then
            NEW_CMDLINE="$NEW_CMDLINE amdgpu.dc=0"
            log_info "amdgpu.dc=0 매개변수가 추가되었습니다."
        fi
    fi
    
    read -p "전력 관리 문제가 있나요? amdgpu.runpm=0을 추가하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if ! echo "$NEW_CMDLINE" | grep -q "amdgpu.runpm=0"; then
            NEW_CMDLINE="$NEW_CMDLINE amdgpu.runpm=0"
            log_info "amdgpu.runpm=0 매개변수가 추가되었습니다."
        fi
    fi
    
    # radeon 드라이버 블랙리스트
    read -p "radeon 레거시 드라이버를 비활성화하시겠습니까? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        blacklist_module "radeon"
    fi
}

# NVIDIA 그래픽 문제 처리
handle_nvidia_graphics() {
    log_info "NVIDIA 그래픽 문제 해결 중..."
    
    # nouveau 드라이버 비활성화
    if lsmod | grep -q nouveau; then
        log_warn "nouveau 오픈소스 드라이버가 감지되었습니다."
        read -p "독점 NVIDIA 드라이버 설치를 위해 nouveau를 비활성화하시겠습니까? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            blacklist_module "nouveau"
            if ! echo "$NEW_CMDLINE" | grep -q "modprobe.blacklist=nouveau"; then
                NEW_CMDLINE="$NEW_CMDLINE modprobe.blacklist=nouveau"
                log_info "nouveau 블랙리스트 매개변수가 추가되었습니다."
            fi
        fi
    fi
    
    # NVIDIA 독점 드라이버 설치 제안
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        read -p "NVIDIA 독점 드라이버를 설치하시겠습니까? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            install_nvidia_drivers
        fi
    fi
    
    # nomodeset 추가 (필요한 경우)
    read -p "부팅 문제가 있나요? nomodeset을 추가하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if ! echo "$NEW_CMDLINE" | grep -q "nomodeset"; then
            NEW_CMDLINE="$NEW_CMDLINE nomodeset"
            log_info "nomodeset 매개변수가 추가되었습니다."
        fi
    fi
}

# Intel 그래픽 문제 처리
handle_intel_graphics() {
    log_info "Intel 그래픽 최적화 중..."
    
    # Intel 그래픽은 일반적으로 안정적이지만 몇 가지 최적화 가능
    read -p "Intel 그래픽 가속을 최적화하시겠습니까? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        # Intel 특정 최적화 (필요한 경우만)
        if ! echo "$NEW_CMDLINE" | grep -q "i915.enable_psr=0"; then
            read -p "화면 깜빡임 문제가 있나요? PSR을 비활성화하시겠습니까? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                NEW_CMDLINE="$NEW_CMDLINE i915.enable_psr=0"
                log_info "Intel PSR 비활성화 매개변수가 추가되었습니다."
            fi
        fi
    fi
}

# 일반 그래픽 문제 처리
handle_generic_graphics() {
    log_info "일반 그래픽 문제 해결 중..."
    
    # nomodeset 추가
    if ! echo "$NEW_CMDLINE" | grep -q "nomodeset"; then
        read -p "부팅 시 화면 문제가 있나요? nomodeset을 추가하시겠습니까? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            NEW_CMDLINE="$NEW_CMDLINE nomodeset"
            log_info "nomodeset 매개변수가 추가되었습니다."
        fi
    fi
}

# 모듈 블랙리스트
blacklist_module() {
    local module="$1"
    local blacklist_file="/etc/modprobe.d/blacklist-$module.conf"
    
    if [[ ! -f "$blacklist_file" ]]; then
        echo "# $module 드라이버 블랙리스트 (자동 생성)" > "$blacklist_file"
        echo "blacklist $module" >> "$blacklist_file"
        log_success "$module 모듈이 블랙리스트에 추가되었습니다."
        
        # 백업
        cp "$blacklist_file" "$BACKUP_DIR/"
    else
        log_info "$module은 이미 블랙리스트에 있습니다."
    fi
}

# NVIDIA 드라이버 설치
install_nvidia_drivers() {
    log_info "NVIDIA 드라이버 설치 중..."
    
    # 시스템 업데이트
    apt update
    
    # 추천 드라이버 확인
    ubuntu-drivers devices
    
    # 자동 설치
    ubuntu-drivers autoinstall
    
    log_success "NVIDIA 드라이버 설치가 완료되었습니다."
    log_warn "시스템 재부팅 후 효과가 적용됩니다."
}

# 웹 브라우저 하드웨어 가속 설정
configure_browser_acceleration() {
    log_info "웹 브라우저 하드웨어 가속 설정 중..."
    
    read -p "Firefox/Chromium 하드웨어 가속을 비활성화하시겠습니까? (프리징 문제 해결) (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        
        # Firefox 설정
        local firefox_dirs=$(find /home -name ".mozilla" -type d 2>/dev/null || true)
        for firefox_dir in $firefox_dirs; do
            local profiles_dir="$firefox_dir/firefox"
            if [[ -d "$profiles_dir" ]]; then
                for profile in "$profiles_dir"/*.default*; do
                    if [[ -d "$profile" ]]; then
                        local prefs_file="$profile/prefs.js"
                        if [[ -f "$prefs_file" ]]; then
                            cp "$prefs_file" "$BACKUP_DIR/firefox_prefs.js.backup" 2>/dev/null || true
                        fi
                        
                        local user_prefs="$profile/user.js"
                        {
                            echo "// 하드웨어 가속 비활성화 (자동 추가)"
                            echo "user_pref(\"layers.acceleration.disabled\", true);"
                            echo "user_pref(\"gfx.direct2d.disabled\", true);"
                            echo "user_pref(\"webgl.disabled\", true);"
                        } >> "$user_prefs"
                        
                        log_info "Firefox 하드웨어 가속이 비활성화되었습니다: $profile"
                    fi
                done
            fi
        done
        
        log_success "브라우저 하드웨어 가속 설정이 완료되었습니다."
        log_info "변경사항은 브라우저 재시작 후 적용됩니다."
    fi
}

# 디스플레이 서버 설정 (Wayland vs X11)
configure_display_server() {
    log_info "디스플레이 서버 설정 확인 중..."
    
    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
        log_info "현재 Wayland 세션을 사용 중입니다."
        
        read -p "그래픽 문제 해결을 위해 X11로 전환하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # GDM 설정 (Ubuntu 기본)
            local gdm_custom="/etc/gdm3/custom.conf"
            if [[ -f "$gdm_custom" ]]; then
                cp "$gdm_custom" "$BACKUP_DIR/gdm3_custom.conf.backup"
                
                # Wayland 비활성화
                sed -i 's/#WaylandEnable=false/WaylandEnable=false/' "$gdm_custom"
                
                log_success "X11이 기본 디스플레이 서버로 설정되었습니다."
                log_warn "로그아웃 후 다시 로그인하여 X11 세션을 선택하세요."
            fi
        fi
    else
        log_info "현재 X11 세션을 사용 중입니다."
    fi
}

# 시스템 정보 수집
collect_graphics_info() {
    log_info "그래픽 시스템 정보 수집 중..."
    
    local info_file="$BACKUP_DIR/graphics_info.txt"
    
    {
        echo "=== 그래픽 시스템 정보 ==="
        echo "날짜: $(date)"
        echo "Ubuntu 버전: $(lsb_release -d | cut -f2)"
        echo "커널 버전: $(uname -r)"
        echo
        echo "=== 그래픽 하드웨어 ==="
        lspci | grep -i -E "(vga|3d|display)"
        echo
        echo "=== 로드된 그래픽 모듈 ==="
        lsmod | grep -E "(nvidia|amdgpu|radeon|nouveau|i915)" || echo "그래픽 모듈 없음"
        echo
        echo "=== GRUB 구성 ==="
        grep "GRUB_CMDLINE_LINUX" /etc/default/grub
        echo
        echo "=== 디스플레이 서버 ==="
        echo "XDG_SESSION_TYPE: ${XDG_SESSION_TYPE:-unknown}"
        echo "DISPLAY: ${DISPLAY:-not set}"
        echo "WAYLAND_DISPLAY: ${WAYLAND_DISPLAY:-not set}"
        echo
        echo "=== OpenGL 정보 ==="
        glxinfo | grep -E "(OpenGL vendor|OpenGL renderer|OpenGL version)" 2>/dev/null || echo "glxinfo 없음"
        echo
        echo "=== 그래픽 관련 오류 ==="
        dmesg | grep -i -E "(gpu|graphics|amdgpu|nvidia|radeon)" | tail -20
        echo
        echo "=== Xorg 로그 ==="
        if [[ -f /var/log/Xorg.0.log ]]; then
            grep -E "(EE|WW)" /var/log/Xorg.0.log | tail -10
        else
            echo "Xorg 로그 없음"
        fi
    } > "$info_file"
    
    log_success "그래픽 정보가 $info_file에 저장되었습니다."
}

# 테스트 및 검증
verify_graphics_fix() {
    log_info "그래픽 설정 검증 중..."
    
    # GRUB 구성 확인
    local current_cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | cut -d'"' -f2)
    log_info "현재 GRUB 커널 매개변수: $current_cmdline"
    
    # 모듈 블랙리스트 확인
    local blacklist_files=$(find /etc/modprobe.d -name "blacklist-*.conf" 2>/dev/null || true)
    if [[ -n "$blacklist_files" ]]; then
        log_info "블랙리스트된 모듈:"
        for file in $blacklist_files; do
            echo "  $file: $(grep blacklist "$file" 2>/dev/null || true)"
        done
    fi
    
    log_success "그래픽 설정 검증이 완료되었습니다."
}

# 메인 실행 함수
main() {
    echo "=================================================="
    echo "Ubuntu 그래픽 드라이버 문제 해결 스크립트"
    echo "=================================================="
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        exit 1
    fi
    
    # 경고 메시지
    log_warn "이 스크립트는 그래픽 드라이버와 부팅 구성을 수정합니다."
    log_warn "데스크톱 환경을 사용 중이라면 재부팅이 필요할 수 있습니다."
    
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "스크립트 실행이 취소되었습니다."
        exit 0
    fi
    
    # 필수 패키지 설치
    log_info "필수 패키지 업데이트 중..."
    apt update
    apt install -y mesa-utils pciutils
    
    # 단계별 실행
    detect_graphics_hardware
    check_current_drivers
    backup_and_modify_grub
    configure_browser_acceleration
    configure_display_server
    collect_graphics_info
    verify_graphics_fix
    
    echo
    log_success "그래픽 드라이버 문제 해결이 완료되었습니다!"
    echo
    log_info "백업 파일들: $BACKUP_DIR"
    log_warn "변경사항을 적용하려면 시스템을 재부팅하세요."
    
    echo
    echo "=== 문제 해결 후 확인 사항 ==="
    echo "1. 시스템 재부팅"
    echo "2. 부팅 시 화면 정상 표시 확인"
    echo "3. 데스크톱 환경 안정성 확인"
    echo "4. 외부 디스플레이 연결 테스트 (해당하는 경우)"
    echo "5. 웹 브라우저 안정성 확인"
    
    echo
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