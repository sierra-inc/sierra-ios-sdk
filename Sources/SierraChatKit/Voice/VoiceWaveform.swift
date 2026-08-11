// Copyright Sierra

import UIKit

/// Number of bars in each row of the voice waveform.
public let VOICE_WAVEFORM_BAR_COUNT = 8

/// Default color of the bars driven by the agent's speech.
public let DEFAULT_VOICE_WAVEFORM_AGENT_COLOR = UIColor(red: 125 / 255, green: 211 / 255, blue: 252 / 255, alpha: 1)

/// Default color of the bars driven by the end user's microphone.
public let DEFAULT_VOICE_WAVEFORM_USER_COLOR = UIColor(red: 255 / 255, green: 194 / 255, blue: 102 / 255, alpha: 1)

/// Bounds of the waveform size scale, a multiplier of the default dimensions. Hosts can shrink the
/// waveform to nothing or grow it to 3x; anything outside the range is clamped so a bad value can't
/// break the voice screen layout. Matches the Web SDK's `voiceWaveformSize` bounds.
public let VOICE_WAVEFORM_SCALE_MIN: CGFloat = 0
public let VOICE_WAVEFORM_SCALE_MAX: CGFloat = 3
public let DEFAULT_VOICE_WAVEFORM_SCALE: CGFloat = 1

/// Clamps a host-supplied waveform scale into the supported range. Non-finite values fall back to
/// the default rather than collapsing the waveform.
public func clampedVoiceWaveformScale(_ scale: CGFloat) -> CGFloat {
    guard scale.isFinite else { return DEFAULT_VOICE_WAVEFORM_SCALE }
    return min(VOICE_WAVEFORM_SCALE_MAX, max(VOICE_WAVEFORM_SCALE_MIN, scale))
}

/// Display-frame smoothing shared by both waveform rows. A nil `levels` value matches the Web
/// SDK's null ref: the first analyser sample snaps into place, then later samples use attack or
/// release smoothing.
struct VoiceWaveformLevelSmoother {
    private static let attack: CGFloat = 0.62
    private static let release: CGFloat = 0.26
    private static let epsilon: CGFloat = 0.001

    private(set) var levels: [CGFloat]?

    var displayedLevels: [CGFloat] {
        levels ?? [CGFloat](repeating: 0, count: VOICE_WAVEFORM_BAR_COUNT)
    }

    mutating func step(toward target: [CGFloat]) {
        guard let current = levels else {
            levels = target
            return
        }
        levels = zip(current, target).map { current, target in
            if abs(target - current) <= Self.epsilon {
                return target
            }
            let coefficient = target > current ? Self.attack : Self.release
            return current + (target - current) * coefficient
        }
    }

    mutating func reset() {
        levels = nil
    }

    func needsStep(toward target: [CGFloat]) -> Bool {
        guard let levels else {
            return true
        }
        return zip(levels, target).contains { abs($0 - $1) > Self.epsilon }
    }
}

/// Renders the voice-call waveform: two overlaid rows of rounded bars centered on a shared
/// horizontal axis, one driven by the agent's speech and one by the end user's microphone. The
/// user's row is reversed and composited in hard-light so overlapping bars stay legible. Mirrors
/// the Web SDK's waveform design.
public final class VoiceWaveformView: UIView {
    /// Dimensions at a scale of 1, matching the Web SDK.
    private static let maxBarHeightPx: CGFloat = 32
    private static let barWidthPx: CGFloat = 4
    private static let barGapPx: CGFloat = 2

    public var agentColor: UIColor = DEFAULT_VOICE_WAVEFORM_AGENT_COLOR {
        didSet { setNeedsDisplay() }
    }

    public var userColor: UIColor = DEFAULT_VOICE_WAVEFORM_USER_COLOR {
        didSet { setNeedsDisplay() }
    }

