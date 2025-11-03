#!/bin/bash

#==============================================================================
# Xen 테스트 시스템 통합 실행 스크립트
# 작성자: MiniMax Agent
# 버전: 1.0
# 날짜: 2025-10-29
#
# 목적:
# - 모든 Xen 테스트를 체계적으로 순서대로 실행
# - 각 테스트 결과를 종합하여 최종 평가 제공
# - 실패 시 상세한 진단 정보 제공
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
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 로그 파일 설정
MASTER_LOG_DIR="/tmp/xen_complete_test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$MASTER_LOG_DIR"
MASTER_LOG="$MASTER_LOG_DIR/complete_test.log"
SUMMARY_REPORT="$MASTER_LOG_DIR/test_summary.json"

# 스크립트 디렉토리
SCRIPT_DIR="/workspace/code/xen_testing_system"

# 테스트 결과 추적
declare -A TEST_RESULTS
declare -A TEST_LOGS
declare -A TEST_DURATIONS

# 전체 통계
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

#==============================================================================
# 로깅 함수들
#==============================================================================

log_header() {
    echo -e "${BOLD}${BLUE}======================================${NC}" | tee -a "$MASTER_LOG"
    echo -e "${BOLD}${BLUE}$1${NC}" | tee -a "$MASTER_LOG"
    echo -e "${BOLD}${BLUE}======================================${NC}" | tee -a "$MASTER_LOG"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$MASTER_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$MASTER_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$MASTER_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$MASTER_LOG"
}

log_phase() {
    echo -e "${PURPLE}[PHASE]${NC} $1" | tee -a "$MASTER_LOG"
}

log_result() {
    echo -e "${CYAN}[RESULT]${NC} $1" | tee -a "$MASTER_LOG"
}

#==============================================================================
# 시스템 사전 확인
#==============================================================================

check_prerequisites() {
    log_header "시스템 사전 확인"
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 루트 권한이 필요합니다"
        log_info "다음 명령으로 실행하세요: sudo $0"
        exit 1
    fi
    
    log_success "루트 권한 확인됨"
    
    # 필수 명령어 확인
    local required_commands=(
        "lscpu"
        "lspci"
        "dmidecode"
        "lsb_release"
        "apt"
        "systemctl"
        "uname"
    )
    
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_success "명령어 가용: $cmd"
        else
            missing_commands+=("$cmd")
            log_error "명령어 누락: $cmd"
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "필수 명령어 누락: ${missing_commands[*]}"
        log_info "다음 패키지 설치 필요: apt install dmidecode lshw pciutils"
        exit 1
    fi
    
    # 테스트 스크립트 존재 확인
    local test_scripts=(
        "$SCRIPT_DIR/xen_system_tester.sh"
        "$SCRIPT_DIR/ubuntu_22_04_tester.sh"
        "$SCRIPT_DIR/ubuntu_24_04_tester.sh"
        "$SCRIPT_DIR/hardware_compatibility_tester.sh"
        "$SCRIPT_DIR/logging_system_verifier.sh"
    )
    
    local missing_scripts=()
    
    for script in "${test_scripts[@]}"; do
        if [[ -f "$script" ]]; then
            log_success "테스트 스크립트 존재: $(basename "$script")"
        else
            missing_scripts+=("$script")
            log_error "테스트 스크립트 누락: $(basename "$script")"
        fi
    done
    
    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        log_error "필수 테스트 스크립트 누락"
        exit 1
    fi
    
    # 네트워크 연결 확인
    if ping -c 1 archive.ubuntu.com >/dev/null 2>&1; then
        log_success "인터넷 연결 확인됨"
    else
        log_warning "인터넷 연결 불안정 - 일부 테스트가 실패할 수 있음"
    fi
    
    log_success "모든 사전 조건 충족"
}

#==============================================================================
# 개별 테스트 실행
#==============================================================================

