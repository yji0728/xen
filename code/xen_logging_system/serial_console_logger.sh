#!/bin/bash

#####################################################################
# 직렬 콘솔 로깅 설정 도구 v1.0
# BIOS/UEFI부터 Xen까지 완전한 직렬 콘솔 로깅 구성
#####################################################################

set -euo pipefail

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 설정 변수
SERIAL_PORT="ttyS0"
SERIAL_SPEED="115200"
SERIAL_PARAMS="8n1"
LOG_DIR="/var/log/xen-serial-console"
BACKUP_DIR="/var/backups/xen-serial-console"

# 로깅 함수
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# 초기화
init_serial_logging() {
    log_section "직렬 콘솔 로깅 시스템 초기화"
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        exit 1
    fi
    
    # 디렉토리 생성
    mkdir -p "$LOG_DIR" "$BACKUP_DIR"
    
    # 현재 설정 백업
    [[ -f /etc/default/grub ]] && cp /etc/default/grub "$BACKUP_DIR/grub.backup.$(date +%s)"
    [[ -f /etc/inittab ]] && cp /etc/inittab "$BACKUP_DIR/inittab.backup.$(date +%s)"
    
    log_info "직렬 콘솔 로깅 시스템 초기화 완료"
}

# 하드웨어 직렬 포트 확인
check_serial_hardware() {
    log_section "직렬 포트 하드웨어 확인"
    
    # 직렬 포트 존재 확인
    if [[ -c "/dev/$SERIAL_PORT" ]]; then
        log_info "직렬 포트 /dev/$SERIAL_PORT 감지됨"
    else
        log_warn "직렬 포트 /dev/$SERIAL_PORT가 존재하지 않습니다."
        log_warn "가상 직렬 포트로 설정을 계속합니다."
    fi
    
    # dmesg에서 직렬 포트 정보 확인
    echo "시스템 직렬 포트 정보:"
    dmesg | grep -i "serial\|uart\|tty" | head -n10 || echo "직렬 포트 정보를 찾을 수 없습니다."
    
    # /proc/tty/driver/serial 확인
    if [[ -f /proc/tty/driver/serial ]]; then
        echo
        echo "/proc/tty/driver/serial 내용:"
        cat /proc/tty/driver/serial
    fi
    
    # 사용 가능한 tty 디바이스 목록
    echo
    echo "사용 가능한 직렬 디바이스:"
    ls -la /dev/ttyS* 2>/dev/null || echo "ttyS* 디바이스를 찾을 수 없습니다."
}

# GRUB 직렬 콘솔 설정
configure_grub_serial() {
    log_section "GRUB 직렬 콘솔 설정"
    
    local grub_file="/etc/default/grub"
    local temp_file=$(mktemp)
    
    # 현재 GRUB 설정 읽기
    cp "$grub_file" "$temp_file"
    
    # 기존 직렬 설정 제거
    sed -i '/^GRUB_TERMINAL=/d' "$temp_file"
    sed -i '/^GRUB_SERIAL_COMMAND=/d' "$temp_file"
    
    # 새로운 직렬 콘솔 설정 추가
    cat >> "$temp_file" << EOF

# 직렬 콘솔 설정 (xen_boot_logger에 의해 추가됨)
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=$SERIAL_SPEED --unit=0 --word=8 --parity=no --stop=1"
EOF
    
    # GRUB_CMDLINE_LINUX_DEFAULT에 콘솔 설정 추가
    if ! grep -q "console=" "$temp_file"; then
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/&console=$SERIAL_PORT,$SERIAL_SPEED console=tty0 /" "$temp_file"
    else
        log_info "콘솔 설정이 이미 존재합니다."
    fi
    
    # 변경사항 적용
    if mv "$temp_file" "$grub_file"; then
        log_info "GRUB 직렬 콘솔 설정 완료"
        
        # GRUB 업데이트
        log_info "GRUB 업데이트 중..."
        if update-grub; then
            log_info "GRUB 업데이트 성공"
        else
            log_error "GRUB 업데이트 실패"
            return 1
        fi
    else
        log_error "GRUB 설정 파일 업데이트 실패"
        return 1
    fi
}

