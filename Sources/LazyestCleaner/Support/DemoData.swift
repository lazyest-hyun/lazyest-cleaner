import Foundation

enum DemoData {
    static let storage = StorageSnapshot(
        total: 1_000_000_000_000,
        available: 238_000_000_000
    )

    static func items() -> [CleanupCategory: [CleanupItem]] {
        let now = Date()
        let day: TimeInterval = 86_400
        let roots = URL(fileURLWithPath: "/Users/demo")

        func item(
            _ category: CleanupCategory,
            _ kind: CleanupItemKind,
            _ name: String,
            _ path: String?,
            _ size: Int64,
            _ risk: CleanupRisk,
            _ recommendation: CleanupRecommendation,
            _ operation: CleanupOperation = .recycle,
            _ source: String,
            modifiedDays: Double = 12,
            detail: String? = nil,
            protectedReason: String? = nil,
            bundleIdentifier: String? = nil,
            duplicateGroupID: String? = nil,
            metadata: [String: String] = [:]
        ) -> CleanupItem {
            let url = path.map { roots.appending(path: $0) }
            return CleanupItem(
                id: CleanupItem.stableID(prefix: category.rawValue, value: path ?? name),
                category: category,
                kind: kind,
                name: name,
                url: url,
                size: size,
                modifiedAt: now.addingTimeInterval(-day * modifiedDays),
                risk: risk,
                recommendation: recommendation,
                operation: operation,
                source: source,
                detail: detail,
                protectedReason: protectedReason,
                bundleIdentifier: bundleIdentifier,
                duplicateGroupID: duplicateGroupID,
                metadata: metadata
            )
        }

        let quick: [CleanupItem] = [
            item(
                .quickClean, .cache, "앱 캐시", "Library/Caches/com.example.editor", 2_420_000_000, .safe, .recommended,
                .removeImmediately, "앱 캐시"),
            item(
                .quickClean, .browserCache, "브라우저 캐시", "Library/Caches/ExampleBrowser", 1_180_000_000, .safe,
                .recommended, .removeImmediately, "브라우저"),
            item(
                .quickClean, .developerCache, "패키지 캐시", "Library/Caches/dev.packages", 864_000_000, .safe, .recommended,
                .removeImmediately, "개발 도구"),
            item(
                .quickClean, .log, "진단 로그", "Library/Logs/DiagnosticReports", 146_000_000, .safe, .recommended,
                .removeImmediately, "로그"),
        ]

        let applications: [CleanupItem] = [
            item(
                .applications, .application, "Studio Pro", "Applications/Studio Pro.app", 8_760_000_000, .review,
                .avoid, .recycle, "응용 프로그램", modifiedDays: 21, bundleIdentifier: "com.example.studio",
                metadata: ["버전": "12.4"]),
            item(
                .applications, .application, "Vector Lab", "Applications/Vector Lab.app", 3_240_000_000, .review,
                .avoid, .recycle, "응용 프로그램", modifiedDays: 86, bundleIdentifier: "com.example.vector",
                metadata: ["버전": "6.8"]),
            item(
                .applications, .application, "Current Editor", "Applications/Current Editor.app", 1_460_000_000,
                .protected, .avoid, .recycle, "응용 프로그램", modifiedDays: 2, detail: "앱 실행 중", protectedReason: "실행 중",
                bundleIdentifier: "com.example.current", metadata: ["버전": "4.2"]),
        ]

        let systemApplications: [CleanupItem] = [
            item(
                .systemApplications, .application, "Finder", "System/Applications/Finder.app", 618_000_000, .protected,
                .avoid, .revealOnly, "시스템 앱", modifiedDays: 2, protectedReason: "시스템 앱",
                bundleIdentifier: "com.apple.finder", metadata: ["버전": "15.0"]),
            item(
                .systemApplications, .application, "Safari", "System/Applications/Safari.app", 1_240_000_000,
                .protected, .avoid, .revealOnly, "시스템 앱", modifiedDays: 5, protectedReason: "시스템 앱",
                bundleIdentifier: "com.apple.Safari", metadata: ["버전": "18.0"]),
        ]

        let leftovers: [CleanupItem] = [
            item(
                .leftovers, .appLeftover, "com.example.retired", "Library/Caches/com.example.retired", 782_000_000,
                .review, .optional, .recycle, "고아 데이터"),
            item(
                .leftovers, .appLeftover, "ExampleSuite", "Library/Application Support/ExampleSuite", 438_000_000,
                .sensitive, .avoid, .recycle, "앱 데이터"),
        ]

        let largeFiles: [CleanupItem] = [
            item(
                .largeFiles, .file, "screen-recording.mov", "Movies/screen-recording.mov", 12_480_000_000, .review,
                .optional, .recycle, "대용량", modifiedDays: 47),
            item(
                .largeFiles, .file, "dataset.archive", "Documents/dataset.archive", 6_320_000_000, .review, .optional,
                .recycle, "대용량", modifiedDays: 112),
            item(
                .largeFiles, .file, "cloud-project.bundle", "Library/CloudStorage/Drive/cloud-project.bundle",
                4_780_000_000, .protected, .avoid, .revealOnly, "대용량", modifiedDays: 8, protectedReason: "클라우드 문서"),
        ]

        let oldFiles: [CleanupItem] = [
            item(
                .oldFiles, .file, "archive-2023.zip", "Documents/Archive/archive-2023.zip", 2_860_000_000, .review,
                .optional, .recycle, "오래된 파일", modifiedDays: 520),
            item(
                .oldFiles, .file, "export-final-2.psd", "Desktop/export-final-2.psd", 1_240_000_000, .review, .optional,
                .recycle, "오래된 파일", modifiedDays: 184),
        ]

        let duplicates: [CleanupItem] = [
            item(
                .duplicates, .duplicateOriginal, "conference-cut.mp4", "Movies/conference-cut.mp4", 3_840_000_000,
                .protected, .avoid, .revealOnly, "중복 A71C", modifiedDays: 23, detail: "3개 사본", protectedReason: "기준 사본",
                duplicateGroupID: "A71C"),
            item(
                .duplicates, .duplicateCopy, "conference-cut.mp4", "Downloads/conference-cut.mp4", 3_840_000_000,
                .review, .optional, .recycle, "중복 A71C", modifiedDays: 22, detail: "3개 사본", duplicateGroupID: "A71C"),
            item(
                .duplicates, .duplicateCopy, "conference-cut-copy.mp4", "Desktop/conference-cut-copy.mp4",
                3_840_000_000, .review, .optional, .recycle, "중복 A71C", modifiedDays: 21, detail: "3개 사본",
                duplicateGroupID: "A71C"),
        ]

        let downloads: [CleanupItem] = [
            item(
                .downloads, .installer, "Editor-8.2.dmg", "Downloads/Editor-8.2.dmg", 1_240_000_000, .safe,
                .recommended, .recycle, "다운로드", modifiedDays: 31),
            item(
                .downloads, .file, "raw-assets.zip", "Downloads/raw-assets.zip", 786_000_000, .review, .optional,
                .recycle, "다운로드", modifiedDays: 11),
        ]

        let desktopMedia: [CleanupItem] = [
            item(
                .desktopMedia, .file, "capture-001.mov", "Desktop/capture-001.mov", 5_460_000_000, .review, .optional,
                .recycle, "데스크톱", modifiedDays: 64),
            item(
                .desktopMedia, .file, "meeting-recording.mp4", "Desktop/meeting-recording.mp4", 2_120_000_000, .review,
                .optional, .recycle, "데스크톱", modifiedDays: 19),
        ]

        let caches = quick.filter { $0.kind == .cache }.map { copy($0, category: .caches) }
        let browser = quick.filter { $0.kind == .browserCache }.map { copy($0, category: .browserData) }
        let developer: [CleanupItem] = [
            item(
                .developerData, .developerCache, "Xcode DerivedData", "Library/Developer/Xcode/DerivedData",
                14_620_000_000, .safe, .recommended, .removeImmediately, "Xcode"),
            item(
                .developerData, .developerCache, "패키지 캐시", "Library/Caches/dev.packages", 864_000_000, .safe,
                .recommended, .removeImmediately, "패키지"),
        ]

        let docker: [CleanupItem] = [
            item(
                .docker, .dockerBuildCache, "빌드 캐시", nil, 18_340_000_000, .safe, .recommended, .docker(.buildCache),
                "Docker", metadata: ["전체": "42", "사용 중": "0"]),
            item(
                .docker, .dockerImage, "미사용 이미지", nil, 9_820_000_000, .review, .optional, .docker(.images), "Docker",
                metadata: ["전체": "18", "사용 중": "7"]),
            item(
                .docker, .dockerContainer, "중지 컨테이너", nil, 624_000_000, .review, .optional, .docker(.containers),
                "Docker", metadata: ["전체": "11", "사용 중": "4"]),
            item(
                .docker, .dockerVolume, "미사용 볼륨", nil, 6_480_000_000, .protected, .avoid, .docker(.volumes), "Docker",
                protectedReason: "볼륨 제외 설정", metadata: ["전체": "9", "사용 중": "5"]),
        ]

        let logs = quick.filter { $0.kind == .log }.map { copy($0, category: .logs) }
        let trash: [CleanupItem] = [
            item(.trash, .trash, "휴지통", ".Trash", 7_620_000_000, .review, .optional, .removeImmediately, "휴지통")
        ]

        return [
            .quickClean: quick,
            .applications: applications,
            .systemApplications: systemApplications,
            .leftovers: leftovers,
            .largeFiles: largeFiles,
            .oldFiles: oldFiles,
            .duplicates: duplicates,
            .downloads: downloads,
            .desktopMedia: desktopMedia,
            .caches: caches,
            .browserData: browser,
            .developerData: developer,
            .docker: docker,
            .logs: logs,
            .trash: trash,
        ]
    }

    private static func copy(_ item: CleanupItem, category: CleanupCategory) -> CleanupItem {
        CleanupItem(
            id: CleanupItem.stableID(prefix: category.rawValue, value: item.url?.path ?? item.name),
            category: category,
            kind: item.kind,
            name: item.name,
            url: item.url,
            size: item.size,
            modifiedAt: item.modifiedAt,
            risk: item.risk,
            recommendation: item.recommendation,
            operation: item.operation,
            source: item.source,
            detail: item.detail,
            protectedReason: item.protectedReason,
            bundleIdentifier: item.bundleIdentifier,
            duplicateGroupID: item.duplicateGroupID,
            metadata: item.metadata
        )
    }
}
