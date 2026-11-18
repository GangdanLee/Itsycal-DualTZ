//
//  ScrubberTrackView.swift
//  Itsycal DualTZ
//

import Cocoa

enum DualTZOverlapHelper {
    enum Tier {
        case golden
        case shoulder
        case rest

        var color: NSColor {
            switch self {
            case .golden: return .systemGreen
            case .shoulder: return .systemYellow
            case .rest: return .systemRed
            }
        }

        var prefixLabel: String {
            switch self {
            case .golden: return LocalizationService.pick("🟢 黄金时段", "🟢 Golden Window")
            case .shoulder: return LocalizationService.pick("🟡 一方早晚", "🟡 Off-Peak")
            case .rest: return LocalizationService.pick("🔴 休息时段", "🔴 Sleep Hours")
            }
        }
    }

    static func tier(for date: Date, localTZ: TimeZone = .autoupdatingCurrent) -> Tier {
        let bjHour = TimeZoneService.gregorianCalendar(in: TimeZoneService.beijingTZ).component(.hour, from: date)
        let laHour = TimeZoneService.gregorianCalendar(in: localTZ).component(.hour, from: date)
        if (8...21).contains(bjHour) && (8...21).contains(laHour) {
            return .golden
        }
        if (7...22).contains(bjHour) && (7...22).contains(laHour) {
            return .shoulder
        }
        return .rest
    }
}

final class ScrubberTrackView: NSView {
    var slotColors: [NSColor] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !slotColors.isEmpty else { return }
        let barRect = NSRect(x: 6, y: (bounds.height - 4) / 2.0, width: max(1, bounds.width - 12), height: 4)
        let clip = NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        let segW = barRect.width / CGFloat(slotColors.count)
        for (idx, color) in slotColors.enumerated() {
            color.withAlphaComponent(0.55).setFill()
            NSRect(x: barRect.minX + CGFloat(idx) * segW, y: barRect.minY, width: segW + 0.5, height: barRect.height).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension NSStackView {
    static func dualTZLocked(
        _ views: [NSView],
        orientation: NSUserInterfaceLayoutOrientation,
        alignment: NSLayoutConstraint.Attribute,
        spacing: CGFloat
    ) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = orientation
        stack.alignment = alignment
        stack.spacing = spacing
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        // 水平栈垂直方向不可强行 .required 紧贴，避免 tall/short 混排基准线对齐时矮控件截断高字体
        stack.setHuggingPriority(orientation == .vertical ? .required : .defaultHigh, for: .vertical)
        stack.setContentHuggingPriority(orientation == .vertical ? .required : .defaultHigh, for: .vertical)
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        return stack
    }
}
