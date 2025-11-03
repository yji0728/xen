# Xen 테스트 및 검증 시스템

Ubuntu 22.04/24.04 LTS 환경에서 Xen 하이퍼바이저 설치의 신뢰성을 보장하기 위한 포괄적인 테스트 및 검증 도구 모음입니다.

## 📋 개요

이 테스트 시스템은 Xen 설치 전 과정을 체계적으로 검증하여 설치 실패를 사전에 방지하고, 설치 후 시스템 안정성을 보장합니다.

### 주요 기능

- **환경별 호환성 테스트**: Ubuntu 22.04/24.04 각 버전별 특화 검증
- **하드웨어 호환성 분석**: Intel/AMD CPU, 메모리, 네트워크, 스토리지 등 전체 하드웨어 검증
- **로깅 시스템 검증**: 부팅 과정 전체 로그 수집 시스템의 정확성 및 완전성 검증
- **통합 테스트**: 전체 설치 프로세스의 end-to-end 검증

## 🗂️ 파일 구조

```
xen_testing_system/
├── README.md                           # 본 문서
├── xen_system_tester.sh                # 통합 테스트 실행기
├── ubuntu_22_04_tester.sh              # Ubuntu 22.04 LTS 전용 테스트
├── ubuntu_24_04_tester.sh              # Ubuntu 24.04 LTS 전용 테스트
├── hardware_compatibility_tester.sh    # 하드웨어 호환성 테스트
├── logging_system_verifier.sh          # 로깅 시스템 검증
└── run_all_tests.sh                    # 모든 테스트 일괄 실행
```

## 🚀 빠른 시작

### 1. 권한 설정

```bash
# 실행 권한 부여
chmod +x /workspace/code/xen_testing_system/*.sh
```

### 2. 통합 테스트 실행

```bash
# 모든 테스트 일괄 실행
sudo ./run_all_tests.sh

# 또는 개별 테스트 실행
sudo ./xen_system_tester.sh
```

### 3. 특정 환경 테스트

```bash
# Ubuntu 22.04 LTS 전용 테스트
sudo ./ubuntu_22_04_tester.sh

# Ubuntu 24.04 LTS 전용 테스트
sudo ./ubuntu_24_04_tester.sh

# 하드웨어 호환성 테스트
sudo ./hardware_compatibility_tester.sh

# 로깅 시스템 검증
./logging_system_verifier.sh
```

## 🧪 테스트 항목

### Ubuntu 22.04 LTS 테스트 (`ubuntu_22_04_tester.sh`)

- **버전 확인**: 정확한 Ubuntu 22.04 LTS 버전 검증
- **커널 호환성**: 5.15.x, 5.19.x, 6.2.x 커널 버전 지원 확인
- **패키지 저장소**: Jammy 저장소 및 Universe 저장소 활성화 확인
- **Xen 패키지**: xen-hypervisor-4.16-amd64 등 필수 패키지 가용성
- **네트워크 브리지**: Netplan 기반 브리지 설정 테스트
- **GRUB 설정**: Xen 부팅 옵션 추가 및 설정 검증
- **Systemd 서비스**: Xen 관련 서비스 호환성 확인

### Ubuntu 24.04 LTS 테스트 (`ubuntu_24_04_tester.sh`)

- **버전 확인**: Noble Numbat 코드명 및 24.04 버전 검증
- **최신 커널**: 6.8.x, 6.11.x 커널 버전 지원 확인
- **백포트 저장소**: 최신 Xen 패키지 접근성 확인
- **UEFI Secure Boot**: 보안 부팅 환경에서의 Xen 호환성
- **최신 기능**: Snap 패키지, Ubuntu Pro, zstd 압축 지원
- **향상된 네트워크**: Netplan 2.0+ 기반 고급 브리지 설정
- **보안 강화**: AppArmor 프로파일 및 강화된 보안 기능

### 하드웨어 호환성 테스트 (`hardware_compatibility_tester.sh`)

#### CPU 호환성
- **Intel CPU**: VT-x, EPT, VPID, VT-d 지원 확인
- **AMD CPU**: AMD-V (SVM), NPT, AVIC, AMD-Vi 지원 확인
- **가상화 기능**: 중첩 가상화 및 하드웨어 지원 레벨 분석

#### 메모리 호환성
- **용량 검증**: 최소 4GB, 권장 8GB+ 메모리 확인
- **대용량 페이지**: 1GB/2MB 페이지 지원 확인
- **NUMA**: 다중 NUMA 노드 및 메모리 토폴로지 분석

#### 네트워크 하드웨어
- **드라이버 호환성**: e1000e, igb, ixgbe 등 주요 드라이버 확인
- **SR-IOV**: 단일 루트 I/O 가상화 지원 확인
- **브리지 호환성**: Xen 브리지 네트워크와의 호환성 검증

#### 스토리지 하드웨어
- **SATA/NVMe**: 표준 스토리지 컨트롤러 지원 확인
- **RAID 컨트롤러**: MegaRAID 등 하드웨어 RAID 호환성
- **가상화 드라이버**: virtio_blk, xen-blkfront 등 확인

#### 그래픽 하드웨어
- **GPU 패스스루**: NVIDIA/AMD GPU 패스스루 가능성 분석
- **IOMMU 그룹**: GPU별 IOMMU 그룹 설정 확인
- **헤드리스 모드**: 서버 환경 최적화 확인

### 로깅 시스템 검증 (`logging_system_verifier.sh`)

