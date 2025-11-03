# 패키지 의존성 관리 도구 사용 가이드

## 개요

이 도구 모음은 Ubuntu 시스템에서 패키지 의존성 충돌 문제를 효과적으로 해결하기 위해 개발되었습니다. 4개의 핵심 스크립트와 1개의 설치 스크립트로 구성되어 있습니다.

## 설치 방법

```bash
# 저장소 디렉토리로 이동
cd code/dependency_tools

# 설치 스크립트 실행 (관리자 권한 필요)
sudo bash install_tools.sh
```

## 도구 목록

### 1. dependency_checker.sh
시스템의 패키지 의존성 상태를 종합적으로 검사하는 도구입니다.

**기능:**
- 손상된 패키지 검출
- 보류된 패키지 확인
- 업그레이드 가능한 패키지 수 확인
- 설치된 PPA 목록 표시
- 자동 제거 가능한 패키지 확인

**사용법:**
```bash
dependency_checker.sh
```

**출력 예시:**
```
=== 시스템 패키지 의존성 상태 검사 ===
1. 손상된 패키지 검사:
   ✓ 손상된 패키지 없음

2. 보류된 패키지 검사:
   ⚠ 보류된 패키지:
     linux-image-generic
     
3. 업그레이드 가능한 패키지:
   총 15 개 패키지 업그레이드 가능
```

### 2. dependency_fixer.sh
감지된 의존성 문제를 자동으로 해결하는 도구입니다.

**기능:**
- 자동 백업 생성
- 손상된 의존성 수정
- 패키지 데이터베이스 정리
- 시스템 업그레이드
- 불필요한 패키지 제거

**사용법:**
```bash
dependency_fixer.sh
```

**주의사항:**
- 시스템에 중요한 변경을 가하므로 실행 전 백업 권장
- 스크립트가 자동으로 임시 백업을 생성함

### 3. ppa_manager.sh
PPA 저장소를 관리하고 관련 문제를 해결하는 도구입니다.

**기능:**
- PPA 목록 표시
- PPA 상태 검사
- 문제가 있는 PPA 자동 정리
- PPA 백업 및 복원

**사용법:**
```bash
# PPA 목록 확인
ppa_manager.sh list

# PPA 상태 검사
ppa_manager.sh check

# PPA 백업 생성
ppa_manager.sh backup

# 문제가 있는 PPA 정리
ppa_manager.sh clean
```

### 4. system_monitor.sh
시스템의 패키지 상태를 정기적으로 모니터링하는 도구입니다.

**기능:**
- 자동화된 시스템 상태 검사
- 문제 발생 시 로그 기록
- 임계값 기반 알림
- cron을 통한 정기 실행

**사용법:**
```bash
# 수동 실행
system_monitor.sh

# 설치 후 매일 자동으로 /etc/cron.daily/에서 실행됨
```

**로그 위치:**
- `/var/log/system-monitor.log`
- `/var/log/dependency-check-YYYYMMDD.log`

## 일반적인 사용 시나리오

### 시나리오 1: 정기적인 시스템 점검
```bash
# 1. 시스템 상태 확인
dependency_checker.sh

# 2. PPA 상태 확인
ppa_manager.sh check

# 3. 필요시 자동 수정
dependency_fixer.sh
```

### 시나리오 2: PPA 관련 문제 해결
```bash
# 1. PPA 목록 확인
ppa_manager.sh list

# 2. 문제가 있는 PPA 검사
ppa_manager.sh check

# 3. 문제가 있는 PPA 정리
ppa_manager.sh clean
```

### 시나리오 3: 패키지 설치 실패 시
```bash
# 1. 현재 상태 진단
dependency_checker.sh

# 2. 자동 수정 시도
dependency_fixer.sh

# 3. 문제가 지속되면 수동 해결
sudo aptitude install [패키지명]
```

## 설정 파일

### 모니터링 임계값 변경
`system_monitor.sh` 스크립트 내의 `ALERT_THRESHOLD` 값을 수정하여 알림 임계값을 조정할 수 있습니다:

```bash
sudo nano /usr/local/bin/system_monitor.sh
# ALERT_THRESHOLD=10 을 원하는 값으로 변경
```

### cron 일정 변경
```bash
# daily에서 다른 주기로 변경하려면
sudo mv /etc/cron.daily/dependency-monitor /etc/cron.weekly/
```

## 문제 해결

### 도구가 실행되지 않는 경우
```bash
# 실행 권한 확인 및 부여
ls -l /usr/local/bin/dependency_*.sh
sudo chmod +x /usr/local/bin/dependency_*.sh
```

### 로그 파일에 접근할 수 없는 경우
```bash
# 로그 디렉토리 권한 확인
sudo ls -la /var/log/system-monitor.log
sudo chmod 644 /var/log/system-monitor.log
```

### PPA-purge 관련 오류
```bash
# ppa-purge가 설치되지 않은 경우
sudo apt update
sudo apt install ppa-purge
```

## 제거 방법

도구를 완전히 제거하려면:

```bash
# 스크립트 파일 제거
sudo rm /usr/local/bin/dependency_*.sh
sudo rm /usr/local/bin/ppa_manager.sh
sudo rm /usr/local/bin/system_monitor.sh

# cron 작업 제거
sudo rm /etc/cron.daily/dependency-monitor

# 로그 파일 제거 (선택사항)
sudo rm /var/log/system-monitor.log
sudo rm /var/log/dependency-check-*.log
```

## 추가 도움말

더 자세한 정보는 다음 문서를 참조하세요:
- `docs/solutions/dependency_conflict_solutions.md` - 완전한 해결 방안 가이드
- `man apt` - APT 패키지 관리자 메뉴얼
- `man dpkg` - 저수준 패키지 관리자 메뉴얼