#!/bin/bash
# install_tools.sh - 의존성 관리 도구 설치 스크립트

INSTALL_DIR="/usr/local/bin"
TOOLS_DIR="$(dirname "$0")"

echo "=== 패키지 의존성 관리 도구 설치 ==="
echo

# 관리자 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "이 스크립트는 관리자 권한이 필요합니다."
    echo "sudo $0 를 사용해서 실행하세요."
    exit 1
fi

# 필수 패키지 설치
echo "1. 필수 패키지 설치 중..."
apt update
apt install -y ppa-purge aptitude curl wget

echo "2. 도구 스크립트 설치 중..."

# 스크립트 파일들 복사 및 실행 권한 부여
tools=(
    "dependency_checker.sh"
    "dependency_fixer.sh"
    "ppa_manager.sh"
    "system_monitor.sh"
)

for tool in "${tools[@]}"; do
    if [ -f "$TOOLS_DIR/$tool" ]; then
        echo "   설치 중: $tool"
        cp "$TOOLS_DIR/$tool" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/$tool"
    else
        echo "   ⚠ 파일 없음: $tool"
    fi
done

echo "3. 시스템 모니터링 cron 작업 설정 중..."

# cron daily 스크립트 생성
cat > /etc/cron.daily/dependency-monitor << 'EOF'
#!/bin/bash
# 매일 패키지 의존성 상태 검사

/usr/local/bin/system_monitor.sh
/usr/local/bin/dependency_checker.sh > /var/log/dependency-check-$(date +%Y%m%d).log 2>&1
EOF

chmod +x /etc/cron.daily/dependency-monitor

echo "4. 로그 디렉토리 설정 중..."
mkdir -p /var/log/dependency-tools
touch /var/log/system-monitor.log
chmod 644 /var/log/system-monitor.log

echo
echo "=== 설치 완료 ==="
echo
echo "사용 가능한 명령어:"
echo "  dependency_checker.sh  - 시스템 의존성 상태 검사"
echo "  dependency_fixer.sh    - 자동 의존성 문제 해결"
echo "  ppa_manager.sh         - PPA 관리 도구"
echo "  system_monitor.sh      - 시스템 모니터링"
echo
echo "매일 자동 검사가 설정되었습니다."
echo "로그 위치: /var/log/system-monitor.log"
echo
echo "예제 사용법:"
echo "  dependency_checker.sh"
echo "  ppa_manager.sh list"
echo "  ppa_manager.sh check"