# Lazyest Cleaner 제품 구조

## 목표

Lazyest Cleaner는 macOS 저장 공간을 탐색하고, 삭제 후보를 한곳에서 비교하고, 사용자가 선택한 항목만 안전하게 처리하는 네이티브 데스크톱 도구다. 첫 화면은 실제 정리 화면이며 별도 소개 화면을 두지 않는다.

## 작업 분류

| 작업군 | 화면 | 대상 | 기본 처리 | 자동 추천 |
| --- | --- | --- | --- | --- |
| 요약 | 전체, 빠른 정리 | 모든 스캔 결과, 안전 후보 | 검토 화면으로 이동 | 안전 후보만 |
| 앱 | 설치 앱, 시스템 앱, 잔여 데이터 | `/Applications`, `~/Applications`, `/System/Applications`, 시스템 도구, 앱별 데이터 | 앱만, 앱 데이터만, 앱과 데이터 | 자동 선택 안 함 |
| 파일 | 대용량, 오래된 파일, 중복, 다운로드, 데스크톱 영상 | 사용자 선택 루트 | 휴지통 | 설치 파일·명확한 중복 사본만 |
| 개발 | 개발 도구, Docker | DerivedData, 패키지 캐시, Docker CLI가 보고한 미사용 리소스 | 휴지통 또는 Docker prune | 재다운로드 가능한 캐시만 |
| 앱 데이터 | 캐시, 브라우저, 로그, 휴지통 | 사용자 Library, `~/.Trash` | 휴지통, 안전 삭제, 영구 삭제 | 종료된 앱의 캐시만 |
| 사용자 지정 | 폴더 스캔 | 사용자가 고른 폴더 | 휴지통 | 안 함 |
| 기록 | 정리 이력 | 앱이 실행한 작업 | Finder 또는 세부 정보 | 해당 없음 |

## 위험 모델

| 단계 | 의미 | 기본 선택 | 실행 조건 |
| --- | --- | --- | --- |
| 안전 | 재생성 가능하고 사용자 원본이 아님 | 선택 | 간단 확인 |
| 검토 | 사용자 판단이 필요한 파일 또는 앱 | 미선택 | 명시적 선택 |
| 민감 | 볼륨, 앱 데이터, 프로젝트 산출물 | 미선택 | 강화 확인 |
| 보호 | 시스템 또는 보호 규칙과 충돌 | 선택 불가 | 보호 해제 후 재스캔 |

항목은 실행 직전에 경로, 심볼릭 링크, 보호 규칙, 실행 중 앱, Docker 상태를 다시 검사한다. 스캔 당시의 판정을 그대로 신뢰하지 않는다.

## 기본 보호

- 앱: Lazyest Cleaner 자체와 현재 실행 중인 모든 앱
- 경로: `~/Library/CloudStorage`
- 시스템: `/System`, `/usr`, `/bin`, `/sbin`, `/private`, 사용자 홈 루트
- 개인 데이터: Keychain, Mail, Messages, Photos Library
- 자격증명: `.ssh`, `.gnupg`, `.aws`, `.docker`, `.kube`, gcloud 설정과 주요 자격증명 파일
- Docker: 실행 중 컨테이너와 사용 중 볼륨
- Docker VM: `~/Library/Containers/com.docker.docker` 직접 삭제 금지
- 사용자 규칙: 임의 폴더와 앱을 보호 목록에 추가 가능
- 원칙: 보호 경로 자체뿐 아니라 보호 경로를 포함하는 상위 폴더도 삭제할 수 없다.

특정 사용자 프로젝트는 제품 코드에 하드코딩하지 않는다. 사용자별 예외는 설정 데이터로 저장하고, 비표준 앱 데이터 위치는 번들 ID 기반의 검증된 제품 매니페스트로만 추가한다.

## 통합 액션 규격

모든 명령은 `CleanupActionID`와 `ActionDescriptor`로 표현한다. 화면은 자체 버튼 문구나 위험 규칙을 만들지 않는다.

```swift
struct ActionDescriptor {
    let id: CleanupActionID
    let title: String
    let systemImage: String
    let tooltip: String
    let role: ActionRole
    let selectionPolicy: SelectionPolicy
    let confirmation: ConfirmationPolicy
    let shortcut: ActionShortcut?
}
```

