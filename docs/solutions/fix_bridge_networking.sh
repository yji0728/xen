#!/bin/bash

# Ubuntu 브릿지 네트워킹 문제 해결 스크립트
# 작성자: MiniMax Agent
# 버전: 1.0
# 사용법: sudo ./fix_bridge_networking.sh

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
BACKUP_DIR="/root/network-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# 네트워크 설정 백업
backup_network_config() {
    log_info "네트워크 설정 백업 중..."
    
    # Netplan 구성 백업
    if [[ -d /etc/netplan ]]; then
        cp -r /etc/netplan "$BACKUP_DIR/"
        log_success "Netplan 구성 백업 완료"
    fi
    
    # 현재 네트워크 상태 저장
    ip addr show > "$BACKUP_DIR/ip_addr.backup"
    ip route show > "$BACKUP_DIR/ip_route.backup"
    
    if command -v brctl >/dev/null 2>&1; then
        brctl show > "$BACKUP_DIR/brctl_show.backup"
    fi
    
    # systemd 네트워크 서비스 상태
    systemctl status NetworkManager > "$BACKUP_DIR/networkmanager_status.backup" 2>&1 || true
    systemctl status systemd-networkd > "$BACKUP_DIR/systemd-networkd_status.backup" 2>&1 || true
    
    log_success "네트워크 설정 백업 완료: $BACKUP_DIR"
}

# 현재 네트워크 상태 진단
diagnose_network() {
    log_info "현재 네트워크 상태 진단 중..."
    
    echo "=== 네트워크 인터페이스 ==="
    ip addr show
    echo
    
    echo "=== 라우팅 테이블 ==="
    ip route show
    echo
    
    if command -v brctl >/dev/null 2>&1; then
        echo "=== 브릿지 상태 ==="
        brctl show
        echo
    fi
    
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
}

# 브릿지 문제 감지
detect_bridge_issues() {
    log_info "브릿지 관련 문제 감지 중..."
    
    local issues_found=0
    
    # 브릿지 인터페이스 확인
    if ! command -v brctl >/dev/null 2>&1; then
        log_warn "bridge-utils가 설치되지 않았습니다."
        ((issues_found++))
    fi
    
    # 충돌하는 네트워크 관리자 확인
    if systemctl is-active --quiet NetworkManager && systemctl is-active --quiet systemd-networkd; then
        log_warn "NetworkManager와 systemd-networkd가 모두 활성화되어 있습니다. 충돌 가능성이 있습니다."
        ((issues_found++))
    fi
    
    # Netplan 구성 파일 확인
    local netplan_files=$(find /etc/netplan -name "*.yaml" -o -name "*.yml" 2>/dev/null || true)
    if [[ -z "$netplan_files" ]]; then
        log_warn "Netplan 구성 파일을 찾을 수 없습니다."
        ((issues_found++))
    else
        for file in $netplan_files; do
            if ! yaml_lint "$file"; then
                log_warn "Netplan 파일 구문 오류: $file"
                ((issues_found++))
            fi
        done
    fi
    
    # iptables 규칙 확인
    if iptables -L | grep -q "DROP"; then
        log_warn "iptables에 DROP 규칙이 있습니다. 네트워크 트래픽을 차단할 수 있습니다."
        ((issues_found++))
    fi
    
    return $issues_found
}

# YAML 구문 검사 (간단한 버전)
yaml_lint() {
    local file="$1"
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null
    else
        # Python이 없는 경우 기본적인 검사만
        if grep -q $'\t' "$file"; then
            log_warn "$file에 탭 문자가 있습니다. YAML은 공백만 사용해야 합니다."
            return 1
        fi
        return 0
    fi
}

