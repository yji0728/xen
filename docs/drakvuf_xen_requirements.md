# Drakvuf-Xen 호환성 및 요구사항 연구 보고서

## 요약 (Executive Summary)

본 연구는 Drakvuf 가상화 기반 바이너리 분석 시스템이 Xen 하이퍼바이저와 함께 정상적으로 작동하기 위한 기술적 요구사항과 호환성 문제를 종합 분석했습니다. 주요 발견사항으로는 Xen 4.17 이상 버전이 필요하며, altp2m=1을 포함한 특정 부팅 옵션이 필수적이고, Intel VT-x + EPT 하드웨어 지원이 요구된다는 점입니다. 또한 OVMF 빌드 버그, altp2m+PML 충돌 등 여러 호환성 이슈와 해결방안을 확인했습니다.

## 1. 서론

Drakvuf는 가상화 기반의 에이전트 없는 블랙박스 바이너리 분석 시스템으로, Xen 하이퍼바이저의 VMI(Virtual Machine Introspection) 기능을 활용하여 게스트 시스템을 스텔스 모니터링합니다. 본 연구는 Drakvuf와 Xen 간의 성공적인 통합을 위한 기술적 요구사항을 명확히 하고, 실무자들이 직면할 수 있는 호환성 문제와 해결방안을 제시하는 것을 목표로 합니다.

## 2. Drakvuf의 Xen 버전 요구사항

### 2.1 지원 버전 매트릭스

**최소 요구사항:**
- Xen 4.17 이상 (절대 필수)
- 테스트된 안정 버전: Xen 4.17.2-5 (Qubes OS 환경)

**권장 버전:**
- Xen 4.19.x (소스 빌드에서 검증됨)
- Xen 4.20.1 (최신 안정 버전)

**버전별 특징:**
- Xen 4.17: Drakvuf의 기본 VMI 기능 지원, altp2m 안정화
- Xen 4.19: 성능 개선 및 버그 수정, OVMF 통합 이슈 존재
- Xen 4.20: 최신 보안 패치 및 성능 최적화

### 2.2 하드웨어 요구사항

**필수 하드웨어 지원:**
- Intel CPU (VT-x 기술 지원)
- EPT (Extended Page Tables) 지원
- SLAT (Second Level Address Translation) 기능

**지원되지 않는 하드웨어:**
- AMD CPU: Drakvuf는 현재 AMD의 SVM 기술을 지원하지 않음
- VT-x 미지원 Intel CPU: 구형 프로세서에서는 작동 불가

## 3. Xen 설정에서 Drakvuf 동작을 위한 필수 옵션들

### 3.1 GRUB 부팅 옵션 설정

Drakvuf가 정상 작동하려면 `/etc/default/grub.d/xen.cfg` 파일에 다음 옵션들을 설정해야 합니다:

```bash
GRUB_CMDLINE_XEN_DEFAULT="dom0_mem=4096M,max:4096M dom0_max_vcpus=4 dom0_vcpus_pin=1 force-ept=1 ept=ad=0 hap_1gb=0 hap_2mb=0 altp2m=1 hpet=legacy-replacement smt=0"
```

### 3.2 핵심 옵션 설명

**메모리 관리 옵션:**
- `dom0_mem=4096M,max:4096M`: Dom0에 4GB 메모리 할당 및 최대치 제한
- `dom0_max_vcpus=4`: Dom0의 최대 vCPU 수 제한
- `dom0_vcpus_pin=1`: vCPU 핀닝 활성화로 성능 안정성 확보

**페이징 및 메모리 보호 옵션:**
- `force-ept=1`: EPT(Extended Page Tables) 강제 활성화 (필수)
- `ept=ad=0`: EPT Access/Dirty 플래그 비활성화 (altp2m 충돌 방지)
- `hap_1gb=0`: 1GB 대형 페이지 비활성화
- `hap_2mb=0`: 2MB 대형 페이지 비활성화

**VMI 핵심 옵션:**
- `altp2m=1`: Alternate p2m 활성화 (Drakvuf의 핵심 기능, 절대 필수)

**시스템 안정성 옵션:**
- `hpet=legacy-replacement`: HPET 타이머 호환성 보장
- `smt=0`: 하이퍼스레딩 비활성화 (보안 및 성능 고려)

### 3.3 DomU 메모리 설정

게스트 도메인의 메모리 설정도 중요합니다:

```json
{
    "memory": 3072,
    "maxmem": 3072
}
```

메모리 할당량은 시스템 리소스와 분석 대상에 따라 조정 가능하지만, Dom0와 DomU의 총합이 물리 메모리를 초과하지 않도록 주의해야 합니다.

## 4. Drakvuf과 Xen 간의 호환성 이슈들

### 4.1 OVMF 빌드 오류 (2025년 4월 발견)

