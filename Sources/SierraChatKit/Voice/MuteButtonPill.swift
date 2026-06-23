// Copyright Sierra

import UIKit

public final class MuteButtonPill: UIButton, VoiceMuteLevelDisplaying {
    private let buttonWidth: CGFloat = 168.5
    private let buttonHeight: CGFloat = 48
    private let contentInset: CGFloat = 20
    private let contentGap: CGFloat = 6
    private let iconContainerSize = CGSize(width: 32, height: 33)
    private let iconSize = CGSize(width: 14, height: 24)
    private let labelLineHeight: CGFloat = 24
    private let labelLetterSpacing: CGFloat = -0.41

    private let iconColor: UIColor
    private let muteIcon: UIImage?
    private let waveformIcon: UIImage?
    private let title: String
    private let layout: VoiceControlButtonLayout
    private let iconContainer = UIView()
    private let titleLabelView = UILabel()
    private var waveformView: VoiceAudioLevelView?

    public init(
        backgroundColor: UIColor,
        iconColor: UIColor,
        muteIcon: UIImage?,
        waveformIcon: UIImage? = nil,
        title: String = "Mute",
        layout: VoiceControlButtonLayout = .pill
    ) {
        self.iconColor = iconColor
        self.muteIcon = muteIcon
        self.waveformIcon = waveformIcon ?? UIImage(named: "WaveformMic", in: .module, compatibleWith: nil)
        self.title = title
        self.layout = layout
        super.init(frame: .zero)

        configure(backgroundColor: backgroundColor)
        update(inputLevel: 0, outputLevel: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(inputLevel: Float, outputLevel: Float) {
        titleLabelView.attributedText = labelAttributedText(title, color: iconColor)
        accessibilityLabel = title
        iconContainer.subviews.forEach { $0.removeFromSuperview() }
        waveformView = nil

        if let muteIcon {
            installStaticIcon(muteIcon, tintColor: iconColor)
            return
        }

        let waveform = VoiceAudioLevelView(micImage: waveformIcon)
        waveform.translatesAutoresizingMaskIntoConstraints = false
        waveform.micColor = iconColor
        iconContainer.addSubview(waveform)
        NSLayoutConstraint.activate([
            waveform.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            waveform.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            waveform.widthAnchor.constraint(equalToConstant: iconSize.width),
            waveform.heightAnchor.constraint(equalToConstant: iconSize.height),
        ])
        waveformView = waveform
        waveform.setInputLevel(inputLevel)
        waveform.setOutputLevel(outputLevel)
    }

    public func setInputLevel(_ level: Float) {
        waveformView?.setInputLevel(level)
    }

    public func setOutputLevel(_ level: Float) {
        waveformView?.setOutputLevel(level)
    }

    public func resetLevels() {
        waveformView?.resetLevels()
    }

    private func configure(backgroundColor: UIColor) {
        translatesAutoresizingMaskIntoConstraints = false
        tintColor = iconColor
        self.backgroundColor = backgroundColor
        layer.cornerRadius = buttonHeight / 2
        clipsToBounds = true
        accessibilityLabel = title

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.isUserInteractionEnabled = false

        if layout == .compact {
            addSubview(iconContainer)
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: buttonHeight),
                heightAnchor.constraint(equalToConstant: buttonHeight),
                iconContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
                iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconContainer.widthAnchor.constraint(equalToConstant: iconContainerSize.width),
                iconContainer.heightAnchor.constraint(equalToConstant: iconContainerSize.height),
            ])
            return
        }

        let contentStack = UIStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = contentGap
        contentStack.isUserInteractionEnabled = false

        contentStack.addArrangedSubview(iconContainer)

        titleLabelView.translatesAutoresizingMaskIntoConstraints = false
        titleLabelView.textColor = iconColor
        titleLabelView.adjustsFontSizeToFitWidth = true
        titleLabelView.minimumScaleFactor = 0.8
        titleLabelView.isUserInteractionEnabled = false
        contentStack.addArrangedSubview(titleLabelView)
        addSubview(contentStack)

        let preferredWidthConstraint = widthAnchor.constraint(equalToConstant: buttonWidth)
        preferredWidthConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            preferredWidthConstraint,
            heightAnchor.constraint(equalToConstant: buttonHeight),
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: contentInset),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -contentInset),
            iconContainer.widthAnchor.constraint(equalToConstant: iconContainerSize.width),
            iconContainer.heightAnchor.constraint(equalToConstant: iconContainerSize.height),
        ])
    }

    private func labelAttributedText(_ title: String, color: UIColor) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = labelLineHeight
        paragraphStyle.maximumLineHeight = labelLineHeight

        return NSAttributedString(
            string: title,
            attributes: [
                .baselineOffset: (labelLineHeight - 18) / 4,
                .font: UIFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: color,
                .kern: labelLetterSpacing,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    private func installStaticIcon(_ image: UIImage?, tintColor: UIColor) {
        let imageView = UIImageView(image: image?.withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = tintColor
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        iconContainer.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: iconSize.width),
            imageView.heightAnchor.constraint(equalToConstant: iconSize.height),
        ])
    }
}
