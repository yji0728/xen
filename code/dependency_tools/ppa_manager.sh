#!/bin/bash
# ppa_manager.sh - PPA 관리 자동화 도구

show_usage() {
    echo "사용법: $0 [옵션]"
    echo "옵션:"
    echo "  list      - 설치된 PPA 목록 표시"
    echo "  check     - PPA 상태 검사"
    echo "  backup    - PPA 목록 백업"
    echo "  restore   - PPA 목록 복원"
    echo "  clean     - 문제가 있는 PPA 정리"
}

list_ppas() {
    echo "=== 설치된 PPA 목록 ==="
    if [ -d "/etc/apt/sources.list.d" ]; then
        for file in /etc/apt/sources.list.d/*.list; do
            if [ -f "$file" ]; then
                echo "파일: $(basename $file)"
                grep -E "^deb.*ppa" "$file" | sed 's/^/  /'
                echo
            fi
        done
    else
        echo "PPA가 설치되어 있지 않습니다."
    fi
}

check_ppas() {
    echo "=== PPA 상태 검사 ==="
    
    temp_file=$(mktemp)
    sudo apt update 2>&1 | tee "$temp_file"
    
    # 실패한 저장소 검사
    failed_repos=$(grep -i "failed\|error\|could not" "$temp_file" | grep -o "ppa:[^/]*/[^[:space:]]*" | sort | uniq)
    
    if [ ! -z "$failed_repos" ]; then
        echo "⚠ 문제가 있는 PPA 발견:"
        echo "$failed_repos" | sed 's/^/  /'
        echo
        echo "다음 명령으로 문제가 있는 PPA를 제거할 수 있습니다:"
        echo "$failed_repos" | sed 's/^/  sudo ppa-purge /'
    else
        echo "✓ 모든 PPA가 정상 상태입니다."
    fi
    
    rm -f "$temp_file"
}

backup_ppas() {
    backup_file="ppa_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    echo "=== PPA 백업 생성 ==="
    sudo tar -czf "$backup_file" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✓ PPA 백업이 생성되었습니다: $backup_file"
    else
        echo "⚠ 백업 생성에 실패했습니다."
    fi
}

clean_ppas() {
    echo "=== 문제가 있는 PPA 자동 정리 ==="
    
    # 임시 파일로 업데이트 테스트
    temp_file=$(mktemp)
    sudo apt update 2>&1 | tee "$temp_file"
    
    # 실패한 PPA 추출
    failed_ppas=$(grep -i "failed\|error" "$temp_file" | grep -o "ppa:[^/]*/[^[:space:]]*" | sort | uniq)
    
    if [ ! -z "$failed_ppas" ]; then
        echo "다음 PPA들에서 문제가 발견되었습니다:"
        echo "$failed_ppas" | sed 's/^/  /'
        echo
        
        read -p "이 PPA들을 자동으로 제거하시겠습니까? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$failed_ppas" | while read ppa; do
                echo "제거 중: $ppa"
                sudo ppa-purge "$ppa" || echo "⚠ $ppa 제거 실패"
            done
            
            echo "PPA 정리 완료. 시스템 업데이트 중..."
            sudo apt update
        fi
    else
        echo "✓ 문제가 있는 PPA가 없습니다."
    fi
    
    rm -f "$temp_file"
}

# 메인 로직
case "$1" in
    list)
        list_ppas
        ;;
    check)
        check_ppas
        ;;
    backup)
        backup_ppas
        ;;
    clean)
        clean_ppas
        ;;
    *)
        show_usage
        exit 1
        ;;
esac