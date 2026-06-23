// Copyright Sierra

import UIKit

public final class EndCallButtonPill: UIButton {
    private let buttonWidth: CGFloat = 168.5
    private let buttonHeight: CGFloat = 48
    private let contentInset: CGFloat = 20
    private let contentGap: CGFloat = 6
    private let iconContainerSize = CGSize(width: 32, height: 33)
    private let iconSize = CGSize(width: 23.5, height: 30)
    private let labelLineHeight: CGFloat = 24
    private let labelLetterSpacing: CGFloat = -0.41

    public init(
        backgroundColor: UIColor,
        iconColor: UIColor,
        icon: UIImage?,
        title: String = "End call",
        layout: VoiceControlButtonLayout = .pill
    ) {
        super.init(frame: .zero)
        configure(
            backgroundColor: backgroundColor,
            iconColor: iconColor,
            icon: icon,
            title: title,
            layout: layout
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(
        backgroundColor: UIColor,
        iconColor: UIColor,
        icon: UIImage?,
        title: String,
        layout: VoiceControlButtonLayout
    ) {
        translatesAutoresizingMaskIntoConstraints = false
        tintColor = iconColor
        self.backgroundColor = backgroundColor
        layer.cornerRadius = buttonHeight / 2
        clipsToBounds = true
        accessibilityLabel = title

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.isUserInteractionEnabled = false

        if layout == .compact {
            addSubview(iconContainer)
        }

        let contentStack = UIStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = contentGap
        contentStack.isUserInteractionEnabled = false

        if layout == .pill {
            contentStack.addArrangedSubview(iconContainer)

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.textColor = iconColor
            label.attributedText = labelAttributedText(title, color: iconColor)
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.8
            label.isUserInteractionEnabled = false
            contentStack.addArrangedSubview(label)
            addSubview(contentStack)
        }

        let imageView = UIImageView(
            image: (icon ?? UIImage(named: "EndConversation", in: .module, compatibleWith: nil) ?? UIImage(systemName: "phone.down.fill"))?
                .withRenderingMode(.alwaysTemplate)
        )
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = iconColor
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        iconContainer.addSubview(imageView)

        var constraints: [NSLayoutConstraint] = [
            imageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: iconSize.width),
            imageView.heightAnchor.constraint(equalToConstant: iconSize.height),
            iconContainer.widthAnchor.constraint(equalToConstant: iconContainerSize.width),
            iconContainer.heightAnchor.constraint(equalToConstant: iconContainerSize.height),
        ]

        switch layout {
        case .pill:
            let preferredWidthConstraint = widthAnchor.constraint(equalToConstant: buttonWidth)
            preferredWidthConstraint.priority = .defaultHigh
            constraints.append(contentsOf: [
                preferredWidthConstraint,
                heightAnchor.constraint(equalToConstant: buttonHeight),
                contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
                contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
                contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: contentInset),
                contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -contentInset),
            ])
        case .compact:
            constraints.append(contentsOf: [
                widthAnchor.constraint(equalToConstant: buttonHeight),
                heightAnchor.constraint(equalToConstant: buttonHeight),
                iconContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
                iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        NSLayoutConstraint.activate(constraints)
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
}