| 액션 | 아이콘 | 선택 조건 | 확인 | 배치 |
| --- | --- | --- | --- | --- |
| 다시 스캔 | `arrow.clockwise` | 없음 | 없음 | 툴바, 메뉴 |
| 추천 선택 | `checkmark.circle` | 결과 있음 | 없음 | 툴바, 메뉴 |
| 선택 해제 | `xmark.circle` | 선택 있음 | 없음 | 툴바, 메뉴 |
| Finder에서 보기 | `folder` | 단일 항목 | 없음 | 하단, 메뉴 |
| 보호 | `lock` | 파일 항목 | 없음 | 하단, 메뉴 |
| 휴지통으로 | `trash` | 실행 가능 항목 | 일반 | 하단, 메뉴 |
| 즉시 삭제 | `eraser` | 허용 설정이 켜진 캐시·로그 | 강화 | 하단 보조 메뉴 |
| 앱만 삭제 | `minus.square` | 설치 앱 | 일반 | 앱 보조 메뉴 |
| 데이터만 삭제 | `externaldrive.badge.minus` | 설치 앱 | 강화 | 앱 하단 |
| 앱 + 데이터 삭제 | `trash.slash` | 설치 앱 | 강화 | 앱 하단 |
| 영구 삭제 | `trash.slash` | 휴지통 항목 | 강화 | 휴지통 하단 |
| Docker 정리 | `shippingbox` | Docker 항목 | 강화 | 하단, 메뉴 |
| 취소 | `xmark` | 스캔 중 | 없음 | 툴바 |

동일한 descriptor가 툴바, 하단 실행바, 컨텍스트 메뉴, 앱 메뉴에 재사용된다. 활성 조건과 확인 방식도 동일한 resolver에서 계산한다.

## 화면 구조

- `Window`: 새 창을 만들지 않는 단일 작업 창. 상태 복원 허용.
- `NavigationSplitView`: 상위 작업군 사이드바와 상세 영역.
- 사이드바: 개요, 빠른 정리, 앱, 파일, 앱 데이터, 개발, 기록, 설정.
- 세부 분류: 상세 상단의 네이티브 분류 메뉴로 전환.
- 앱 탭: 설치 앱, 시스템 앱, 잔여 데이터. 시스템 앱은 읽기 전용이다.
- 개발 탭: 개발 도구, Docker.
- 설정: 일반, 스캔 위치, 보호를 메인 창 안에서 전환.
- 상세 상단: 짧은 제목, 항목 수, 선택 용량, 스캔 상태.
- 상세 본문: 정렬 가능한 테이블.
- 하단 실행바: 선택 항목의 이름과 경로, 주 실행 액션, 보조 액션 메뉴.
- 확인: 삭제와 Docker 정리만 현재 창에 붙는 시트로 표시.
- 첫 실행: 자동 스캔은 기본으로 꺼져 있고 사용자가 스캔을 시작한다.
- 전체 스캔: 시스템 앱과 Docker는 기본 제외하며 일반 설정에서 각각 포함 가능.

## 텍스트 규칙

- 화면 설명 문단은 사용하지 않는다.
- 제목, 상태, 열 이름, 버튼 이름만 항상 보인다.
- 동작 설명, 위험 근거, 예외 조건은 `.help(...)` 툴팁에 둔다.
- 확인창은 대상 수, 용량, 실행 방식만 짧게 표시한다.
- 오류는 한 줄 요약과 세부 보기로 분리한다.

## 실행 흐름

1. 스캔
2. 분류 및 위험 판정
3. 검색·정렬·필터
4. 추천 또는 수동 선택
5. 실행 전 재검증
6. 짧은 확인
7. 휴지통 또는 허용된 도구 명령 실행
8. 결과 기록 및 재스캔

## 코드 책임

- `Models`: 작업군, 항목, 위험, 액션, 설정처럼 UI와 서비스가 공유하는 계약.
- `Services`: 파일 시스템 및 Docker I/O, 분류, 보호 판정, 크기 측정, 실행 전 검증과 실행.
- `Stores/CleanupStore.swift`: 관찰 가능한 핵심 상태와 파생 쿼리.
- `Stores/CleanupStore+Scanning.swift`: 전체/현재 작업군 스캔과 취소.
- `Stores/CleanupStore+Actions.swift`: 통합 액션 해석과 확인 준비 진입점.
- `Stores/CleanupStore+Execution.swift`: 앱 데이터 준비, 확인, 실행, 기록.
- `Views`: 상태를 표시하고 descriptor 기반 명령만 전달하는 단일 창 UI.

화면과 컨텍스트 메뉴는 `CleanupActionResolver`를 공유한다. 스캔 오류는 `CleanupScanIssueMapper`, 전체 스캔 범위는 `FullScanPlan`에서 결정해 화면별 규칙 중복을 막는다.

## 경계

- Docker의 `~/Library/Containers/com.docker.docker`는 직접 삭제하지 않는다.
- 브라우저 프로필, 쿠키, 비밀번호, 방문 기록은 캐시로 분류하지 않는다.
- CloudStorage 문서는 직접 삭제 후보로 만들지 않는다.
- 관리자 권한이 필요한 시스템 경로는 읽기 결과만 표시하며 우회 삭제하지 않는다.
- 앱 제거는 `앱만 삭제`, `데이터만 삭제`, `앱 + 데이터 삭제`를 구분한다. 연결 데이터는 정확 경로, 코드 서명 앱 그룹, 검증된 매니페스트만 포함하고 파일 시스템 식별자로 중복 제거한다.