# systemd 직렬 콘솔 서비스 설정
configure_systemd_serial() {
    log_section "systemd 직렬 콘솔 서비스 설정"
    
    # getty 서비스 활성화
    local getty_service="serial-getty@$SERIAL_PORT.service"
    
    if systemctl enable "$getty_service"; then
        log_info "직렬 getty 서비스 활성화: $getty_service"
    else
        log_warn "직렬 getty 서비스 활성화 실패"
    fi
    
    # 서비스 시작
    if systemctl start "$getty_service"; then
        log_info "직렬 getty 서비스 시작됨"
    else
        log_warn "직렬 getty 서비스 시작 실패"
    fi
    
    # 서비스 상태 확인
    echo "직렬 getty 서비스 상태:"
    systemctl status "$getty_service" --no-pager -l || true
}

# Xen 직렬 콘솔 설정
configure_xen_serial() {
    log_section "Xen 하이퍼바이저 직렬 콘솔 설정"
    
    # Xen 설치 확인
    if ! command -v xl >/dev/null; then
        log_warn "Xen이 설치되어 있지 않습니다. Xen 설정을 건너뜁니다."
        return 0
    fi
    
    # xl.conf 파일 확인 및 생성
    local xl_conf="/etc/xen/xl.conf"
    if [[ ! -f "$xl_conf" ]]; then
        log_info "xl.conf 파일 생성 중..."
        mkdir -p /etc/xen
        touch "$xl_conf"
    fi
    
    # 백업 생성
    cp "$xl_conf" "$BACKUP_DIR/xl.conf.backup.$(date +%s)"
    
    # Xen 직렬 콘솔 설정 추가
    cat >> "$xl_conf" << EOF

# 직렬 콘솔 설정 (xen_boot_logger에 의해 추가됨)
# 기본 콘솔 타입
vfb = []
console = "pty"

# 직렬 콘솔 포트 매핑
serial = "pty"
EOF
    
    log_info "Xen 직렬 콘솔 설정 완료"
}

# 직렬 로그 캡처 서비스 생성
create_serial_logging_service() {
    log_section "직렬 로그 캡처 서비스 생성"
    
    # 로그 캡처 스크립트 생성
    cat > /usr/local/bin/serial-console-logger.sh << EOF
#!/bin/bash

#####################################################################
# 직렬 콘솔 로그 캡처 스크립트
#####################################################################

SERIAL_PORT="$SERIAL_PORT"
LOG_DIR="$LOG_DIR"
LOG_FILE="\$LOG_DIR/serial-console-\$(date +%Y%m%d).log"

# 로그 디렉토리 생성
mkdir -p "\$LOG_DIR"

# 직렬 포트 설정
if [[ -c "/dev/\$SERIAL_PORT" ]]; then
    stty -F "/dev/\$SERIAL_PORT" $SERIAL_SPEED cs8 -cstopb -parity
fi

# 로그 시작 마커
echo "=== Serial Console Logging Started: \$(date) ===" >> "\$LOG_FILE"

# 무한 루프로 직렬 포트 데이터 캡처
while true; do
    if [[ -c "/dev/\$SERIAL_PORT" ]]; then
        # 직렬 포트에서 데이터 읽기
        timeout 1 cat "/dev/\$SERIAL_PORT" >> "\$LOG_FILE" 2>/dev/null || true
    else
        # 가상 환경에서는 dmesg 모니터링
        timeout 1 dmesg -w >> "\$LOG_FILE" 2>/dev/null || true
    fi
    sleep 1
done
EOF
    
    chmod +x /usr/local/bin/serial-console-logger.sh
    
    # systemd 서비스 파일 생성
    cat > /etc/systemd/system/serial-console-logger.service << EOF
[Unit]
Description=Serial Console Logger
After=multi-user.target
Wants=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/serial-console-logger.sh
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
    
    # 서비스 활성화
    systemctl daemon-reload
    systemctl enable serial-console-logger.service
    systemctl start serial-console-logger.service
    
    log_info "직렬 콘솔 로깅 서비스 생성 및 시작 완료"
}

