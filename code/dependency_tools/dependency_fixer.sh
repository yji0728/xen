#!/bin/bash
# dependency_fixer.sh - 자동 의존성 문제 해결 도구

set -e

echo "=== 패키지 의존성 자동 수정 도구 ==="
echo "시작 시간: $(date)"
echo

# 사용자 확인
read -p "패키지 의존성 자동 수정을 시작하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "작업이 취소되었습니다."
    exit 1
fi

# 백업 디렉토리 생성
backup_dir="/tmp/apt_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$backup_dir"

echo "1. 시스템 상태 백업 중..."
cp -r /etc/apt/sources.list* "$backup_dir/"
dpkg --get-selections > "$backup_dir/package_selections.txt"
echo "   백업 위치: $backup_dir"
echo

echo "2. 패키지 목록 업데이트 중..."
sudo apt update
echo

echo "3. 손상된 의존성 수정 중..."
sudo apt -f install -y
echo

echo "4. 패키지 데이터베이스 정리 중..."
sudo apt clean
sudo apt autoclean
echo

echo "5. 불완전한 패키지 설정 완료 중..."
sudo dpkg --configure -a
echo

echo "6. 시스템 업그레이드 시도 중..."
sudo apt upgrade -y
echo

echo "7. 불필요한 패키지 제거 중..."
sudo apt autoremove -y
echo

echo "=== 자동 수정 완료 ==="
echo "완료 시간: $(date)"
echo "백업 위치: $backup_dir"
echo
echo "문제가 지속되면 다음 명령을 시도해보세요:"
echo "  sudo aptitude install [문제_패키지]"
echo "  sudo ppa-purge [문제_ppa]"