# 브릿지 인터페이스 생성/수정
create_bridge_interface() {
    log_info "브릿지 인터페이스 구성 중..."
    
    # 기본 물리 인터페이스 감지
    local physical_iface=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [[ -z "$physical_iface" ]]; then
        log_error "기본 네트워크 인터페이스를 찾을 수 없습니다."
        return 1
    fi
    
    log_info "감지된 기본 인터페이스: $physical_iface"
    
    # 현재 IP 주소 가져오기
    local current_ip=$(ip addr show "$physical_iface" | grep "inet " | awk '{print $2}' | head -1)
    local current_gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    
    log_info "현재 IP: $current_ip"
    log_info "현재 게이트웨이: $current_gateway"
    
    # Netplan 구성 파일 생성
    local netplan_file="/etc/netplan/01-netcfg.yaml"
    
    cat > "$netplan_file" << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $physical_iface:
      dhcp4: no
      dhcp6: no
  bridges:
    br0:
      interfaces: [$physical_iface]
      dhcp4: no
      dhcp6: no
      addresses: [$current_ip]
      routes:
        - to: default
          via: $current_gateway
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      parameters:
        stp: false
        forward-delay: 0
EOF
    
    log_success "Netplan 구성 파일 생성 완료: $netplan_file"
}

# NetworkManager 비활성화 및 systemd-networkd 활성화
configure_network_services() {
    log_info "네트워크 서비스 구성 중..."
    
    # NetworkManager 비활성화
    if systemctl is-active --quiet NetworkManager; then
        log_info "NetworkManager 비활성화 중..."
        systemctl stop NetworkManager
        systemctl disable NetworkManager
    fi
    
    # systemd-networkd 활성화
    if ! systemctl is-active --quiet systemd-networkd; then
        log_info "systemd-networkd 활성화 중..."
        systemctl enable systemd-networkd
        systemctl start systemd-networkd
    fi
    
    # systemd-resolved 활성화 (DNS 해결을 위해)
    if ! systemctl is-active --quiet systemd-resolved; then
        log_info "systemd-resolved 활성화 중..."
        systemctl enable systemd-resolved
        systemctl start systemd-resolved
    fi
}

# 방화벽 규칙 정리
configure_firewall() {
    log_info "방화벽 규칙 확인 및 구성 중..."
    
    # iptables 규칙 확인
    if iptables -L | grep -q "FORWARD.*DROP"; then
        log_warn "FORWARD 체인에 DROP 규칙이 있습니다."
        
        read -p "브릿지 트래픽을 허용하기 위해 FORWARD 정책을 ACCEPT로 변경하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            iptables -P FORWARD ACCEPT
            log_success "FORWARD 정책이 ACCEPT로 변경되었습니다."
            
            # 영구 저장
            if command -v iptables-save >/dev/null 2>&1; then
                iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
            fi
        fi
    fi
    
    # 브릿지 관련 커널 모듈 확인
    modprobe bridge
    
    # br_netfilter 설정
    echo "net.bridge.bridge-nf-call-iptables = 0" >> /etc/sysctl.conf
    echo "net.bridge.bridge-nf-call-ip6tables = 0" >> /etc/sysctl.conf
    echo "net.bridge.bridge-nf-call-arptables = 0" >> /etc/sysctl.conf
    
    sysctl -p
}

# Netplan 적용
apply_netplan() {
    log_info "Netplan 구성 적용 중..."
    
    # 구성 검증
    if ! netplan try --timeout 30; then
        log_error "Netplan 구성 적용에 실패했습니다."
        log_info "백업에서 복원 중..."
        restore_backup
        return 1
    fi
    
    # 영구 적용
    netplan apply
    log_success "Netplan 구성이 성공적으로 적용되었습니다."
}

