import Cocoa

/// About view with app information
class AboutView: NSView {

    private var stackView: NSStackView!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 16

        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Header
        let header = HeaderView(title: "About")
        stackView.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // App Info Card
        setupAppInfoCard()

        // System Info Card
        setupSystemInfoCard()
    }

    private func setupAppInfoCard() {
        let card = SettingsCardView(title: "Application")

        // Version row
        let versionRow = SettingsRowView(label: "Version")
        let versionLabel = NSTextField(labelWithString: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.font = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionRow.addControl(versionLabel)
        card.addRow(versionRow)

        // Build row
        let buildRow = SettingsRowView(label: "Build")
        let buildLabel = NSTextField(labelWithString: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
        buildLabel.translatesAutoresizingMaskIntoConstraints = false
        buildLabel.font = .systemFont(ofSize: 13)
        buildLabel.textColor = .secondaryLabelColor
        buildRow.addControl(buildLabel)
        card.addRow(buildRow)

        stackView.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    private func setupSystemInfoCard() {
        let card = SettingsCardView(title: "System")

        // macOS Version row
        let osRow = SettingsRowView(label: "macOS")
        let osLabel = NSTextField(labelWithString: ProcessInfo.processInfo.operatingSystemVersionString)
        osLabel.translatesAutoresizingMaskIntoConstraints = false
        osLabel.font = .systemFont(ofSize: 13)
        osLabel.textColor = .secondaryLabelColor
        osRow.addControl(osLabel)
        card.addRow(osRow)

        // Screen Recording Permission row
        let permissionRow = SettingsRowView(label: "Screen Recording")
        let hasPermission = CGPreflightScreenCaptureAccess()
        let permissionLabel = NSTextField(labelWithString: hasPermission ? "Granted" : "Not Granted")
        permissionLabel.translatesAutoresizingMaskIntoConstraints = false
        permissionLabel.font = .systemFont(ofSize: 13)
        permissionLabel.textColor = hasPermission ? .systemGreen : .systemRed
        permissionRow.addControl(permissionLabel)
        card.addRow(permissionRow)

        stackView.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // Request Permission Button if not granted
        if !hasPermission {
            let buttonView = NSView()
            buttonView.translatesAutoresizingMaskIntoConstraints = false

            let requestButton = NSButton(title: "Request Permission", target: self, action: #selector(requestPermission(_:)))
            requestButton.translatesAutoresizingMaskIntoConstraints = false
            requestButton.bezelStyle = .rounded
            buttonView.addSubview(requestButton)

            NSLayoutConstraint.activate([
                buttonView.heightAnchor.constraint(equalToConstant: 40),
                requestButton.centerYAnchor.constraint(equalTo: buttonView.centerYAnchor),
                requestButton.leadingAnchor.constraint(equalTo: buttonView.leadingAnchor)
            ])

            stackView.addArrangedSubview(buttonView)
            buttonView.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }
    }

    @objc private func requestPermission(_ sender: NSButton) {
        CGRequestScreenCaptureAccess()
    }
}
