import SwiftUI

struct SettingsView: View {
    @State private var section: SettingsSection
    private let protectionHome: URL?

    init(section: SettingsSection = .general, protectionHome: URL? = nil) {
        _section = State(initialValue: section)
        self.protectionHome = protectionHome
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("설정", selection: $section) {
                    ForEach(SettingsSection.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 380, alignment: .leading)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.spacing16)
            .padding(.vertical, DesignTokens.spacing12)

            Divider()

            switch section {
            case .general:
                GeneralSettingsPane()
            case .locations:
                ScanLocationsPane()
            case .protection:
                ProtectionSettingsPane(home: protectionHome)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum SettingsSection: CaseIterable, Identifiable {
    case general
    case locations
    case protection

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "일반"
        case .locations: "스캔 위치"
        case .protection: "보호"
        }
    }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .locations: "folder"
        case .protection: "lock.shield"
        }
    }
}

private struct GeneralSettingsPane: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        @Bindable var settings = store.settings
        List {
            Section("스캔") {
                SettingsToggle(title: "화면을 열 때 자동 스캔", isOn: $settings.autoScan)
                    .help("처음 연 분류를 자동으로 스캔합니다.")
                SettingsToggle(title: "숨김 파일 포함", isOn: $settings.includeHiddenFiles)
                    .help("사용자 파일 스캔에 숨김 파일을 포함합니다.")
                SettingsToggle(
                    title: "전체 스캔에 시스템 앱 포함",
                    isOn: $settings.includeSystemApplicationsInFullScan
                )
                .help("읽기 전용 시스템 앱 목록도 전체 스캔에서 계산합니다.")
                SettingsToggle(
                    title: "전체 스캔에 Docker 포함",
                    isOn: $settings.includeDockerInFullScan
                )
                .help("Docker 엔진 조회를 전체 스캔에 포함합니다.")

                Picker("대용량 기준", selection: $settings.largeFileThreshold) {
                    Text("250 MB").tag(Int64(250_000_000))
                    Text("500 MB").tag(Int64(500_000_000))
                    Text("1 GB").tag(Int64(1_000_000_000))
                    Text("2 GB").tag(Int64(2_000_000_000))
                    Text("5 GB").tag(Int64(5_000_000_000))
                }
                .help("대용량 파일로 표시할 최소 크기입니다.")

                HStack {
                    Text("오래된 파일")
                    Spacer()
                    Text("\(settings.oldFileDays)일")
                        .monospacedDigit()
                    Stepper("오래된 파일", value: $settings.oldFileDays, in: 7...730, step: 7)
                        .labelsHidden()
                        .fixedSize()
                }
                .help("수정일이 이 기간보다 오래된 파일을 표시합니다.")

                Picker("중복 최소 크기", selection: $settings.duplicateMinimumSize) {
                    Text("1 MB").tag(Int64(1_000_000))
                    Text("10 MB").tag(Int64(10_000_000))
                    Text("50 MB").tag(Int64(50_000_000))
                    Text("100 MB").tag(Int64(100_000_000))
                }
                .help("해시를 비교할 파일의 최소 크기입니다.")
            }

            Section("실행") {
                SettingsToggle(title: "즉시 삭제 허용", isOn: $settings.allowImmediateRemoval)
                    .help("캐시와 로그에만 휴지통 없는 삭제를 허용합니다.")
                SettingsToggle(title: "Docker 볼륨 포함", isOn: $settings.includeDockerVolumes)
                    .help("미사용 볼륨을 Docker 정리 후보에 포함합니다.")
            }
        }
        .listStyle(.inset)
    }
}

private struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct ScanLocationsPane: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        List {
            Section("사용자 지정") {
                ForEach(store.settings.customScanRoots, id: \.standardizedFileURL.path) { url in
                    LocationRow(url: url) {
                        store.removeScanRoot(url)
                    }
                }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsListBar {
                store.addScanLocations()
            }
        }
    }
}

private struct ProtectionSettingsPane: View {
    @Environment(CleanupStore.self) private var store
    let home: URL?

    var body: some View {
        let builtIns = ProtectionPolicy(home: home).rules.filter(\.isBuiltIn)
        List {
            Section("기본") {
                AlignedSymbolLabel(title: "현재 실행 중인 앱", systemImage: "app.badge.checkmark")
                    .help("실행 중인 앱은 제거할 수 없습니다.")
                ForEach(builtIns) { rule in
                    HStack(spacing: DesignTokens.spacing8) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: DesignTokens.labelIconWidth)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.reason)
                            Text(rule.url.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .help(rule.url.path)
                }
            }

            Section("사용자") {
                ForEach(store.settings.customProtectedPaths, id: \.standardizedFileURL.path) { url in
                    LocationRow(url: url) {
                        store.removeProtectedPath(url)
                    }
                }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsListBar {
                store.addProtectedLocations()
            }
        }
    }
}

private struct LocationRow: View {
    let url: URL
    let remove: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.spacing8) {
            Image(systemName: url.pathExtension == "app" ? "app" : "folder")
                .frame(width: DesignTokens.labelIconWidth)
            Text(url.path)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .help(url.path)
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("목록에서 제거")
            .accessibilityLabel("목록에서 제거")
        }
    }
}

private struct SettingsListBar: View {
    let add: () -> Void

    var body: some View {
        HStack {
            Button(action: add) {
                Image(systemName: "plus")
                    .frame(
                        width: DesignTokens.iconButtonSize,
                        height: DesignTokens.iconButtonSize
                    )
            }
            .buttonStyle(.borderless)
            .help("추가")
            .accessibilityLabel("추가")
            Spacer()
        }
        .padding(.horizontal, DesignTokens.spacing16)
        .frame(height: 52)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