# 직렬 콘솔 모니터링 도구 생성
create_serial_monitor_tools() {
    log_section "직렬 콘솔 모니터링 도구 생성"
    
    # 실시간 직렬 콘솔 모니터 스크립트
    cat > /usr/local/bin/monitor-serial-console.sh << 'EOF'
#!/bin/bash

#####################################################################
# 실시간 직렬 콘솔 모니터
#####################################################################

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SERIAL_PORT="ttyS0"
LOG_DIR="/var/log/xen-serial-console"

echo -e "${BLUE}=== Xen Serial Console Monitor ===${NC}"
echo "Monitoring serial console on /dev/$SERIAL_PORT"
echo "Logs saved to: $LOG_DIR"
echo "Press Ctrl+C to exit"
echo

# 실시간 로그 표시
tail -f "$LOG_DIR/serial-console-$(date +%Y%m%d).log" 2>/dev/null | while read -r line; do
    timestamp=$(date '+%H:%M:%S')
    
    # 패턴별 색상 적용
    if echo "$line" | grep -qiE "error|fail|panic|fatal"; then
        echo -e "${RED}[$timestamp] $line${NC}"
    elif echo "$line" | grep -qiE "warn|warning"; then
        echo -e "${YELLOW}[$timestamp] $line${NC}"
    elif echo "$line" | grep -qiE "xen|dom0|domain"; then
        echo -e "${GREEN}[$timestamp] $line${NC}"
    else
        echo "[$timestamp] $line"
    fi
done
EOF
    
    chmod +x /usr/local/bin/monitor-serial-console.sh
    
    # 직렬 콘솔 연결 도구
    cat > /usr/local/bin/connect-serial-console.sh << 'EOF'
#!/bin/bash

#####################################################################
# 직렬 콘솔 연결 도구
#####################################################################

SERIAL_PORT="ttyS0"
SERIAL_SPEED="115200"

echo "=== Connecting to Serial Console ==="
echo "Port: /dev/$SERIAL_PORT"
echo "Speed: $SERIAL_SPEED"
echo "Press Ctrl+A, X to exit minicom"
echo

# minicom이 설치되어 있는지 확인
if ! command -v minicom >/dev/null; then
    echo "Installing minicom..."
    apt update && apt install -y minicom
fi

# minicom 설정
if [[ ! -f /etc/minicom/minirc.xen ]]; then
    cat > /etc/minicom/minirc.xen << MINICOM_EOF
pu port             /dev/$SERIAL_PORT
pu baudrate         $SERIAL_SPEED
pu bits             8
pu parity           N
pu stopbits         1
pu rtscts           No
pu xonxoff          No
pu linewrap         Yes
pu addlinefeed      No
MINICOM_EOF
fi

# minicom 실행
minicom -c on xen
EOF
    
    chmod +x /usr/local/bin/connect-serial-console.sh
    
    # 로그 분석 도구
    cat > /usr/local/bin/analyze-serial-logs.sh << 'EOF'
#!/bin/bash

#####################################################################
# 직렬 콘솔 로그 분석 도구
#####################################################################

LOG_DIR="/var/log/xen-serial-console"
ANALYSIS_DIR="$LOG_DIR/analysis"

mkdir -p "$ANALYSIS_DIR"

echo "=== Serial Console Log Analysis ==="
echo "Analyzing logs in: $LOG_DIR"

# 최근 로그 파일 찾기
LATEST_LOG=$(ls -t "$LOG_DIR"/serial-console-*.log 2>/dev/null | head -n1)

if [[ -z "$LATEST_LOG" ]]; then
    echo "No serial console logs found"
    exit 1
fi

echo "Analyzing: $LATEST_LOG"

# 분석 결과 파일
ANALYSIS_FILE="$ANALYSIS_DIR/analysis-$(date +%Y%m%d-%H%M%S).txt"

{
    echo "=== Serial Console Log Analysis Report ==="
    echo "Generated: $(date)"
    echo "Log file: $LATEST_LOG"
    echo "Log size: $(du -h "$LATEST_LOG" | cut -f1)"
    echo

    echo "=== Boot Sequence Detection ==="
    grep -n -i "boot\|grub\|xen\|kernel\|init" "$LATEST_LOG" | head -n20
    echo

    echo "=== Error Messages ==="
    grep -n -iE "error|fail|panic|fatal" "$LATEST_LOG" | head -n10
    echo

    echo "=== Warning Messages ==="
    grep -n -iE "warn|warning" "$LATEST_LOG" | head -n10
    echo

    echo "=== Xen Messages ==="
    grep -n -i "xen" "$LATEST_LOG" | head -n10
    echo

    echo "=== Domain Information ==="
    grep -n -iE "dom0|domain|domU" "$LATEST_LOG" | head -n10
    echo

    echo "=== Memory Information ==="
    grep -n -i "memory\|mem" "$LATEST_LOG" | head -n10
    echo

    echo "=== Network Information ==="
    grep -n -iE "network|eth|bridge|vif" "$LATEST_LOG" | head -n10
    echo

} > "$ANALYSIS_FILE"

echo "Analysis saved to: $ANALYSIS_FILE"
echo
echo "Quick summary:"
echo "  Total lines: $(wc -l < "$LATEST_LOG")"
echo "  Errors: $(grep -c -iE "error|fail|panic|fatal" "$LATEST_LOG" 2>/dev/null || echo 0)"
echo "  Warnings: $(grep -c -iE "warn|warning" "$LATEST_LOG" 2>/dev/null || echo 0)"
echo "  Xen messages: $(grep -c -i "xen" "$LATEST_LOG" 2>/dev/null || echo 0)"
EOF
    
    chmod +x /usr/local/bin/analyze-serial-logs.sh
    
    log_info "직렬 콘솔 모니터링 도구 생성 완료"
}

