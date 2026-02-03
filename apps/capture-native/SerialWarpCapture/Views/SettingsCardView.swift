import Cocoa

/// A rounded card view similar to BetterDisplay's settings cards
class SettingsCardView: NSView {

    private var titleLabel: NSTextField!
    private var contentStackView: NSStackView!
    private var backgroundBox: NSBox!

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupViews(title: title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews(title: String) {
        // Background box with rounded corners
        backgroundBox = NSBox()
        backgroundBox.translatesAutoresizingMaskIntoConstraints = false
        backgroundBox.boxType = .custom
        backgroundBox.cornerRadius = 10
        backgroundBox.borderWidth = 0
        backgroundBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5)
        addSubview(backgroundBox)

        // Title label
        titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        backgroundBox.addSubview(titleLabel)

        // Content stack view
        contentStackView = NSStackView()
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.orientation = .vertical
        contentStackView.alignment = .leading
        contentStackView.spacing = 1
        backgroundBox.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            backgroundBox.topAnchor.constraint(equalTo: topAnchor),
            backgroundBox.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundBox.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundBox.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: backgroundBox.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: backgroundBox.leadingAnchor, constant: 16),

            contentStackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            contentStackView.leadingAnchor.constraint(equalTo: backgroundBox.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: backgroundBox.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: backgroundBox.bottomAnchor, constant: -12)
        ])
    }

    /// Add a settings row to the card
    func addRow(_ row: SettingsRowView) {
        row.widthAnchor.constraint(equalTo: contentStackView.widthAnchor).isActive = true
        contentStackView.addArrangedSubview(row)
    }

    /// Add a custom view to the card
    func addCustomView(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(view)

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: wrapper.topAnchor),
            view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])

        wrapper.widthAnchor.constraint(equalTo: contentStackView.widthAnchor).isActive = true
        contentStackView.addArrangedSubview(wrapper)
    }
}

/// A single row in a settings card with a label and control
class SettingsRowView: NSView {

    private var labelField: NSTextField!
    private var controlContainer: NSView!
    private var separatorView: NSView!

    init(label: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupViews(label: label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews(label: String) {
        // Container for the row content
        let rowContainer = NSView()
        rowContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowContainer)

        // Label
        labelField = NSTextField(labelWithString: label)
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.font = .systemFont(ofSize: 13)
        labelField.textColor = .labelColor
        rowContainer.addSubview(labelField)

        // Control container
        controlContainer = NSView()
        controlContainer.translatesAutoresizingMaskIntoConstraints = false
        rowContainer.addSubview(controlContainer)

        // Separator line
        separatorView = NSView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.wantsLayer = true
        separatorView.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(separatorView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            rowContainer.topAnchor.constraint(equalTo: topAnchor),
            rowContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            rowContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            rowContainer.bottomAnchor.constraint(equalTo: separatorView.topAnchor),

            labelField.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor),
            labelField.centerYAnchor.constraint(equalTo: rowContainer.centerYAnchor),

            controlContainer.trailingAnchor.constraint(equalTo: rowContainer.trailingAnchor),
            controlContainer.centerYAnchor.constraint(equalTo: rowContainer.centerYAnchor),

            separatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    /// Add a control (button, popup, switch, etc.) to the row
    func addControl(_ control: NSView) {
        control.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.addSubview(control)

        NSLayoutConstraint.activate([
            control.topAnchor.constraint(equalTo: controlContainer.topAnchor),
            control.bottomAnchor.constraint(equalTo: controlContainer.bottomAnchor),
            control.leadingAnchor.constraint(equalTo: controlContainer.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: controlContainer.trailingAnchor)
        ])
    }

    /// Hide the separator line (for last item in card)
    func hideSeparator() {
        separatorView.isHidden = true
    }
}
