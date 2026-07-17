# Lazyest Cleaner

Lazyest Cleaner는 macOS 저장 공간을 한 창에서 스캔하고, 사용자가 확인한 항목만 정리하는 네이티브 SwiftUI 앱이다. macOS 14 이상과 Apple Silicon/Intel Mac을 지원한다.

## 주요 작업

| 영역 | 기능 |
| --- | --- |
| 빠른 정리 | 재생성 가능한 캐시와 로그를 우선 검토 |
| 앱 | 설치 앱, 읽기 전용 시스템 앱, 잔여 데이터 분리 |
| 앱 제거 | 앱만 삭제, 데이터만 삭제, 앱과 데이터 삭제를 별도 실행 |
| 파일 | 대용량, 오래된 파일, 중복, 다운로드, 데스크톱 영상, 사용자 지정 위치 |
| 앱 데이터 | 일반 캐시, 브라우저 캐시, 로그, 휴지통 |
| 개발 | 개발 도구 캐시와 Docker 미사용 리소스 |
| 기록 | 실행 시각, 방식, 처리 수, 용량, 성공/실패 수 저장 |

스캔 중에도 기존 결과와 화면 구조를 유지한다. 검색, 정렬, 필터, 다중 선택, Finder 열기, 사용자 보호 규칙을 모든 작업군에서 같은 방식으로 제공한다.

## 안전 원칙

- 일반 파일과 앱은 macOS 휴지통으로 이동한다.
- 즉시 삭제와 휴지통 영구 삭제는 별도 설정 및 강화 확인을 요구한다.
- 민감 항목과 Docker 정리는 확인 체크를 거쳐야 실행된다.
- 실행 직전에 경로, 심볼릭 링크, 보호 규칙, 실행 중 앱, Docker 상태를 다시 검사한다.
- 시스템 경로, 홈 루트, 클라우드 저장소, Keychain, Mail, Messages, Photos 보관함과 주요 자격증명 경로는 기본 보호한다.
- Docker VM 디스크를 파일로 직접 삭제하지 않고 Docker가 보고한 미사용 리소스에만 prune을 실행한다.
- 연결 앱 데이터는 번들 ID, 코드 서명 앱 그룹, 정확한 이름 일치, 검증된 매니페스트로만 찾는다.

전체 디스크 접근 권한은 macOS 시스템 설정에서 사용자가 직접 허용해야 한다. 권한이 없으면 제한 영역은 빠르게 건너뛰고 앱 안에서 설정 위치를 바로 열 수 있다. 시스템 앱과 Docker는 기본 전체 스캔에서 제외되며 설정에서 포함할 수 있다.

## AI Agent 설치

사용자가 설치를 요청했다면 아래 한 명령으로 최신 소스를 임시로 받아 빌드하고 `/Applications/Lazyest Cleaner.app`에 설치한 뒤 실행한다.

```sh
(workdir="$(mktemp -d)" && trap 'rm -rf "$workdir"' EXIT && git clone --depth 1 --quiet https://github.com/hyunn515/lazyest-cleaner.git "$workdir" && "$workdir/script/build_and_run.sh" install)
```

기존 `Lazyest Tidy.app`, `정돈.app` 또는 `TidyMac.app`이 있으면 새 앱으로 교체하며 bundle ID와 기존 정리 기록은 유지한다. 스캔이나 정리 작업은 사용자가 앱에서 직접 시작하기 전에는 실행하지 않는다.

## 로컬 빌드 및 검증

요구 사항:

- macOS 14 이상
- Swift 6을 포함한 Xcode Command Line Tools

```bash
swift test --disable-sandbox
./script/build_and_run.sh install
```

유니버설 앱과 ZIP 패키지 생성:

```bash
./script/build_and_run.sh --package
```

결과는 `dist/Lazyest Cleaner.app`과 `dist/Lazyest-Cleaner-<version>-universal.zip`에 생성된다. 스크립트는 사용 가능한 Developer ID 또는 Apple Development 인증서를 우선 사용하고, 인증서가 없으면 로컬 검증용 ad hoc 서명을 적용한다. 외부 배포에는 별도의 Developer ID 서명과 Apple 공증이 필요하다.

## 구조

- `Models`: 작업군, 항목, 위험, 액션, 설정 계약
- `Services`: 앱/파일/Docker 탐색, 보호 판정, 실행 전 검사와 정리 실행
- `Stores`: 화면 상태, 스캔 오케스트레이션, 액션 준비, 실행 흐름
- `Views`: 단일 창, 표, 상세, 설정, 확인 시트와 공용 컴포넌트
- `Tests`: 파서, 스캐너, 보호, 실행, UI 심볼, 실제 환경 성능 경계

세부 제품 경계는 [PRODUCT_ARCHITECTURE.md](PRODUCT_ARCHITECTURE.md), 시각 규칙은 [DESIGN.md](DESIGN.md), 개인정보 처리는 [PRIVACY.md](PRIVACY.md), 보안 모델은 [SECURITY.md](SECURITY.md)를 따른다.