run_individual_test() {
    local test_name="$1"
    local script_path="$2"
    local optional="${3:-false}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    log_phase "테스트 시작: $test_name"
    
    # 스크립트 실행 권한 확인
    if [[ ! -x "$script_path" ]]; then
        log_info "실행 권한 부여: $(basename "$script_path")"
        chmod +x "$script_path" || true
    fi
    
    # 테스트 실행
    local start_time=$(date +%s)
    local test_output_dir=""
    
    if "$script_path" >"$MASTER_LOG_DIR/$(basename "$test_name").log" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        TEST_RESULTS["$test_name"]="PASSED"
        TEST_DURATIONS["$test_name"]=$duration
        PASSED_TESTS=$((PASSED_TESTS + 1))
        
        log_success "$test_name 성공 (소요시간: ${duration}초)"
        
        # 테스트 로그 디렉토리 찾기
        test_output_dir=$(find /tmp -name "*$(echo "$test_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')*" -type d -newer "$script_path" 2>/dev/null | head -1)
        if [[ -n "$test_output_dir" ]]; then
            TEST_LOGS["$test_name"]="$test_output_dir"
            log_info "테스트 상세 로그: $test_output_dir"
        fi
        
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        TEST_DURATIONS["$test_name"]=$duration
        
        if [[ "$optional" == "true" ]]; then
            TEST_RESULTS["$test_name"]="SKIPPED"
            SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
            log_warning "$test_name 스킵됨 (선택적 테스트)"
        else
            TEST_RESULTS["$test_name"]="FAILED"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            log_error "$test_name 실패 (소요시간: ${duration}초)"
            
            # 실패 로그 표시
            log_error "실패 상세 정보:"
            tail -20 "$MASTER_LOG_DIR/$(basename "$test_name").log" | while read line; do
                log_error "  $line"
            done
        fi
        
        return 1
    fi
}

#==============================================================================
# Ubuntu 버전 감지 및 적절한 테스트 선택
#==============================================================================

detect_ubuntu_version() {
    local ubuntu_version=""
    
    if command -v lsb_release >/dev/null 2>&1; then
        ubuntu_version=$(lsb_release -rs)
    fi
    
    case "$ubuntu_version" in
        "22.04")
            log_info "Ubuntu 22.04 LTS 감지됨"
            echo "22.04"
            ;;
        "24.04")
            log_info "Ubuntu 24.04 LTS 감지됨"
            echo "24.04"
            ;;
        *)
            log_warning "지원되지 않는 Ubuntu 버전: $ubuntu_version"
            log_info "가장 가까운 버전으로 테스트 진행"
            
            # 버전 번호 비교로 가장 가까운 버전 선택
            if [[ "$ubuntu_version" > "23.00" ]]; then
                echo "24.04"
            else
                echo "22.04"
            fi
            ;;
    esac
}

#==============================================================================
# 메인 테스트 시퀀스
#==============================================================================

run_all_tests() {
    log_header "Xen 완전 테스트 시퀀스 시작"
    
    local ubuntu_version
    ubuntu_version=$(detect_ubuntu_version)
    
    # 1. 로깅 시스템 검증 (사전 확인)
    log_phase "1/5: 로깅 시스템 검증"
    run_individual_test "로깅 시스템 검증" "$SCRIPT_DIR/logging_system_verifier.sh" "true"
    
    # 2. 하드웨어 호환성 테스트
    log_phase "2/5: 하드웨어 호환성 테스트"
    run_individual_test "하드웨어 호환성" "$SCRIPT_DIR/hardware_compatibility_tester.sh"
    
    # 3. Ubuntu 버전별 테스트
    log_phase "3/5: Ubuntu 버전별 테스트"
    case "$ubuntu_version" in
        "22.04")
            run_individual_test "Ubuntu 22.04 호환성" "$SCRIPT_DIR/ubuntu_22_04_tester.sh"
            run_individual_test "Ubuntu 24.04 호환성" "$SCRIPT_DIR/ubuntu_24_04_tester.sh" "true"
            ;;
        "24.04")
            run_individual_test "Ubuntu 24.04 호환성" "$SCRIPT_DIR/ubuntu_24_04_tester.sh"
            run_individual_test "Ubuntu 22.04 호환성" "$SCRIPT_DIR/ubuntu_22_04_tester.sh" "true"
            ;;
        *)
            run_individual_test "Ubuntu 22.04 호환성" "$SCRIPT_DIR/ubuntu_22_04_tester.sh" "true"
            run_individual_test "Ubuntu 24.04 호환성" "$SCRIPT_DIR/ubuntu_24_04_tester.sh" "true"
            ;;
    esac
    
    # 4. 통합 시스템 테스트
    log_phase "4/5: 통합 시스템 테스트"
    run_individual_test "통합 시스템 테스트" "$SCRIPT_DIR/xen_system_tester.sh"
    
    # 5. 최종 검증 및 권장사항
    log_phase "5/5: 최종 검증 완료"
    log_success "모든 테스트 시퀀스 완료"
}

