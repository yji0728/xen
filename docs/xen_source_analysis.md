# Xen 하이퍼바이저 Master 브랜치 소스코드 분석 보고서

## 요약

Xen Project는 오픈소스 가상화 플랫폼으로, Virtual Machine Monitor (VMM) 역할을 수행하는 하이퍼바이저입니다. 본 분석에서는 xen-master.zip에서 추출한 소스코드를 바탕으로 Xen 프로젝트의 전체 구조, 빌드 시스템, 의존성 요구사항, 그리고 설치 과정을 종합적으로 분석했습니다.

Xen은 4개의 주요 서브시스템(xen, tools, stubdom, docs)으로 구성되어 있으며, GNU autoconf/automake 기반의 정교한 빌드 시스템을 통해 다양한 플랫폼과 아키텍처를 지원합니다. 특히 x86, ARM, RISC-V 아키텍처를 지원하고, 크로스 컴파일 환경도 완벽하게 지원하여 임베디드 시스템부터 엔터프라이즈급 서버까지 광범위한 환경에서 활용할 수 있습니다.

## 1. Xen 프로젝트의 전체 구조와 주요 구성 요소

### 1.1 최상위 디렉토리 구조

Xen 프로젝트는 다음과 같은 논리적 계층 구조를 가지고 있습니다:

```
xen-master/
├── xen/                    # 핵심 하이퍼바이저 코드
├── tools/                  # 관리 도구 및 라이브러리
├── stubdom/                # 스텁 도메인 컴포넌트
├── docs/                   # 문서 소스
├── automation/             # CI/CD 자동화 스크립트
├── config/                 # 빌드 설정 파일
└── scripts/                # 유틸리티 스크립트
```

### 1.2 핵심 서브시스템 분석

**1.2.1 xen/ 서브시스템 (하이퍼바이저 코어)**

하이퍼바이저의 핵심 구현체로, 계층적이고 모듈화된 구조를 가지고 있습니다. arch 디렉토리는 x86, ARM, RISC-V 등 다양한 아키텍처별 특화 구현을 담고 있으며, common 디렉토리는 스케줄링, 메모리 관리, 도메인 관리와 같은 플랫폼 독립적인 핵심 기능들을 구현합니다. drivers 디렉토리는 ACPI, PCI, USB, 네트워크 등 하드웨어 추상화 계층을 제공하고, include와 lib 디렉토리는 각각 공통 헤더 파일과 라이브러리 함수들을 포함합니다. 특히 crypto 디렉토리는 현대적인 보안 요구사항을 위한 암호화 기능을 별도로 관리합니다.

하이퍼바이저는 Linux의 Kconfig 시스템을 차용하여 구성 옵션을 관리하며, 보안 지원을 위해 대부분의 옵션 변경을 제한하고 있습니다. 전문가 모드(`XEN_CONFIG_EXPERT=y`)를 통해서만 고급 설정이 가능합니다.

**1.2.2 tools/ 서브시스템 (관리 도구)**

Xen 하이퍼바이저를 제어하고 가상 머신을 관리하기 위한 포괄적인 사용자 공간 도구 모음입니다. 9pfsd는 Plan 9 파일시스템 프로토콜을 지원하는 데몬이며, console 도구들은 가상 머신의 콘솔 세션을 관리합니다. debugger는 하이퍼바이저와 게스트 운영체제의 디버깅을 지원하고, firmware 디렉토리는 SeaBIOS와 OVMF 같은 펌웨어 구성요소들을 포함합니다. 특히 flask는 XSM(Xen Security Modules) 프레임워크의 일부로 강제 접근 제어 정책을 구현합니다.

특히 libxl 라이브러리를 통해 현대적인 가상 머신 관리 API를 제공하며, 기본적으로 upstream QEMU를 사용하여 디바이스 에뮬레이션을 수행합니다.

**1.2.3 stubdom/ 서브시스템 (스텁 도메인)**

보안성 향상을 위한 격리된 서비스 도메인들을 구현합니다. c 디렉토리는 C 언어로 작성된 기본 스텁 도메인 구현체를 포함하고, grub은 반가상화 환경에서 부트로더 역할을 하는 PV-GRUB을 구현합니다. vtpm과 vtpmmgr은 각각 가상 Trusted Platform Module과 그 관리자를 구현하여, 클라우드 환경에서도 하드웨어 수준의 보안 기능을 제공할 수 있도록 합니다.

스텁 도메인은 Mini-OS 위에서 실행되며, Dom0의 특권을 분리하여 공격 표면을 줄이는 역할을 합니다.

**1.2.4 docs/ 서브시스템 (문서)**

프로젝트 문서화를 위한 소스 파일들을 포함하며, pandoc을 통해 다양한 형식으로 렌더링됩니다.