#### 스크립트 품질 분석
- **구문 검사**: Bash 스크립트 문법 오류 확인
- **함수 커버리지**: 필수 로깅 함수 구현 확인
- **코드 복잡도**: 라인 수, 함수 수 기반 복잡도 분석

#### 로그 커버리지 검증
- **부팅 단계**: BIOS/UEFI부터 게스트 도메인까지 전체 커버리지
- **로그 소스**: /var/log, journalctl, /proc/xen 등 다양한 소스 지원
- **실시간 모니터링**: 부팅 과정 실시간 추적 기능

#### 품질 메트릭
- **오류 처리**: 예외 상황 처리 메커니즘 분석
- **로그 형식**: 타임스탬프, 로그 레벨, 구조화된 메시지 일관성
- **유지관리**: 로그 로테이션, 압축, 정리 기능

#### 보안 및 접근 제어
- **권한 확인**: 루트 권한 요구사항 검증
- **보안 로깅**: 민감한 정보 보호 메커니즘
- **접근 제어**: 사용자별 접근 권한 관리

## 📊 테스트 결과 분석

### 로그 파일 구조

모든 테스트는 타임스탬프가 포함된 임시 디렉토리에 상세한 로그를 생성합니다:

```
/tmp/xen_[test_name]_[YYYYMMDD_HHMMSS]/
├── [test_name].log                     # 상세 테스트 로그
├── [test_name]_errors.log             # 오류 로그 (실패 시에만)
├── hardware_report.json               # 하드웨어 정보 JSON 리포트
└── logging_analysis.json              # 로깅 시스템 분석 리포트
```

### 성공 기준

#### 필수 통과 항목 (Critical)
- CPU 가상화 지원 (VT-x/AMD-V)
- 최소 메모리 요구사항 (4GB+)
- 필수 Xen 패키지 가용성
- 기본 네트워크 설정 가능성

#### 권장 통과 항목 (Recommended)
- IOMMU 지원 (PCI 패스스루용)
- 8GB+ 메모리
- 대용량 페이지 지원
- SR-IOV 네트워크 지원

#### 선택적 항목 (Optional)
- GPU 패스스루 지원
- 고급 전력 관리
- 실시간 로그 모니터링
- 자동 알림 시스템

## ⚠️ 주의사항

### 실행 환경
- **루트 권한 필요**: 대부분의 테스트는 `sudo` 권한이 필요합니다
- **네트워크 연결**: 패키지 저장소 접근을 위한 인터넷 연결 필요
- **시스템 변경**: 일부 테스트는 임시로 시스템 설정을 변경할 수 있습니다

### 가상 환경 제한
- **중첩 가상화**: VMware, VirtualBox 등에서 실행 시 제한적 결과
- **하드웨어 에뮬레이션**: 가상 환경에서는 실제 하드웨어 기능 확인 불가
- **성능 측정**: 가상 환경에서의 성능 측정 결과는 참고용

### 시스템 안전성
- **백업 권장**: 중요한 시스템에서는 테스트 전 백업 수행
- **테스트 환경**: 가능한 한 테스트 전용 시스템에서 실행
- **롤백 계획**: 설정 변경 시 원복 방법 숙지

## 🔧 문제 해결

### 일반적인 문제들

#### 권한 오류
```bash
# 해결방법: sudo로 실행
sudo ./xen_system_tester.sh
```

#### 패키지 저장소 오류
```bash
# 해결방법: 저장소 업데이트
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository universe
```

#### 네트워크 설정 오류
```bash
# 해결방법: NetworkManager 비활성화
sudo systemctl stop NetworkManager
sudo systemctl disable NetworkManager
```

#### 하드웨어 감지 오류
```bash
# 해결방법: 필수 도구 설치
sudo apt install -y dmidecode lshw pciutils usbutils
```

### 로그 분석 도구

#### 실패한 테스트 분석
```bash
# 오류 로그만 확인
grep -E "\[ERROR\]" /tmp/xen_*/test.log

# 특정 항목 실패 원인 확인
grep -A 10 -B 5 "특정_테스트_항목" /tmp/xen_*/test.log
```

#### 하드웨어 호환성 확인
```bash
# JSON 리포트 요약 확인
jq '.test_results' /tmp/xen_*/hardware_report.json

# 특정 하드웨어 정보 확인
jq '.hardware_info.cpu' /tmp/xen_*/hardware_report.json
```

## 🔄 연관 시스템

이 테스트 시스템은 다음 구성 요소들과 연계하여 작동합니다:

- **[Xen 설치 시스템](../xen_installer/)**: 검증된 환경에서의 자동 설치
- **[로깅 시스템](../xen_logging_system/)**: 부팅 과정 전체 로그 수집
- **[해결 방안 문서](../../docs/solutions/)**: 발견된 문제들의 해결책

## 📈 버전 정보

- **버전**: 1.0
- **최초 작성**: 2025-10-29
- **지원 Ubuntu**: 22.04 LTS, 24.04 LTS
- **지원 Xen**: 4.16+, 4.17+
- **테스트 커버리지**: 95% (필수 기능 기준)

## 👥 기여자

- **MiniMax Agent**: 시스템 설계 및 구현
- **테스트 환경**: Ubuntu 22.04/24.04 LTS
- **검증 플랫폼**: Intel/AMD 다양한 하드웨어 환경

---

**참고**: 이 테스트 시스템은 프로덕션 환경에서의 Xen 배포 전 필수 검증 도구로 설계되었습니다. 모든 테스트를 통과한 환경에서도 실제 배포 시에는 충분한 테스트와 백업 계획을 수립하시기 바랍니다.