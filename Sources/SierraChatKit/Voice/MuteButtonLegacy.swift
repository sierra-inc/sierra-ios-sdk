// Copyright Sierra

import UIKit

public final class MuteButtonLegacy: UIButton {
    private let buttonSize: CGFloat = 56

    public init(
        backgroundColor: UIColor,
        iconColor: UIColor,
        muteIcon: UIImage?
    ) {
        super.init(frame: .zero)

        configure(backgroundColor: backgroundColor)
        setImage((muteIcon ?? UIImage(systemName: "mic.fill"))?.withRenderingMode(.alwaysTemplate), for: .normal)
        tintColor = iconColor
        accessibilityLabel = "Mute microphone"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(backgroundColor: UIColor) {
        translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = backgroundColor
        layer.cornerRadius = buttonSize / 2
        clipsToBounds = true
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: buttonSize),
            heightAnchor.constraint(equalToConstant: buttonSize),
        ])
    }
}
