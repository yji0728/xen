# Xen 부팅 과정 전체 로그 기록 시스템 v1.0

BIOS/UEFI부터 게스트 도메인까지 Xen 환경의 완전한 부팅 과정을 기록하고 분석하는 통합 로깅 시스템입니다.

## 🎯 주요 특징

- **전체 부팅 과정 커버**: BIOS/UEFI → 부트로더 → Xen 하이퍼바이저 → Dom0 → 게스트 도메인
- **실시간 모니터링**: 부팅 과정과 운영 중 이벤트 실시간 추적
- **직렬 콘솔 지원**: 원격 모니터링 및 헤드리스 서버 지원
- **자동 게스트 감지**: 새로운 도메인 자동 발견 및 로깅 설정
- **포괄적 분석**: HTML 보고서를 통한 시각적 분석
- **성능 모니터링**: 리소스 사용량 및 성능 메트릭 수집

## 📁 시스템 구조

```
xen_logging_system/
├── xen_boot_logger.sh              # 메인 부팅 로그 시스템
├── serial_console_logger.sh        # 직렬 콘솔 로깅 설정
├── guest_domain_logger.sh          # 게스트 도메인 전용 로깅
├── README.md                       # 이 파일
└── logs/ (생성됨)
    ├── /var/log/xen-boot-logging/
    │   ├── bios-uefi/              # BIOS/UEFI 로그
    │   ├── bootloader/             # GRUB 부트로더 로그  
    │   ├── xen-hypervisor/         # Xen 하이퍼바이저 로그
    │   ├── dom0-kernel/            # Dom0 커널 로그
    │   ├── guest-domains/          # 게스트 도메인 로그
    │   ├── system-services/        # 시스템 서비스 로그
    │   └── analysis/               # 분석 보고서
    ├── /var/log/xen-serial-console/
    └── /var/log/xen-guest-logging/
```

## 🚀 빠른 시작

### 1단계: 메인 부팅 로그 시스템 설정

전체 부팅 과정 로깅을 설정합니다:

```bash
chmod +x xen_boot_logger.sh
sudo ./xen_boot_logger.sh setup
```

### 2단계: 직렬 콘솔 로깅 설정 (선택사항)

원격 모니터링을 위한 직렬 콘솔을 설정합니다:

```bash
chmod +x serial_console_logger.sh
sudo ./serial_console_logger.sh setup
```

### 3단계: 게스트 도메인 로깅 설정

게스트 가상머신 로깅을 설정합니다:

```bash
chmod +x guest_domain_logger.sh
sudo ./guest_domain_logger.sh setup
```

### 4단계: 시스템 재부팅

로깅 설정을 활성화하기 위해 재부팅합니다:

```bash
sudo reboot
```

## 📊 로그 수집 범위

### BIOS/UEFI 단계
- **UEFI 변수**: 부팅 항목, 펌웨어 설정
- **ACPI 테이블**: 하드웨어 구성 정보
- **하드웨어 정보**: CPU, 메모리, PCI 디바이스
- **BIOS 정보**: 펌웨어 버전, 설정

### 부트로더 단계
- **GRUB 설정**: 부팅 매개변수, 메뉴 항목
- **부팅 매개변수**: 커널 명령줄 옵션
- **systemd-boot**: UEFI 부트 매니저 (해당 시)

### Xen 하이퍼바이저 단계
- **Xen 시스템 정보**: 버전, 기능, 구성
- **하이퍼바이저 로그**: xl dmesg 출력
- **도메인 목록**: 실행 중인 도메인 상태
- **vCPU/메모리 할당**: 리소스 배분 정보

### Dom0 커널 단계
- **커널 로그**: dmesg, journalctl 출력
- **커널 모듈**: 로드된 모듈 목록
- **시스템 정보**: OS 버전, 가동 시간
- **서비스 상태**: systemd 서비스 모니터링

### 게스트 도메인 단계
- **콘솔 로그**: 게스트 부팅 과정
- **성능 메트릭**: CPU, 메모리, 네트워크, 디스크
- **이벤트 로그**: 상태 변화, 충돌, 재시작
- **도메인 설정**: 구성 파일, 자동 시작

### 시스템 서비스 단계
- **서비스 상태**: 실행 중인 서비스 목록
- **Xen 서비스**: xenconsoled, xenstored 등
- **부팅 성능**: systemd-analyze 결과

## 🛠️ 상세 사용법

### xen_boot_logger.sh

메인 부팅 로그 시스템 컨트롤러:

```bash
sudo ./xen_boot_logger.sh [명령어]

명령어:
  setup          전체 로깅 시스템 설정
  collect        현재 로그 수집 실행
  analyze        로그 분석 보고서 생성
  monitor        실시간 로그 모니터링
  status         로깅 시스템 상태 확인
  install        systemd 서비스 설치
```

**주요 기능**:
- 6개 로깅 모듈 자동 설정
- HTML 분석 보고서 생성
- 실시간 로그 모니터링
- systemd 서비스 통합

### serial_console_logger.sh

직렬 콘솔 로깅 전용 도구:

```bash
sudo ./serial_console_logger.sh [명령어] [옵션]

명령어:
  setup          직렬 콘솔 로깅 설정
  test           설정 테스트 및 확인
  monitor        실시간 직렬 콘솔 모니터링
  connect        직렬 콘솔 연결
  analyze        직렬 로그 분석

옵션:
  --port PORT    직렬 포트 지정 (기본값: ttyS0)
  --speed SPEED  통신 속도 (기본값: 115200)
```

**주요 기능**:
- GRUB 직렬 콘솔 자동 설정
- systemd getty 서비스 구성
- 네트워크 직렬 콘솔 (선택사항)
- minicom 통합 연결 도구

### guest_domain_logger.sh

게스트 도메인 로깅 전용 시스템:

```bash
sudo ./guest_domain_logger.sh [명령어]

명령어:
  setup               전체 게스트 로깅 시스템 설정
  setup-domain NAME   특정 도메인 로깅 설정
  analyze             게스트 로그 분석 보고서 생성
  scan                현재 도메인 상태 스캔
  status              로깅 서비스 상태 확인
```

**주요 기능**:
- 자동 도메인 감지 및 로깅 설정
- 도메인별 콘솔/성능/이벤트 로깅
- 실시간 도메인 상태 모니터링
- HTML 분석 보고서 생성

## 📈 분석 및 모니터링

### HTML 분석 보고서

각 로깅 시스템은 포괄적인 HTML 분석 보고서를 생성합니다:

```bash
# 전체 부팅 로그 분석
sudo ./xen_boot_logger.sh analyze

# 게스트 도메인 로그 분석  
sudo ./guest_domain_logger.sh analyze

# 직렬 콘솔 로그 분석
sudo ./serial_console_logger.sh analyze
```

**보고서 내용**:
- 시스템 개요 및 구성 정보
- 부팅 단계별 상세 분석
- 오류 및 경고 메시지 요약
- 성능 메트릭 및 리소스 사용량
- 문제점 식별 및 권장사항

### 실시간 모니터링

진행 중인 로그를 실시간으로 모니터링합니다:

```bash
# 전체 부팅 로그 실시간 모니터링
sudo ./xen_boot_logger.sh monitor

# 직렬 콘솔 실시간 모니터링
sudo ./serial_console_logger.sh monitor
```

**모니터링 특징**:
- 색상 코딩 (오류: 빨강, 경고: 노랑, 정보: 초록)
- 타임스탬프 자동 추가
- 패턴 기반 필터링

## 🔧 고급 설정

### 로그 보존 정책

로그 회전은 logrotate를 통해 자동으로 관리됩니다:

- **보존 기간**: 30일
- **회전 주기**: 일일
- **압축**: 지연 압축 적용
- **위치**: `/etc/logrotate.d/xen-*-logging`

### 직렬 콘솔 네트워크 접근

원격 직렬 콘솔 접근을 설정할 수 있습니다:

```bash
# 네트워크 직렬 콘솔 활성화 (설정 시 선택)
sudo ./serial_console_logger.sh setup

# 원격 연결
telnet <server-ip> 2023
```

### 커스텀 포트 설정

기본 ttyS0 대신 다른 직렬 포트를 사용할 수 있습니다:

```bash
sudo ./serial_console_logger.sh setup --port ttyS1 --speed 38400
```

## 📁 로그 파일 구조

### 부팅 로그 (`/var/log/xen-boot-logging/`)

```
bios-uefi/
├── hardware-info-YYYYMMDD-HHMMSS.log     # 하드웨어 정보
├── uefi-variables-YYYYMMDD-HHMMSS.log     # UEFI 변수
├── uefi-boot-YYYYMMDD-HHMMSS.log          # UEFI 부팅 항목
└── acpi-tables-YYYYMMDD-HHMMSS.log        # ACPI 테이블

bootloader/
├── grub-analysis-YYYYMMDD-HHMMSS.log      # GRUB 설정 분석
└── systemd-boot-YYYYMMDD-HHMMSS.log       # systemd-boot 설정

xen-hypervisor/
├── xen-info-YYYYMMDD-HHMMSS.log           # Xen 시스템 정보
├── xen-dmesg-YYYYMMDD-HHMMSS.log          # Xen 하이퍼바이저 로그
└── xen-continuous-YYYYMMDD.log            # 지속적 모니터링

dom0-kernel/
├── kernel-log-YYYYMMDD-HHMMSS.log         # 커널 dmesg
├── kernel-modules-YYYYMMDD-HHMMSS.log     # 로드된 모듈
├── system-info-YYYYMMDD-HHMMSS.log        # 시스템 정보
└── journal-boot-YYYYMMDD.log              # journalctl 부팅 로그

system-services/
├── services-status-YYYYMMDD-HHMMSS.log    # 서비스 상태
├── xen-services-detail-YYYYMMDD-HHMMSS.log # Xen 서비스 상세
└── boot-performance-YYYYMMDD-HHMMSS.log   # 부팅 성능 분석

analysis/
└── boot-analysis-YYYYMMDD-HHMMSS.html     # HTML 분석 보고서
```

### 직렬 콘솔 로그 (`/var/log/xen-serial-console/`)

```
serial-console-YYYYMMDD.log                # 일일 직렬 콘솔 로그
analysis/
└── analysis-YYYYMMDD-HHMMSS.txt          # 텍스트 분석 보고서
```

### 게스트 도메인 로그 (`/var/log/xen-guest-logging/`)

```
domains/
└── domain-list-YYYYMMDD-HHMMSS.txt       # 도메인 목록 스냅샷

console-logs/
└── [domain-name]/
    └── console-YYYYMMDD-HHMMSS.log       # 도메인 콘솔 로그

performance/
└── [domain-name]/
    └── performance-YYYYMMDD.log          # 일일 성능 데이터

events/
└── [domain-name]/
    └── events-YYYYMMDD.log               # 도메인 이벤트 로그

analysis/
└── guest-analysis-YYYYMMDD-HHMMSS.html  # HTML 분석 보고서
```

## ⚙️ systemd 서비스

설치된 systemd 서비스들:

### 메인 서비스
- `xen-boot-logging.service` - 메인 부팅 로그 수집
- `serial-console-logger.service` - 직렬 콘솔 로그 캡처
- `xen-domain-watcher.service` - 게스트 도메인 자동 감지

### 게스트별 서비스 (자동 생성)
- `xen-guest-console-[domain].service` - 도메인 콘솔 로깅
- `xen-guest-performance-[domain].service` - 도메인 성능 모니터링  
- `xen-guest-events-[domain].service` - 도메인 이벤트 로깅

### 서비스 관리

```bash
# 서비스 상태 확인
systemctl status xen-boot-logging.service
systemctl status xen-domain-watcher.service

# 서비스 재시작
sudo systemctl restart xen-boot-logging.service

# 로그 확인
journalctl -u xen-boot-logging.service
```

## 🔍 문제 해결

### 일반적인 문제

**Q: 직렬 콘솔에 출력이 없습니다**
A: 다음을 확인하세요:
```bash
# 직렬 포트 존재 확인
ls -la /dev/ttyS*

# GRUB 설정 확인
grep console /etc/default/grub

# 서비스 상태 확인
systemctl status serial-console-logger.service
```

**Q: 게스트 도메인이 자동으로 감지되지 않습니다**
A: 도메인 감시 서비스를 확인하세요:
```bash
systemctl status xen-domain-watcher.service
journalctl -u xen-domain-watcher.service
```

**Q: HTML 보고서가 생성되지 않습니다**
A: 분석 스크립트를 수동으로 실행해보세요:
```bash
sudo /var/log/xen-boot-logging/analyze_boot_logs.sh
```

### 로그 파일 위치

문제 해결을 위한 주요 로그 위치:

- 시스템 로그: `journalctl -u xen-*`
- 부팅 로그: `/var/log/xen-boot-logging/`
- 직렬 콘솔: `/var/log/xen-serial-console/`
- 게스트 로그: `/var/log/xen-guest-logging/`

### 설정 파일 백업

설정 변경 전 자동으로 백업이 생성됩니다:

- GRUB: `/var/backups/xen-serial-console/grub.backup.*`
- Xen: `/var/backups/xen-serial-console/xl.conf.backup.*`

## 📞 지원 및 기여

### 진단 정보 수집

문제 보고 시 다음 정보를 포함해주세요:

```bash
# 시스템 정보
uname -a
lsb_release -a

# Xen 상태
xl info
xl list

# 서비스 상태  
systemctl status xen-*

# 로그 분석
sudo ./xen_boot_logger.sh analyze
```

### 제한사항

- **하드웨어 직렬 포트**: 물리적 직렬 포트가 없는 시스템에서는 가상 로깅만 가능
- **UEFI Secure Boot**: 활성화된 경우 일부 로깅 기능이 제한될 수 있음
- **중첩 가상화**: 가상머신 내에서 실행 시 하드웨어 정보 수집이 제한됨

### 성능 고려사항

- **디스크 사용량**: 로그 파일이 빠르게 증가할 수 있으므로 정기적인 정리 필요
- **CPU 오버헤드**: 실시간 모니터링 시 약간의 CPU 사용량 증가
- **네트워크 대역폭**: 원격 직렬 콘솔 사용 시 네트워크 대역폭 소모

## 📝 라이선스

이 프로젝트는 교육 및 연구 목적으로 제공됩니다. 상용 환경에서 사용 시 충분한 테스트를 거친 후 사용하시기 바랍니다.

---

**⚠️ 중요**: 이 로깅 시스템은 상당한 양의 로그 데이터를 생성합니다. 디스크 공간을 모니터링하고 필요에 따라 로그 보존 정책을 조정하시기 바랍니다.