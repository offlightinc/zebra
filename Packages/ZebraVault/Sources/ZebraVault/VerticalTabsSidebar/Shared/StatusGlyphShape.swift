import SwiftUI

/// 도메인-중립 status glyph 어휘. `StatusGlyph` 가 직접 그리는 7가지 도형 +
/// unknown placeholder. 각 도메인 enum (BrainTaskStatus / BrainGoalStatus) 이
/// 자기 시각을 `glyphShape` extension 으로 직접 결정. 이전엔 BrainTaskStatus
/// 가 StatusGlyph 의 분기 키였고 Goal 은 어댑터 변환을 거쳤음.
///
/// archived ≠ canceled 처럼 도메인 의미는 다르지만 현 시각이 동일한 경우는
/// 같은 case (`canceledBar`) 로 매핑됨. 별 issue 에서 차별화 case 추가 가능.
enum StatusGlyphShape: Hashable {
    case dashedCircle    // backlog: 점선 stroke
    case openCircle      // todo / goal.draft: 실선 stroke
    case progressRing    // inprogress: blue progress ring + breathing
    case halfFilled      // goal.active: stroke + 우측 반원 채움
    case blockedCircle   // blocked: stroke + 가운데 가로 막대
    case waitingDots     // waiting: 채움 + 점 3개
    case checkFilled     // done / goal.completed: 채움 + 흰 체크
    case canceledBar     // canceled / goal.archived: 채움 + 가로 막대 흑
    case unknown         // raw 가 schema 위반이거나 키 자체 없음

    var tint: Color {
        switch self {
        case .dashedCircle, .openCircle: return BVColor.statusTodo
        case .progressRing:              return Color(red: 0x3b / 255.0, green: 0x82 / 255.0, blue: 0xf6 / 255.0)
        case .halfFilled:                return BVColor.statusDoing
        case .blockedCircle:             return BVColor.statusBlocked
        case .waitingDots:               return BVColor.statusWaiting
        case .checkFilled:               return BVColor.statusCompleted
        case .canceledBar:               return BVColor.statusCanceled
        case .unknown:                   return BVColor.fgFaint
        }
    }
}

// MARK: - Domain → shape

extension BrainTaskStatus {
    var glyphShape: StatusGlyphShape {
        switch self {
        case .backlog:    return .dashedCircle
        case .todo:       return .openCircle
        case .inprogress: return .progressRing
        case .blocked:    return .blockedCircle
        case .waiting:    return .waitingDots
        case .done:       return .checkFilled
        case .canceled:   return .canceledBar
        }
    }
}

extension BrainGoalStatus {
    var glyphShape: StatusGlyphShape {
        switch self {
        case .draft:     return .openCircle
        case .active:    return .halfFilled
        case .blocked:   return .blockedCircle
        case .completed: return .checkFilled
        case .archived:  return .canceledBar
        }
    }

    /// Sentence-case 라벨. `BrainGoalStatus.label` (uppercase) 은 섹션 헤더 용
    /// 으로 유지 — `SidebarSectionHeader` 가 `.uppercased()` 책임지지만 호환 위해
    /// 보존. picker / inspector 에는 이 sentence-case 가 들어감.
    var localizedLabel: String {
        switch self {
        case .active:    return String(localized: "brain.goal.status.active", defaultValue: "Active")
        case .blocked:   return String(localized: "brain.goal.status.blocked", defaultValue: "Blocked")
        case .draft:     return String(localized: "brain.goal.status.draft", defaultValue: "Draft")
        case .completed: return String(localized: "brain.goal.status.completed", defaultValue: "Completed")
        case .archived:  return String(localized: "brain.goal.status.archived", defaultValue: "Archived")
        }
    }
}