    /// Multiplier of the default waveform dimensions. Values outside
    /// `VOICE_WAVEFORM_SCALE_MIN...VOICE_WAVEFORM_SCALE_MAX` are clamped.
    public var scale: CGFloat = DEFAULT_VOICE_WAVEFORM_SCALE {
        didSet {
            scale = clampedVoiceWaveformScale(scale)
            guard scale != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    private var targetAgentLevels: [CGFloat]?
    private var targetUserLevels: [CGFloat]?
    private var agentSmoother = VoiceWaveformLevelSmoother()
    private var userSmoother = VoiceWaveformLevelSmoother()
    private var displayLink: CADisplayLink?

    public init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        contentMode = .redraw
        isOpaque = false
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    public override var intrinsicContentSize: CGSize {
        let barCount = CGFloat(VOICE_WAVEFORM_BAR_COUNT)
        return CGSize(
            width: barCount * barWidth + (barCount - 1) * barGap,
            height: maxBarHeight
        )
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDisplayLinkState()
    }

    public override var isHidden: Bool {
        didSet { updateDisplayLinkState() }
    }

    /// Sets the agent's per-band levels, each normalized to `0...1`. Levels beyond
    /// `VOICE_WAVEFORM_BAR_COUNT` are ignored and missing bands rest at zero.
    public func setAgentLevels(_ levels: [Float]) {
        dispatchPrecondition(condition: .onQueue(.main))
        targetAgentLevels = Self.normalized(levels)
        updateDisplayLinkState()
    }

    /// Sets the end user's per-band levels, each normalized to `0...1`.
    public func setUserLevels(_ levels: [Float]) {
        dispatchPrecondition(condition: .onQueue(.main))
        targetUserLevels = Self.normalized(levels)
        updateDisplayLinkState()
    }

    /// Drops every bar back to its resting dot immediately, without the release ramp.
    public func resetLevels() {
        dispatchPrecondition(condition: .onQueue(.main))
        targetAgentLevels = nil
        targetUserLevels = nil
        agentSmoother.reset()
        userSmoother.reset()
        setNeedsDisplay()
        stopDisplayLink()
    }

    private var barWidth: CGFloat { Self.barWidthPx * scale }
    private var barGap: CGFloat { Self.barGapPx * scale }
    private var maxBarHeight: CGFloat { Self.maxBarHeightPx * scale }

    private static func normalized(_ levels: [Float]) -> [CGFloat] {
        (0..<VOICE_WAVEFORM_BAR_COUNT).map { index in
            let level = index < levels.count ? CGFloat(levels[index]) : 0
            guard level.isFinite else { return 0 }
            return min(1, max(0, level))
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateDisplayLinkState() {
        // UIKit has no useful work to draw while this view is hidden or detached. Stopping here is
        // the native equivalent of browser requestAnimationFrame pausing for a hidden page; target
        // updates are retained and smoothing resumes when the view is visible again.
        guard window != nil, !isHidden else {
            stopDisplayLink()
            return
        }
        if needsSmoothing {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    @objc private func tick() {
        if let targetAgentLevels {
            agentSmoother.step(toward: targetAgentLevels)
        }
        if let targetUserLevels {
            userSmoother.step(toward: targetUserLevels)
        }
        setNeedsDisplay()
        updateDisplayLinkState()
    }

    private var needsSmoothing: Bool {
        let agentNeedsSmoothing = targetAgentLevels.map { agentSmoother.needsStep(toward: $0) } ?? false
        let userNeedsSmoothing = targetUserLevels.map { userSmoother.needsStep(toward: $0) } ?? false
        return agentNeedsSmoothing || userNeedsSmoothing
    }

    public override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let barWidth = self.barWidth
        guard barWidth > 0 else { return }

        let barCount = CGFloat(VOICE_WAVEFORM_BAR_COUNT)
        let totalWidth = barCount * barWidth + (barCount - 1) * barGap
        let originX = (bounds.width - totalWidth) / 2
        let centerY = bounds.midY

        drawRow(
            levels: agentSmoother.displayedLevels,
            color: agentColor,
            blendMode: .normal,
            originX: originX,
            centerY: centerY,
            context: context
        )
        // The user's row runs in the opposite direction so the two spectra fan out from the middle.
        drawRow(
            levels: Array(userSmoother.displayedLevels.reversed()),
            color: userColor,
            blendMode: .hardLight,
            originX: originX,
            centerY: centerY,
            context: context
        )
        context.setBlendMode(.normal)
    }

    private func drawRow(
        levels: [CGFloat],
        color: UIColor,
        blendMode: CGBlendMode,
        originX: CGFloat,
        centerY: CGFloat,
        context: CGContext
    ) {
        let barWidth = self.barWidth
        let barStride = barWidth + barGap
        context.setBlendMode(blendMode)
        context.setFillColor(color.cgColor)
        for (index, level) in levels.enumerated() {
            // A silent bar rests as a circle the width of the bar.
            let height = max(barWidth, level * maxBarHeight)
            let barRect = CGRect(
                x: originX + CGFloat(index) * barStride,
                y: centerY - height / 2,
                width: barWidth,
                height: height
            )
            context.addPath(UIBezierPath(roundedRect: barRect, cornerRadius: barWidth / 2).cgPath)
            context.fillPath()
        }
    }
}
