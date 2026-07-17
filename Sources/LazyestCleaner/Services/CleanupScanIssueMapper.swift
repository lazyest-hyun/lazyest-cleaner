import Foundation

enum CleanupScanIssueMapper {
    static func issue(
        category: CleanupCategory,
        error: any Error
    ) -> CleanupScanIssue {
        if let accessError = error as? FullDiskAccessError {
            return CleanupScanIssue(
                kind: .permissionDenied,
                title: "전체 디스크 접근 권한 필요",
                detail: accessError.localizedDescription
            )
        }

        if let accessError = error as? DirectoryAccessError {
            return CleanupScanIssue(
                kind: .permissionDenied,
                title: "전체 디스크 접근 권한 필요",
                detail: accessError.localizedDescription
            )
        }

        if let trashError = error as? TrashAccessError {
            switch trashError {
            case .permissionDenied:
                return CleanupScanIssue(
                    kind: .permissionDenied,
                    title: "휴지통 접근 권한 필요",
                    detail: trashError.localizedDescription
                )
            case .unavailable:
                return CleanupScanIssue(
                    kind: .failed,
                    title: "휴지통을 읽을 수 없음",
                    detail: trashError.localizedDescription
                )
            }
        }

        if let dockerError = error as? DockerServiceError {
            switch dockerError {
            case .unavailable, .daemonUnavailable:
                return CleanupScanIssue(
                    kind: .unavailable,
                    title: "Docker 실행 필요",
                    detail: dockerError.localizedDescription
                )
            case .timedOut:
                return CleanupScanIssue(
                    kind: .timedOut,
                    title: "Docker 응답 시간 초과",
                    detail: dockerError.localizedDescription
                )
            case .commandFailed, .invalidResponse:
                return CleanupScanIssue(
                    kind: .failed,
                    title: "Docker 스캔 실패",
                    detail: dockerError.localizedDescription
                )
            }
        }

        return CleanupScanIssue(
            kind: .failed,
            title: "\(category.title) 스캔 실패",
            detail: error.localizedDescription
        )
    }
}