### 1.3 XenStore 아키텍처

Xen은 설정 및 상태 정보 공유를 위해 XenStore라는 계층적 데이터베이스를 사용합니다. 두 가지 구현체를 제공합니다:

- **xenstored (C 구현)**: 전통적인 C 기반 구현체
- **oxenstored (OCaml 구현)**: 더 견고하고 현대적인 OCaml 구현체 (기본값)

OCaml 개발 도구가 설치된 경우 oxenstored가 기본으로 선택되며, 런타임에 `/etc/sysconfig/xencommons` 또는 `/etc/default/xencommons` 설정 파일을 통해 변경할 수 있습니다.

## 2. 빌드 시스템 및 설정 파일들

### 2.1 빌드 시스템 아키텍처

Xen의 빌드 시스템은 GNU autoconf/automake를 기반으로 하는 계층적 구조를 가지고 있습니다:

```
configure (최상위)
├── tools/configure
├── stubdom/configure
└── docs/configure
```

### 2.2 주요 설정 파일 분석

**2.2.1 configure.ac (Autoconf 소스)**

최상위 configure.ac는 전체 프로젝트의 메타데이터와 서브시스템 활성화 로직을 정의합니다:

```autoconf
AC_INIT([Xen Hypervisor], m4_esyscmd([./version.sh ./xen/Makefile]),
    [xen-devel@lists.xen.org], [xen], [https://www.xen.org/])
```

플랫폼별 스텁 도메인 지원 여부를 자동으로 감지하며, x86 계열과 x86_64에서만 스텁 도메인을 활성화합니다. FreeBSD에서는 호환성 문제로 인해 스텁 도메인을 비활성화합니다.

**2.2.2 Config.mk (빌드 변수 설정)**

모든 하위 Makefile에서 공유하는 핵심 빌드 변수들을 정의합니다:

- **컴파일러 감지**: GCC 5.0 이상 또는 Clang/LLVM 11 이상 지원
- **아키텍처 감지**: 자동으로 호스트 및 타겟 아키텍처 감지
- **크로스 컴파일 지원**: `XEN_TARGET_ARCH`와 `CROSS_COMPILE` 변수를 통한 완전한 크로스 컴파일 지원
- **upstream 저장소 URL**: QEMU, SeaBIOS, OVMF, Mini-OS 등의 외부 의존성 관리

특히 재현 가능한 빌드를 위해 `SOURCE_DATE_EPOCH` 환경 변수를 지원하며, 빌드 ID 생성 기능을 통해 바이너리 추적성을 제공합니다.

**2.2.3 계층적 Makefile 구조**

최상위 Makefile은 각 서브시스템의 빌드를 조율하는 역할을 합니다:

```makefile
SUBSYSTEMS?=xen tools stubdom docs
```

주요 타겟들:
- **world**: 전체 클린 빌드 (`make clean && make dist`)
- **dist**: 로컬 dist 디렉토리에 설치
- **install**: 시스템 디렉토리에 설치
- **build**: 빌드만 수행 (설치 안함)

### 2.3 Kconfig 시스템

Xen 하이퍼바이저는 Linux 커널의 Kconfig 시스템을 차용하여 설정을 관리합니다:

- **기본 설정**: 보안상의 이유로 대부분의 옵션이 고정됨
- **menuconfig**: `make -C xen menuconfig`를 통한 대화형 설정
- **전문가 모드**: `XEN_CONFIG_EXPERT=y`로 모든 옵션 접근 가능 (보안 지원 제외)

### 2.4 빌드 프로세스

표준 빌드 과정은 다음과 같습니다:

1. **configure 실행**: `./configure [옵션들]`
2. **의존성 체크**: 필수 및 선택적 의존성 확인
3. **빌드**: `make world` 또는 개별 `make build-[subsystem]`
4. **설치**: `make install` 또는 `make dist`

병렬 빌드를 지원하며, `make -j$(nproc)`를 통해 빌드 시간을 단축할 수 있습니다.

## 3. 의존성 패키지 및 라이브러리 요구사항

### 3.1 필수 의존성

**3.1.1 빌드 도구**
- **GNU Make**: 3.80 이상
- **컴파일러**:
  - x86: GCC 5.1+ 또는 Clang/LLVM 11+, GNU Binutils 2.25+
  - ARM: GCC 5.1+, GNU Binutils 2.25+
  - RISC-V 64-bit: GCC 12.2+, GNU Binutils 2.39+
- **POSIX 호환 awk**
- **GNU bison, GNU flex**