# 네트워크 직렬 콘솔 설정 (원격 모니터링)
setup_network_serial_logging() {
    log_section "네트워크 직렬 콘솔 설정 (선택사항)"
    
    read -p "네트워크를 통한 원격 직렬 콘솔 액세스를 설정하시겠습니까? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # socat 설치
        if ! command -v socat >/dev/null; then
            log_info "socat 설치 중..."
            apt update && apt install -y socat
        fi
        
        # 네트워크 직렬 콘솔 서비스 생성
        cat > /etc/systemd/system/network-serial-console.service << EOF
[Unit]
Description=Network Serial Console Bridge
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:2023,reuseaddr,fork FILE:/dev/$SERIAL_PORT,raw,echo=0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable network-serial-console.service
        systemctl start network-serial-console.service
        
        log_info "네트워크 직렬 콘솔 설정 완료"
        log_info "원격 연결: telnet <server-ip> 2023"
        
        # 방화벽 설정 안내
        log_warn "방화벽에서 포트 2023을 열어야 합니다:"
        log_warn "  ufw allow 2023/tcp  # Ubuntu 방화벽"
    else
        log_info "네트워크 직렬 콘솔 설정을 건너뜁니다."
    fi
}

# 로그 회전 설정
setup_serial_log_rotation() {
    log_section "직렬 콘솔 로그 회전 설정"
    
    cat > /etc/logrotate.d/xen-serial-console << 'EOF'
/var/log/xen-serial-console/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        # 로그 회전 후 서비스 재시작
        systemctl restart serial-console-logger 2>/dev/null || true
    endscript
}
EOF
    
    log_info "직렬 콘솔 로그 회전 설정 완료"
}

# 설치 완료 정보 출력
show_installation_summary() {
    log_section "직렬 콘솔 로깅 설치 완료"
    
    echo -e "${GREEN}설치가 완료되었습니다!${NC}"
    echo
    echo "설정된 기능:"
    echo "  ✓ GRUB 직렬 콘솔 설정"
    echo "  ✓ systemd 직렬 getty 서비스"
    echo "  ✓ Xen 직렬 콘솔 설정"
    echo "  ✓ 직렬 로그 캡처 서비스"
    echo "  ✓ 모니터링 도구"
    echo "  ✓ 로그 회전 설정"
    echo
    echo -e "${CYAN}사용 방법:${NC}"
    echo "  - 실시간 모니터링: monitor-serial-console.sh"
    echo "  - 직렬 콘솔 연결: connect-serial-console.sh"
    echo "  - 로그 분석: analyze-serial-logs.sh"
    echo
    echo -e "${CYAN}로그 위치:${NC}"
    echo "  - 직렬 콘솔 로그: $LOG_DIR"
    echo "  - 설정 백업: $BACKUP_DIR"
    echo
    echo -e "${YELLOW}중요:${NC}"
    echo "  - 시스템을 재부팅하여 GRUB 설정을 적용하세요"
    echo "  - 직렬 포트 연결을 확인하세요"
    echo "  - 원격 모니터링을 위해서는 실제 직렬 케이블이 필요합니다"
    echo
    
    # 서비스 상태 확인
    echo "서비스 상태:"
    systemctl status serial-console-logger.service --no-pager -l | head -n5 || true
}