#==============================================================================
# 테스트 결과 분석
#==============================================================================

analyze_test_results() {
    log_header "테스트 결과 분석"
    
    # 전체 통계
    log_result "총 테스트: $TOTAL_TESTS"
    log_result "성공: $PASSED_TESTS"
    log_result "실패: $FAILED_TESTS"
    log_result "스킵: $SKIPPED_TESTS"
    
    local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    log_result "성공률: $success_rate%"
    
    # 개별 테스트 결과
    echo ""
    log_info "=== 개별 테스트 결과 ==="
    for test_name in "${!TEST_RESULTS[@]}"; do
        local status="${TEST_RESULTS[$test_name]}"
        local duration="${TEST_DURATIONS[$test_name]}"
        
        case "$status" in
            "PASSED")
                log_success "$test_name: 성공 (${duration}초)"
                ;;
            "FAILED")
                log_error "$test_name: 실패 (${duration}초)"
                ;;
            "SKIPPED")
                log_warning "$test_name: 스킵됨 (${duration}초)"
                ;;
        esac
    done
    
    # 실패한 테스트에 대한 권장사항
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo ""
        log_warning "=== 실패한 테스트 해결 방안 ==="
        
        for test_name in "${!TEST_RESULTS[@]}"; do
            if [[ "${TEST_RESULTS[$test_name]}" == "FAILED" ]]; then
                case "$test_name" in
                    *"하드웨어"*)
                        log_info "$test_name: 하드웨어 사양 확인 및 BIOS 설정 검토 필요"
                        ;;
                    *"Ubuntu"*)
                        log_info "$test_name: 패키지 저장소 업데이트 및 커널 버전 확인 필요"
                        ;;
                    *"통합"*)
                        log_info "$test_name: 전체 시스템 설정 재검토 및 의존성 확인 필요"
                        ;;
                    *)
                        log_info "$test_name: 상세 로그 확인 및 문제 해결 가이드 참조"
                        ;;
                esac
            fi
        done
    fi
    
    # 전체 평가
    echo ""
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "=== 전체 평가: Xen 설치 준비 완료 ==="
        log_success "모든 필수 테스트를 통과했습니다"
        log_success "Xen 하이퍼바이저 설치를 진행할 수 있습니다"
    elif [[ $success_rate -ge 80 ]]; then
        log_warning "=== 전체 평가: 조건부 설치 가능 ==="
        log_warning "일부 테스트가 실패했지만 핵심 기능은 정상입니다"
        log_warning "실패한 항목을 해결한 후 설치를 진행하세요"
    else
        log_error "=== 전체 평가: 설치 권장하지 않음 ==="
        log_error "중요한 테스트들이 실패했습니다"
        log_error "문제를 해결한 후 다시 테스트를 실행하세요"
    fi
}

#==============================================================================
# JSON 요약 리포트 생성
#==============================================================================