**3.1.2 핵심 라이브러리**
- **zlib 개발 패키지** (예: zlib-dev): 압축 지원
- **Python 2.7 이상** (예: python-dev): 다양한 도구들
- **curses 개발 패키지** (예: libncurses-dev): 터미널 인터페이스
- **uuid 개발 패키지** (예: uuid-dev): UUID 생성
- **json-c 0.15+ 또는 yajl** (예: libjson-c-dev, libyajl-dev): JSON 처리
- **libaio 0.3.107+** (예: libaio-dev): 비동기 I/O
- **GLib v2.0** (예: libglib2.0-dev): 기본 라이브러리
- **Pixman** (예: libpixman-1-dev): 픽셀 조작

**3.1.3 시스템 도구**
- **pkg-config**: 패키지 구성 관리
- **bridge-utils** (/sbin/brctl): 네트워크 브릿지 관리
- **iproute** (/sbin/ip): 네트워크 구성
- **ACPI ASL 컴파일러** (iasl): ACPI 테이블 처리

### 3.2 선택적 의존성

**3.2.1 언어별 개발 도구**
- **OCaml 개발 패키지** (ocaml-nox, ocaml-findlib): oxenstored 및 OCaml 도구 빌드용
- **cmake**: vTPM 스텁 도메인 빌드용

**3.2.2 문서화 도구**
- **pandoc**: 문서 변환
- **transfig, pod2{man,html,text}**: 다양한 문서 형식 지원
- **figlet**: 전통적인 Xen 시작 배너 생성

**3.2.3 고급 기능**
- **Binary-search capable grep**: CET 지원 빌드 시 필요
- **systemd daemon 개발 파일**: systemd 통합
- **libnl3 개발 패키지**: Remus 네트워크 버퍼링 지원
- **16-bit x86 도구** (dev86 rpm 또는 bin86 & bcc debs): rombios용
- **압축 라이브러리들**: liblzma, libbz2, liblzo2, libzstd - DomU 커널 압축 해제

### 3.3 펌웨어 의존성

**3.3.1 QEMU 통합**
기본적으로 upstream QEMU의 private copy를 빌드하지만, 시스템 QEMU를 사용하도록 설정할 수 있습니다:
```bash
./configure --with-system-qemu=PATH
```

**3.3.2 BIOS/UEFI 펌웨어**
Xen은 다양한 펌웨어 환경을 지원합니다. SeaBIOS는 전통적인 BIOS 구현으로 기본 BIOS 기능을 제공하며, private copy를 빌드하거나 시스템에 설치된 버전을 사용할 수 있습니다. OVMF는 현대적인 UEFI 펌웨어 구현체로, Secure Boot 등의 고급 기능을 지원하지만 특별한 개발 도구가 필요하며 현재는 실험적 상태입니다.

### 3.4 플랫폼별 요구사항

**3.4.1 Dom0 커널**
Xen 실행을 위해서는 적절한 Dom0 커널이 필요합니다. 가장 안정적인 방법은 OS 배포판에서 제공하는 커널을 사용하는 것이며, 이들은 이미 필요한 패치와 설정이 적용되어 있습니다. 직접 커널을 컴파일하는 경우에는 XenParavirtOps 패치를 적용해야 하고, Xen 백엔드 드라이버 모듈들이 부팅 시 자동으로 로딩될 수 있도록 설정해야 합니다.

**3.4.2 Intel TXT 지원**
Intel Trusted Execution Technology 지원을 위해서는 tboot 모듈이 필수적입니다. tboot는 측정 및 검증된 부팅 과정을 제공하여 하이퍼바이저의 무결성을 보장하며, 이를 위해서는 GRUB 부트로더에서 특별한 설정이 필요합니다. 이 기능은 고보안 환경에서 하드웨어 기반의 신뢰 체인을 구축하는 데 사용됩니다.

## 4. 설치 과정에서 사용되는 스크립트들

### 4.1 핵심 설치 스크립트

**4.1.1 autogen.sh - 빌드 시스템 초기화**

```bash
#!/bin/sh -e
autoconf -f
( cd tools; autoconf -f; autoheader )
( cd stubdom; autoconf -f )
( cd docs; autoconf -f )
```

이 스크립트는 configure.ac 파일들로부터 실제 configure 스크립트를 생성합니다. 개발 환경에서 소스를 직접 수정한 후 빌드 시스템을 재생성할 때 사용됩니다.

**4.1.2 install.sh - 시스템 설치**

Xen의 설치 과정을 자동화하는 스크립트로, 다음과 같은 로직을 수행합니다:

1. **소스 디렉토리 감지**: `./install` 또는 `./dist/install` 중 유효한 경로 선택
2. **임시 디렉토리 생성**: `mktemp -d`를 통한 안전한 임시 공간 확보
3. **파일 복사**: tar를 이용한 효율적인 파일 전송
4. **권한 처리**: `--no-same-owner` 옵션으로 소유권 문제 방지

