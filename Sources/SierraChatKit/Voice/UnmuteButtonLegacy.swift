// Copyright Sierra

import UIKit

public final class UnmuteButtonLegacy: UIButton {
    private let buttonSize: CGFloat = 56

    public init(
        backgroundColor: UIColor,
        iconColor: UIColor,
        unmuteIcon: UIImage?
    ) {
        super.init(frame: .zero)
        configure(backgroundColor: backgroundColor, iconColor: iconColor, unmuteIcon: unmuteIcon)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(backgroundColor: UIColor, iconColor: UIColor, unmuteIcon: UIImage?) {
        translatesAutoresizingMaskIntoConstraints = false
        setImage((unmuteIcon ?? UIImage(systemName: "mic.slash.fill"))?.withRenderingMode(.alwaysTemplate), for: .normal)
        tintColor = iconColor
        self.backgroundColor = backgroundColor
        layer.cornerRadius = buttonSize / 2
        clipsToBounds = true
        accessibilityLabel = "Unmute microphone"
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: buttonSize),
            heightAnchor.constraint(equalToConstant: buttonSize),
        ])
    }
}
