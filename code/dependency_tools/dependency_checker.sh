#!/bin/bash
# dependency_checker.sh - 패키지 의존성 상태 검사 도구

echo "=== 시스템 패키지 의존성 상태 검사 ==="
echo "검사 시작 시간: $(date)"
echo

# 1. 손상된 패키지 검사
echo "1. 손상된 패키지 검사:"
broken_packages=$(dpkg -l | grep "^.H" | awk '{print $2}')
if [ -z "$broken_packages" ]; then
    echo "   ✓ 손상된 패키지 없음"
else
    echo "   ⚠ 손상된 패키지 발견:"
    echo "$broken_packages" | sed 's/^/     /'
fi
echo

# 2. 보류된 패키지 검사
echo "2. 보류된 패키지 검사:"
held_packages=$(apt-mark showhold)
if [ -z "$held_packages" ]; then
    echo "   ✓ 보류된 패키지 없음"
else
    echo "   ⚠ 보류된 패키지:"
    echo "$held_packages" | sed 's/^/     /'
fi
echo

# 3. 업그레이드 가능한 패키지 검사
echo "3. 업그레이드 가능한 패키지:"
upgradable=$(apt list --upgradable 2>/dev/null | grep -v "^Listing" | wc -l)
echo "   총 $upgradable 개 패키지 업그레이드 가능"
echo

# 4. PPA 저장소 검사
echo "4. 추가 저장소 (PPA) 목록:"
ppa_count=$(find /etc/apt/sources.list.d/ -name "*.list" 2>/dev/null | wc -l)
if [ $ppa_count -eq 0 ]; then
    echo "   ✓ 추가 저장소 없음"
else
    echo "   📋 $ppa_count 개의 추가 저장소 발견:"
    ls /etc/apt/sources.list.d/*.list 2>/dev/null | sed 's/^/     /'
fi
echo

# 5. 자동으로 제거 가능한 패키지
echo "5. 자동 제거 가능한 패키지:"
autoremovable=$(apt autoremove -s 2>/dev/null | grep "^Remv" | wc -l)
if [ $autoremovable -eq 0 ]; then
    echo "   ✓ 자동 제거 가능한 패키지 없음"
else
    echo "   📦 $autoremovable 개 패키지 자동 제거 가능"
fi
echo

echo "=== 검사 완료 ==="
echo "권장 사항:"
if [ ! -z "$broken_packages" ]; then
    echo "  - 손상된 패키지 수정: sudo apt -f install"
fi
if [ $upgradable -gt 0 ]; then
    echo "  - 패키지 업그레이드: sudo apt upgrade"
fi
if [ $autoremovable -gt 0 ]; then
    echo "  - 불필요한 패키지 제거: sudo apt autoremove"
fi