설치 대상 디렉토리를 인자로 받으며, 기본값은 루트 디렉토리(`/`)입니다:
```bash
./install.sh [대상_디렉토리]
```

**4.1.3 version.sh - 버전 정보 추출**

Xen의 버전 정보를 동적으로 생성하는 스크립트로, 다양한 리비전 식별 방식을 지원합니다. 기본 모드에서는 MAJOR.MINOR 형식(예: 4.21)으로 단순한 버전 번호를 출력하며, 전체 모드(`--full` 옵션)에서는 EXTRAVERSION과 VENDORVERSION을 포함한 상세 버전 정보를 제공합니다. 특히 Git 기반의 개발 버전과 공식 릴리스 버전을 구분하여 처리할 수 있어, 개발 단계별 버전 추적이 가능합니다.

### 4.2 빌드 및 패키징 스크립트

**4.2.1 배포판 패키지 생성**

Xen은 다양한 배포판을 위한 패키지 생성 도구를 제공합니다. debball 명령은 DEB 형식의 컴팩트한 컨테이너를 생성하여 (`make debball`) Debian 계열 시스템에서 쉬운 설치와 제거를 가능하게 합니다. 마찬가지로 rpmball은 RPM 형식의 컴팩트 컨테이너를 생성하고 (`make rpmball`), src-tarball은 QEMU 서브트리를 포함한 완전한 소스 타르볼을 생성합니다. 이들은 완전한 정책 준수 패키지는 아니지만, 실용적인 배포와 관리를 위한 컴팩트 컨테이너 역할을 합니다.

**4.2.2 크로스 컴파일 지원**

Xen은 완전한 크로스 컴파일 환경을 지원합니다:

```bash
./configure --build=x86_64-unknown-linux-gnu --host=aarch64-linux-gnu
make XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
```

### 4.3 시스템 통합 스크립트

**4.3.1 systemd 통합**

systemd 환경에서는 다음 서비스들의 활성화가 필요합니다:

```bash
systemctl enable xen-qemu-dom0-disk-backend.service
systemctl enable xen-init-dom0.service  
systemctl enable xenconsoled.service
systemctl enable xendomains.service      # 선택적
systemctl enable xen-watchdog.service    # 선택적
```

systemd 지원이 감지되면 자동으로 활성화되며, `--disable-systemd` 옵션으로 비활성화할 수 있습니다.

**4.3.2 런레벨 스크립트**

systemd를 사용하지 않는 시스템에서는 전통적인 SysV init 스크립트가 설치됩니다. 스크립트들은 시스템 구성에 따라 `/etc/init.d`, `/etc/rc.d/init.d`, 또는 `/etc/rc.d` 디렉토리에 배치되며, 관련 설정 파일들은 `/etc/sysconfig` 또는 `/etc/default` 하위 디렉토리에 저장됩니다. configure 스크립트가 자동으로 시스템의 디렉토리 구조를 감지하여 적절한 경로를 선택합니다.

### 4.4 QEMU 권한 분리

보안 강화를 위해 QEMU를 비특권 사용자로 실행하는 것이 권장됩니다. 이를 위한 설정은 `docs/misc/qemu-deprivilege.txt`에 상세히 문서화되어 있으며, 설치 시 적절한 사용자 계정과 권한 설정이 필요합니다.

## 결론

Xen 하이퍼바이저는 20년 이상의 개발 역사를 가진 성숙한 가상화 플랫폼으로, 엔터프라이즈급 요구사항을 만족하는 견고한 아키텍처를 가지고 있습니다. 모듈러 설계를 통해 다양한 사용 사례에 맞춘 맞춤형 구성이 가능하며, 포괄적인 빌드 시스템을 통해 개발부터 배포까지의 전체 생명주기를 지원합니다.

특히 보안에 중점을 둔 설계가 돋보이며, 스텁 도메인을 통한 공격 표면 최소화, XSM/Flask 보안 정책 프레임워크, 그리고 Intel TXT와 같은 하드웨어 보안 기능 지원을 통해 고보안 환경에서의 요구사항을 충족합니다.

광범위한 의존성 관리와 정교한 빌드 시스템을 통해 다양한 플랫폼과 아키텍처를 지원하며, 크로스 컴파일과 재현 가능한 빌드를 통해 현대적인 개발 및 배포 환경의 요구사항을 만족합니다. 또한 systemd와 전통적인 SysV init 시스템을 모두 지원하여 다양한 Linux 배포판과의 호환성을 보장합니다.

---

*본 분석은 2025-10-29 기준 Xen Project master 브랜치 소스코드를 대상으로 수행되었습니다.*