# 백업 복원
restore_backup() {
    log_warn "백업에서 네트워크 구성 복원 중..."
    
    if [[ -d "$BACKUP_DIR/netplan" ]]; then
        rm -rf /etc/netplan/*
        cp -r "$BACKUP_DIR/netplan/"* /etc/netplan/
        netplan apply
        log_success "백업에서 Netplan 구성이 복원되었습니다."
    fi
}

# 연결성 테스트
test_connectivity() {
    log_info "네트워크 연결성 테스트 중..."
    
    # 게이트웨이 ping 테스트
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    if ping -c 3 "$gateway" >/dev/null 2>&1; then
        log_success "게이트웨이($gateway) ping 성공"
    else
        log_error "게이트웨이($gateway) ping 실패"
        return 1
    fi
    
    # 외부 DNS 테스트
    if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
        log_success "외부 DNS(8.8.8.8) ping 성공"
    else
        log_error "외부 DNS(8.8.8.8) ping 실패"
        return 1
    fi
    
    # 도메인 이름 해결 테스트
    if nslookup google.com >/dev/null 2>&1; then
        log_success "도메인 이름 해결 테스트 성공"
    else
        log_warn "도메인 이름 해결 테스트 실패"
    fi
    
    log_success "기본 네트워크 연결성 테스트 통과"
}

# 가상 머신 네트워크 테스트 (옵션)
test_vm_connectivity() {
    log_info "가상 머신 네트워크 설정 확인 중..."
    
    if command -v virsh >/dev/null 2>&1; then
        # libvirt 네트워크 확인
        virsh net-list --all
        
        # 브릿지에 연결된 VM 확인
        if [[ -f /proc/net/dev ]] && grep -q "tap" /proc/net/dev; then
            log_info "TAP 인터페이스가 감지되었습니다."
            ip link show | grep tap
        fi
    else
        log_info "libvirt가 설치되지 않았습니다. VM 테스트를 건너뜁니다."
    fi
}

# 진단 정보 수집
collect_diagnostic_info() {
    log_info "진단 정보 수집 중..."
    
    local diag_file="$BACKUP_DIR/network_diagnostic.txt"
    
    {
        echo "=== 네트워크 진단 정보 ==="
        echo "날짜: $(date)"
        echo "Ubuntu 버전: $(lsb_release -d | cut -f2)"
        echo "커널 버전: $(uname -r)"
        echo
        echo "=== 네트워크 인터페이스 ==="
        ip addr show
        echo
        echo "=== 라우팅 테이블 ==="
        ip route show
        echo
        echo "=== 브릿지 상태 ==="
        brctl show 2>/dev/null || echo "brctl 명령어 없음"
        echo
        echo "=== Netplan 구성 ==="
        for file in /etc/netplan/*.yaml /etc/netplan/*.yml; do
            if [[ -f "$file" ]]; then
                echo "--- $file ---"
                cat "$file"
                echo
            fi
        done
        echo
        echo "=== 네트워크 서비스 상태 ==="
        systemctl status NetworkManager --no-pager -l || true
        systemctl status systemd-networkd --no-pager -l || true
        echo
        echo "=== iptables 규칙 ==="
        iptables -L -n -v
        echo
        echo "=== 시스템 로그 (네트워크 관련) ==="
        journalctl -u systemd-networkd --no-pager -l | tail -50
    } > "$diag_file"
    
    log_success "진단 정보가 $diag_file에 저장되었습니다."
}

# 메인 실행 함수
main() {
    echo "=================================================="
    echo "Ubuntu 브릿지 네트워킹 문제 해결 스크립트"
    echo "=================================================="
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        exit 1
    fi
    
    # 경고 메시지
    log_warn "이 스크립트는 네트워크 구성을 변경합니다."
    log_warn "원격 접속 중이라면 연결이 끊어질 수 있습니다."
    
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "스크립트 실행이 취소되었습니다."
        exit 0
    fi
    
    # 필수 패키지 설치
    log_info "필수 패키지 설치 중..."
    apt update
    apt install -y bridge-utils netplan.io
    
    # 단계별 실행
    backup_network_config
    diagnose_network
    
    if detect_bridge_issues; then
        log_info "문제가 감지되었습니다. 수정을 시작합니다."
        
        create_bridge_interface
        configure_network_services
        configure_firewall
        
        if apply_netplan; then
            sleep 5  # 네트워크 재구성 대기
            
            if test_connectivity; then
                log_success "네트워크 구성이 성공적으로 완료되었습니다!"
                test_vm_connectivity
            else
                log_error "네트워크 연결성 테스트에 실패했습니다."
                restore_backup
            fi
        fi
    else
        log_success "심각한 브릿지 네트워크 문제가 감지되지 않았습니다."
    fi
    
    collect_diagnostic_info
    
    echo
    log_info "백업 파일들: $BACKUP_DIR"
    log_info "복원이 필요한 경우: $BACKUP_DIR의 백업 파일들을 사용하세요."
    
    echo
    echo "=== 최종 네트워크 상태 ==="
    ip addr show br0 2>/dev/null || log_warn "br0 인터페이스가 없습니다."
    brctl show 2>/dev/null || log_warn "브릿지 정보를 가져올 수 없습니다."
    
    log_success "브릿지 네트워킹 문제 해결 완료!"
}

main "$@"