**문제점:**
Xen 4.19.2 버전에서 오래된 Tianocore OVMF 버전을 참조하여 서브모듈 URL이 깨지는 문제가 발생합니다.

**증상:**
```
fatal: repository 'https://xenbits.xen.org/git-http/ovmf.git/' not found
```

**해결방안:**
`tools/firmware/ovmf-dir-remote/Config.mk` 파일을 다음과 같이 패치:

```diff
- OVMF_UPSTREAM_URL ?= https://xenbits.xen.org/git-http/ovmf.git
- OVMF_UPSTREAM_REVISION ?= ba91d0292e593df8528b66f99c1b0b14fadc8e16
+ OVMF_UPSTREAM_URL ?= https://github.com/tianocore/edk2.git
+ OVMF_UPSTREAM_REVISION ?= 4dfdca63a93497203f197ec98ba20e2327e4afe4
```

### 4.2 altp2m + PML 충돌 문제

**문제점:**
EPT의 Access/Dirty 플래그와 PML(Page Modification Logging) 기능이 altp2m과 함께 사용될 때 시스템 충돌이 발생합니다.

**증상:**
- Xen 하이퍼바이저 크래시
- "Xen BUG" 메시지와 함께 시스템 재부팅

**해결방안:**
부팅 옵션에 `ept=ad=0`를 추가하여 Access/Dirty 플래그와 PML을 비활성화합니다.

### 4.3 Nested HVM 보안 취약점

**문제점:**
Nested HVM 기능이 altp2m과 함께 사용될 때 보안 취약점이 발생할 수 있습니다.

**해결방안:**
Drakvuf 사용 시에는 Nested HVM을 비활성화하거나, 보안이 중요한 환경에서는 사용을 피해야 합니다.

### 4.4 Qubes OS 통합 문제

**문제점:**
Qubes OS의 libvirt는 altp2m 옵션을 직접 지원하지 않아 도메인 생성 시 문제가 발생합니다.

**해결방안:**
`libxl_create.c` 파일을 패치하여 altp2m 지원을 추가하거나, 수동으로 도메인을 생성해야 합니다.

### 4.5 일반적인 설치 문제들

**메모리 할당 오류:**
```
ERROR: can't allocate low memory for domain
```
- **해결책**: `dom0_mem` 값을 증가시키거나 DomU 메모리를 감소

**빌드 의존성 문제:**
- Ubuntu 22.04에서 수동 빌드 시 다양한 패키지 의존성 오류
- **권장사항**: 배포판의 기본 Xen 패키지 사용 (`apt-get install xen`)

## 5. 보안 및 권한 설정 요구사항

### 5.1 시스템 권한 요구사항

**Dom0 관리자 권한:**
Drakvuf는 Dom0에서 root 권한으로 실행되어야 하며, 다음과 같은 시스템 리소스에 접근합니다:
- `/dev/xen/evtchn`: 이벤트 채널 액세스
- `/dev/xen/privcmd`: 하이퍼바이저 명령 인터페이스
- `/proc/xen/`: Xen 시스템 정보

**LibVMI 권한:**
VMI 라이브러리가 게스트 메모리에 접근하기 위해 특별한 권한이 필요합니다.

### 5.2 XSM/Flask 보안 정책

**지원 현황:**
Drakvuf는 XSM(Xen Security Modules)과 Flask 보안 정책을 부분적으로 지원합니다.

**제한사항:**
- 일부 VMI 기능이 엄격한 보안 정책과 충돌할 수 있음
- 정책 조정 없이는 정상 작동이 어려울 수 있음

**권장사항:**
고보안 환경에서는 사용자 정의 Flask 정책을 작성하여 Drakvuf의 필요 권한만 허용하도록 설정

### 5.3 보안 고려사항

**도메인 격리 약화:**
VMI 기술의 특성상 하이퍼바이저 레벨에서 게스트를 모니터링하므로, 전통적인 가상화 격리가 약화될 수 있습니다.

**데이터 유출 위험:**
- 파일 추출 기능으로 인한 민감 데이터 노출 위험
- 메모리 덤프에서 개인정보 및 기밀정보 추출 가능성

**완화 방안:**
- 분석 대상을 격리된 네트워크 환경에서 실행
- 추출된 데이터의 안전한 저장 및 관리 정책 수립
- 정기적인 보안 감사 및 모니터링

## 6. 실행 가능한 권장사항

### 6.1 설치 및 구성 단계별 가이드

**1단계: 하드웨어 호환성 확인**
```bash
# Intel VT-x 지원 확인
grep -E "(vmx|svm)" /proc/cpuinfo

# EPT 지원 확인 (Intel CPU에서)
cat /proc/cpuinfo | grep ept
```