generate_summary_report() {
    log_info "요약 리포트 생성 중"
    
    # 테스트 결과를 JSON 형식으로 변환
    local test_results_json="{"
    local first_test=true
    
    for test_name in "${!TEST_RESULTS[@]}"; do
        if [[ "$first_test" == "true" ]]; then
            first_test=false
        else
            test_results_json+=","
        fi
        
        test_results_json+="\"$test_name\":{"
        test_results_json+="\"status\":\"${TEST_RESULTS[$test_name]}\","
        test_results_json+="\"duration\":${TEST_DURATIONS[$test_name]}"
        
        if [[ -n "${TEST_LOGS[$test_name]:-}" ]]; then
            test_results_json+=",\"log_directory\":\"${TEST_LOGS[$test_name]}\""
        fi
        
        test_results_json+="}"
    done
    test_results_json+="}"
    
    # 전체 리포트 생성
    cat > "$SUMMARY_REPORT" << EOF
{
  "test_summary": {
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "ubuntu_version": "$(lsb_release -rs 2>/dev/null || echo 'unknown')",
    "kernel_version": "$(uname -r)",
    "test_directory": "$MASTER_LOG_DIR"
  },
  "overall_results": {
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "skipped_tests": $SKIPPED_TESTS,
    "success_rate": $((PASSED_TESTS * 100 / TOTAL_TESTS))
  },
  "individual_results": $test_results_json,
  "recommendation": {
    "xen_installation_ready": $([ $FAILED_TESTS -eq 0 ] && echo "true" || echo "false"),
    "critical_issues": $FAILED_TESTS,
    "overall_status": "$([ $FAILED_TESTS -eq 0 ] && echo "READY" || [ $((PASSED_TESTS * 100 / TOTAL_TESTS)) -ge 80 ] && echo "CONDITIONAL" || echo "NOT_READY")"
  }
}
EOF

    log_success "요약 리포트 생성됨: $SUMMARY_REPORT"
}

#==============================================================================
# 정리 및 마무리
#==============================================================================

cleanup_and_finish() {
    log_header "테스트 완료 및 정리"
    
    # 로그 파일 압축 (선택적)
    if command -v gzip >/dev/null 2>&1; then
        log_info "로그 파일 압축 중"
        gzip "$MASTER_LOG_DIR"/*.log 2>/dev/null || true
        log_success "로그 파일 압축 완료"
    fi
    
    # 결과 요약 출력
    echo ""
    log_info "=== 최종 결과 요약 ==="
    log_info "테스트 디렉토리: $MASTER_LOG_DIR"
    log_info "마스터 로그: $MASTER_LOG"
    log_info "요약 리포트: $SUMMARY_REPORT"
    
    # 다음 단계 안내
    echo ""
    log_info "=== 다음 단계 ==="
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "1. Xen 설치 시스템 실행: /workspace/code/xen_installer/xen_reliable_installer.sh"
        log_success "2. 설치 후 로깅 시스템 활성화: /workspace/code/xen_logging_system/"
        log_success "3. 설치 완료 후 검증 테스트 재실행"
    else
        log_warning "1. 실패한 테스트 로그 확인: $MASTER_LOG_DIR/"
        log_warning "2. 문제 해결 후 테스트 재실행: $0"
        log_warning "3. 해결 방안 문서 참조: /workspace/docs/solutions/"
    fi
    
    echo ""
    log_header "Xen 테스트 시스템 완료"
}

#==============================================================================
# 메인 실행 함수
#==============================================================================

main() {
    # 시작 시간 기록
    local start_time=$(date +%s)
    
    log_header "Xen 완전 테스트 시스템 v1.0"
    log_info "작성자: MiniMax Agent"
    log_info "시작 시간: $(date)"
    log_info "테스트 디렉토리: $MASTER_LOG_DIR"
    
    # 실행 단계
    check_prerequisites
    run_all_tests
    analyze_test_results
    generate_summary_report
    cleanup_and_finish
    
    # 총 실행 시간 계산
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    log_info "총 실행 시간: ${total_duration}초"
    
    # 종료 코드 설정
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "모든 테스트 성공 - 종료 코드: 0"
        exit 0
    else
        log_error "일부 테스트 실패 - 종료 코드: 1"
        exit 1
    fi
}

# 스크립트 직접 실행 시에만 main 함수 호출
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi