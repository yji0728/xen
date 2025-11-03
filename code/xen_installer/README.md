# Xen 신뢰성 높은 설치 시스템 v1.0

Ubuntu 22.04/24.04 LTS에서 Xen 하이퍼바이저를 안정적으로 설치하고 운영하기 위한 통합 시스템입니다.

## 🎯 주요 특징

- **자동 환경 진단**: 설치 전 호환성 문제 사전 감지
- **지능형 의존성 해결**: Ubuntu 버전별 최적화된 패키지 관리
- **드라이버 호환성 자동 처리**: 알려진 호환성 문제 자동 해결
- **단계별 검증**: 설치 과정 실시간 모니터링
- **자동 롤백**: 오류 시 시스템 상태 자동 복구
- **포괄적 로깅**: 부팅 과정 전체 로그 기록
- **설치 후 검증**: 완전한 기능 테스트

## 📁 프로젝트 구조

```
xen_installer/
├── xen_reliable_installer.sh          # 메인 설치 스크립트
├── system_diagnostic.sh               # 설치 전 시스템 진단
├── post_installation_verification.sh  # 설치 후 검증
├── README.md                          # 이 파일
├── config/
│   ├── xen_templates/                 # Xen 설정 템플릿
│   └── grub_configs/                  # GRUB 설정 템플릿
└── utils/
    ├── emergency_recovery.sh          # 긴급 복구 도구
    └── troubleshooting_guide.md       # 문제 해결 가이드
```

## 🚀 빠른 시작

### 1단계: 시스템 진단

설치 전 시스템 호환성을 확인합니다:

```bash
chmod +x system_diagnostic.sh
sudo ./system_diagnostic.sh
```

### 2단계: Xen 설치

진단 결과가 양호한 경우 설치를 진행합니다:

```bash
chmod +x xen_reliable_installer.sh
sudo ./xen_reliable_installer.sh
```

### 3단계: 시스템 재부팅

설치 완료 후 시스템을 재부팅합니다:

```bash
sudo reboot
```

**중요**: GRUB 메뉴에서 Xen 항목을 선택하여 부팅하세요.

### 4단계: 설치 검증

재부팅 후 설치 상태를 검증합니다:

```bash
chmod +x post_installation_verification.sh
sudo ./post_installation_verification.sh
```

## 📋 시스템 요구사항

### 지원 운영체제
- Ubuntu 22.04 LTS (Jammy Jellyfish)
- Ubuntu 24.04 LTS (Noble Numbat)

### 하드웨어 요구사항
- **CPU**: Intel VT-x 또는 AMD-V 지원 (필수)
- **메모리**: 최소 4GB (권장: 8GB 이상)
- **디스크**: 최소 10GB 여유공간 (권장: 50GB 이상)
- **아키텍처**: x86_64

### 추가 기능 요구사항
- **IOMMU**: PCI 패스스루 사용 시 필요
- **EPT/NPT**: 성능 최적화를 위해 권장
- **직렬 포트**: 원격 로깅 사용 시 필요

## 🛠️ 스크립트 상세 설명

### xen_reliable_installer.sh

메인 설치 스크립트로 다음 기능을 제공합니다:

- **환경 검사**: Ubuntu 버전, 하드웨어 가상화, 리소스 확인
- **의존성 해결**: 자동 패키지 설치 및 충돌 해결
- **드라이버 호환성**: 알려진 문제 자동 해결
- **Xen 설치**: 버전별 최적화된 Xen 설치
- **GRUB 설정**: 부팅 옵션 자동 구성
- **기본 로깅**: 부팅 로그 시스템 기본 설정

**사용법**:
```bash
sudo ./xen_reliable_installer.sh [옵션]

옵션:
  -h, --help     도움말 출력
  -v, --verbose  상세한 로그 출력
  -q, --quiet    오류만 출력
  --dry-run      설치하지 않고 검사만 수행
```

### system_diagnostic.sh

설치 전 시스템 호환성을 종합적으로 진단합니다:

- **OS 호환성**: Ubuntu 버전 및 커널 호환성
- **하드웨어 가상화**: Intel VT-x/AMD-V, IOMMU 지원
- **리소스 확인**: 메모리, 디스크 용량
- **네트워크 구성**: 인터페이스 및 브릿지 설정
- **충돌 소프트웨어**: KVM, VirtualBox 등 감지
- **드라이버 호환성**: 알려진 문제 사전 감지
- **BIOS/UEFI 설정**: Secure Boot 등 확인

### post_installation_verification.sh

설치 후 Xen 시스템의 정상 작동을 검증합니다:

- **패키지 설치**: 필수 Xen 패키지 확인
- **하이퍼바이저 상태**: Xen 부팅 및 작동 상태
- **GRUB 구성**: 부팅 옵션 및 설정
- **Xen 도구**: xl, xenstore 등 도구 기능
- **Dom0 상태**: 도메인 0 리소스 및 상태
- **가상화 기능**: HVM, HAP, IOMMU 등
- **네트워킹**: 브릿지 설정 및 연결
- **로깅 시스템**: 로그 수집 기능
- **성능**: 기본 성능 확인

## 🔧 고급 사용법

### 상세 로깅 활성화

설치 과정을 상세히 모니터링하려면:

```bash
sudo ./xen_reliable_installer.sh --verbose
```

### 설치 가능성만 확인

실제 설치하지 않고 호환성만 확인하려면:

```bash
sudo ./xen_reliable_installer.sh --dry-run
```

### 로그 수집

설치 후 시스템 로그를 수집하려면:

```bash
sudo /usr/local/bin/collect-xen-logs.sh
```

## 🌟 해결된 호환성 문제

### Ubuntu 22.04 LTS
- ✅ zstd 커널 압축 호환성 (Xen 4.16+ 자동 설치)
- ✅ libzstd-dev 의존성 자동 해결
- ✅ HWE 스택 호환성 최적화

### Ubuntu 24.04 LTS
- ✅ MegaRAID SAS 드라이버 문제 (IOMMU 설정 자동 적용)
- ✅ AMD 그래픽 드라이버 충돌 (nomodeset 자동 적용)
- ✅ 네트워크 브릿지 설정 회귀 (설정 자동 최적화)
- ✅ Python 호환성 (python-is-python3 자동 설치)

### 공통 문제
- ✅ Secure Boot 충돌 감지 및 안내
- ✅ KVM/VirtualBox 충돌 감지
- ✅ NetworkManager 브릿지 호환성 자동 설정
- ✅ GRUB 설정 최적화

## 📊 지원 환경

| 환경 | Ubuntu 22.04 | Ubuntu 24.04 | 자동 대응 |
|------|-------------|-------------|----------|
| BIOS Legacy | ✅ | ✅ | ✅ |
| UEFI | ✅ | ✅ | ✅ |
| Secure Boot | ⚠️ | ⚠️ | 감지/안내 |
| Intel VT-x | ✅ | ✅ | ✅ |
| AMD-V | ✅ | ✅ | ✅ |
| IOMMU/VT-d | ✅ | ✅ | ✅ |
| MegaRAID | ✅ | ⚠️ | ✅ |
| AMD Graphics | ✅ | ⚠️ | ✅ |
| 네트워크 브릿지 | ✅ | ⚠️ | ✅ |

범례: ✅ 완전 지원, ⚠️ 알려진 문제/자동 대응

## 🔍 로그 및 문제 해결

### 로그 위치
- **설치 로그**: `/var/log/xen-installer/`
- **Xen 로그**: `/var/log/xen/`
- **백업 파일**: `/var/backups/xen-installer/`

### 주요 로그 파일
- `xen-install-YYYYMMDD-HHMMSS.log`: 설치 과정 상세 로그
- `xen-dmesg-YYYYMMDD-HHMMSS.log`: Xen 하이퍼바이저 로그
- `system-dmesg-YYYYMMDD-HHMMSS.log`: 시스템 부팅 로그

### 문제 해결

#### 설치 실패 시
1. 로그 파일 확인: `/var/log/xen-installer/`
2. 진단 도구 재실행: `sudo ./system_diagnostic.sh`
3. 실패 원인 해결 후 재시도

#### 부팅 실패 시
1. GRUB에서 이전 커널로 부팅
2. 백업에서 GRUB 설정 복원:
   ```bash
   sudo cp /var/backups/xen-installer/grub.backup.* /etc/default/grub
   sudo update-grub
   ```

#### Dom0 문제 시
1. Xen 로그 확인: `sudo xl dmesg`
2. Dom0 메모리 설정 확인: `sudo xl list`
3. 시스템 리소스 확인: `sudo xl info`

## 📞 지원 및 문의

### 진단 정보 수집
문제 발생 시 다음 정보를 수집해주세요:

```bash
# 시스템 정보
sudo ./system_diagnostic.sh > diagnostic_report.txt

# 검증 결과
sudo ./post_installation_verification.sh > verification_report.txt

# Xen 로그 수집
sudo /usr/local/bin/collect-xen-logs.sh
```

### 알려진 제한사항
- **AMD CPU**: Drakvuf 등 일부 VMI 도구는 Intel VT-x + EPT 필수
- **Secure Boot**: 활성화 시 추가 설정 필요
- **중첩 가상화**: 가상머신 내에서의 설치는 제한적 지원

### 추가 리소스
- [Xen Project 공식 문서](https://xen-project.org/documentation/)
- [Ubuntu Xen 패키지 정보](https://packages.ubuntu.com/search?keywords=xen)
- [Drakvuf 공식 문서](https://drakvuf.com/)

## 📝 라이선스

이 프로젝트는 교육 및 연구 목적으로 제공됩니다. 상용 환경에서 사용 시 충분한 테스트를 거친 후 사용하시기 바랍니다.

## 🔄 업데이트 이력

### v1.0 (2024년 10월)
- 초기 릴리스
- Ubuntu 22.04/24.04 LTS 지원
- 자동 진단 및 설치 시스템
- 드라이버 호환성 자동 해결
- 포괄적 설치 후 검증

---

**⚠️ 중요**: 이 도구는 시스템의 부팅 설정과 커널 구성을 변경합니다. 중요한 시스템에서 사용하기 전에 전체 시스템 백업을 생성하시기 바랍니다.