**2단계: Xen 설치**
```bash
# 배포판 패키지 사용 (권장)
sudo apt-get install xen-hypervisor-4.17-amd64 xen-utils-4.17

# 또는 최신 버전 수동 빌드 (고급 사용자)
git clone https://xenbits.xen.org/git-http/xen.git
cd xen && git checkout RELEASE-4.19.2
```

**3단계: GRUB 설정**
```bash
# Xen 부팅 옵션 설정
sudo echo 'GRUB_CMDLINE_XEN_DEFAULT="dom0_mem=4096M,max:4096M dom0_max_vcpus=4 dom0_vcpus_pin=1 force-ept=1 ept=ad=0 hap_1gb=0 hap_2mb=0 altp2m=1 hpet=legacy-replacement smt=0"' > /etc/default/grub.d/xen.cfg

# GRUB 업데이트
sudo update-grub
```

**4단계: 재부팅 및 검증**
```bash
# 시스템 재부팅
sudo reboot

# Xen 로드 확인
xl info

# altp2m 기능 확인
xl dmesg | grep altp2m
```

### 6.2 문제 해결 체크리스트

**부팅 문제:**
- [ ] GRUB에서 Xen 항목 선택됨
- [ ] Xen 부팅 옵션이 올바르게 설정됨
- [ ] Dom0 메모리 할당이 적절함

**VMI 기능 문제:**
- [ ] altp2m=1 옵션 활성화됨
- [ ] EPT 기능이 활성화됨
- [ ] Intel VT-x 지원 확인됨

**성능 문제:**
- [ ] CPU 핀닝 설정됨
- [ ] 대형 페이지 비활성화됨
- [ ] 불필요한 Xen 기능 비활성화됨

### 6.3 모니터링 및 유지보수

**시스템 상태 모니터링:**
```bash
# Xen 하이퍼바이저 상태
xl info

# 도메인 상태 확인
xl list

# 메모리 사용량 모니터링
xl info | grep -E "(total_memory|free_memory)"
```

**로그 분석:**
```bash
# Xen 하이퍼바이저 로그
xl dmesg

# Dom0 커널 로그
dmesg | grep xen

# Drakvuf 실행 로그
journalctl -u drakrun
```

## 7. 결론

Drakvuf와 Xen의 성공적인 통합을 위해서는 정확한 버전 선택, 올바른 부팅 옵션 설정, 그리고 알려진 호환성 문제에 대한 이해가 필수적입니다. 특히 altp2m 기능의 활성화와 EPT 관련 설정이 가장 중요한 요소이며, 하드웨어 수준에서 Intel VT-x + EPT 지원이 반드시 필요합니다.

보안 관점에서는 VMI 기술의 특성상 도메인 격리가 약화될 수 있으므로, 적절한 보안 정책과 모니터링 체계를 구축해야 합니다. 또한 지속적인 업데이트와 패치 적용을 통해 새롭게 발견되는 호환성 문제들을 해결해 나가야 합니다.

본 연구에서 제시한 구성 가이드와 문제 해결 방안을 따르면, 안정적이고 효율적인 Drakvuf-Xen 환경을 구축할 수 있을 것입니다.

## 8. 참고 문헌 및 소스

[1] [Drakvuf Sandbox Release v0.16.1](https://github.com/CERT-Polska/drakvuf-sandbox/releases/tag/v0.16.1) - High Reliability - 공식 릴리스 문서
[2] [Drakvuf Official Documentation](https://drakvuf.com/) - High Reliability - 공식 프로젝트 사이트
[3] [Drakvuf Release v0.19.0](https://github.com/tklengyel/drakvuf/releases/tag/v0.19.0) - High Reliability - 공식 GitHub 릴리스
[4] [Qubes Drakvuf Integration](https://github.com/QubesOS/qubes-vmm-xen-stubdom-linux/tree/main/drakvuf) - High Reliability - Qubes OS 통합 문서
[5] [Xen Performance Tuning Guide](https://wiki.xen.org/wiki/Xen_Hypervisor_Performance_Tuning) - High Reliability - 공식 Xen 위키
[6] [Drakvuf Main Repository](https://github.com/tklengyel/drakvuf) - High Reliability - 공식 GitHub 저장소
[7] [VMI Stealthiness Blog](https://volatility-labs.blogspot.com/2016/04/anti-hypervisor-malware-and-xen.html) - Medium Reliability - 기술 블로그
[8] [Xen Common Problems Documentation](https://xen-project.org/help/faq/) - High Reliability - 공식 FAQ
[9] [GitHub Discussion #1678](https://github.com/tklengyel/drakvuf/discussions/1678) - Medium Reliability - 커뮤니티 토론
[10] [Drakvuf Troubleshooting Guide](https://drakvuf.readthedocs.io/en/latest/troubleshooting.html) - High Reliability - 공식 문제 해결 가이드

---

*작성자: MiniMax Agent*  
*작성일: 2025-10-29*  
*문서 버전: 1.0*