# 설정 확인 및 테스트
test_serial_configuration() {
    log_section "직렬 콘솔 설정 테스트"
    
    # GRUB 설정 확인
    echo "GRUB 설정 확인:"
    grep -E "GRUB_TERMINAL|GRUB_SERIAL|console=" /etc/default/grub || echo "설정을 찾을 수 없습니다"
    echo
    
    # 직렬 포트 상태 확인
    echo "직렬 포트 상태:"
    if [[ -c "/dev/$SERIAL_PORT" ]]; then
        ls -la "/dev/$SERIAL_PORT"
        stty -F "/dev/$SERIAL_PORT" 2>/dev/null || echo "포트 설정 확인 실패"
    else
        echo "/dev/$SERIAL_PORT가 존재하지 않습니다"
    fi
    echo
    
    # 서비스 상태 확인
    echo "관련 서비스 상태:"
    systemctl is-active serial-console-logger.service 2>/dev/null || echo "serial-console-logger: inactive"
    systemctl is-active "serial-getty@$SERIAL_PORT.service" 2>/dev/null || echo "serial-getty: inactive"
    echo
    
    # 테스트 메시지 전송
    echo "테스트 메시지 전송:"
    echo "Test message from xen serial console setup - $(date)" | tee -a "$LOG_DIR/test-message.log"
}

# 사용법 출력
show_usage() {
    echo "사용법: $0 [명령어] [옵션]"
    echo
    echo "명령어:"
    echo "  setup          전체 직렬 콘솔 로깅 설정"
    echo "  test           설정 테스트 및 확인"
    echo "  monitor        실시간 직렬 콘솔 모니터링"
    echo "  connect        직렬 콘솔 연결"
    echo "  analyze        로그 분석"
    echo
    echo "옵션:"
    echo "  -h, --help     이 도움말 출력"
    echo "  --port PORT    직렬 포트 지정 (기본값: ttyS0)"
    echo "  --speed SPEED  직렬 통신 속도 (기본값: 115200)"
    echo
    echo "예시:"
    echo "  sudo $0 setup                    # 전체 설정"
    echo "  sudo $0 setup --port ttyS1       # ttyS1 포트 사용"
    echo "  sudo $0 test                     # 설정 테스트"
    echo "  sudo $0 monitor                  # 실시간 모니터링"
}

# 메인 함수
main() {
    local command="${1:-setup}"
    
    # 옵션 파싱
    while [[ $# -gt 0 ]]; do
        case $1 in
            --port)
                SERIAL_PORT="$2"
                shift 2
                ;;
            --speed)
                SERIAL_SPEED="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                command="$1"
                shift
                ;;
        esac
    done
    
    case "$command" in
        setup)
            init_serial_logging
            check_serial_hardware
            configure_grub_serial
            configure_systemd_serial
            configure_xen_serial
            create_serial_logging_service
            create_serial_monitor_tools
            setup_network_serial_logging
            setup_serial_log_rotation
            show_installation_summary
            ;;
        test)
            test_serial_configuration
            ;;
        monitor)
            if [[ -f /usr/local/bin/monitor-serial-console.sh ]]; then
                /usr/local/bin/monitor-serial-console.sh
            else
                log_error "모니터링 도구가 설치되지 않았습니다. 먼저 'setup'을 실행하세요."
            fi
            ;;
        connect)
            if [[ -f /usr/local/bin/connect-serial-console.sh ]]; then
                /usr/local/bin/connect-serial-console.sh
            else
                log_error "연결 도구가 설치되지 않았습니다. 먼저 'setup'을 실행하세요."
            fi
            ;;
        analyze)
            if [[ -f /usr/local/bin/analyze-serial-logs.sh ]]; then
                /usr/local/bin/analyze-serial-logs.sh
            else
                log_error "분석 도구가 설치되지 않았습니다. 먼저 'setup'을 실행하세요."
            fi
            ;;
        *)
            echo "알 수 없는 명령어: $command"
            show_usage
            exit 1
            ;;
    esac
}

# 스크립트 실행
main "$@"