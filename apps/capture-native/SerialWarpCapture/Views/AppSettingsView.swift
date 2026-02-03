import Cocoa

/// App settings view with global preferences
class AppSettingsView: NSView {

    private var appState = AppState.shared
    private var stackView: NSStackView!

    // Controls
    private var autoConnectSwitch: NSSwitch!
    private var previewEnabledSwitch: NSSwitch!
    private var previewQualitySlider: NSSlider!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        loadSettings()
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
        let header = HeaderView(title: "Settings")
        stackView.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // General Settings Card
        setupGeneralCard()

        // Preview Settings Card
        setupPreviewCard()
    }

    private func setupGeneralCard() {
        let card = SettingsCardView(title: "General")

        // Auto-connect row
        let autoConnectRow = SettingsRowView(label: "Auto-connect on launch")
        autoConnectSwitch = NSSwitch()
        autoConnectSwitch.translatesAutoresizingMaskIntoConstraints = false
        autoConnectSwitch.target = self
        autoConnectSwitch.action = #selector(autoConnectChanged(_:))
        autoConnectRow.addControl(autoConnectSwitch)
        card.addRow(autoConnectRow)

        stackView.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    private func setupPreviewCard() {
        let card = SettingsCardView(title: "Preview")

        // Enable preview row
        let enableRow = SettingsRowView(label: "Enable live preview")
        previewEnabledSwitch = NSSwitch()
        previewEnabledSwitch.translatesAutoresizingMaskIntoConstraints = false
        previewEnabledSwitch.target = self
        previewEnabledSwitch.action = #selector(previewEnabledChanged(_:))
        enableRow.addControl(previewEnabledSwitch)
        card.addRow(enableRow)

        // Quality row
        let qualityRow = SettingsRowView(label: "Preview quality")
        previewQualitySlider = NSSlider(value: 50, minValue: 10, maxValue: 100, target: self, action: #selector(previewQualityChanged(_:)))
        previewQualitySlider.translatesAutoresizingMaskIntoConstraints = false
        previewQualitySlider.controlSize = .small
        previewQualitySlider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        qualityRow.addControl(previewQualitySlider)
        card.addRow(qualityRow)

        stackView.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    private func loadSettings() {
        autoConnectSwitch.state = appState.settings.autoConnect ? .on : .off
        previewEnabledSwitch.state = appState.settings.previewEnabled ? .on : .off
        previewQualitySlider.integerValue = Int(appState.settings.previewQuality)
    }

    @objc private func autoConnectChanged(_ sender: NSSwitch) {
        appState.settings.autoConnect = sender.state == .on
        appState.saveCurrentSettings()
    }

    @objc private func previewEnabledChanged(_ sender: NSSwitch) {
        appState.settings.previewEnabled = sender.state == .on
        appState.saveCurrentSettings()
    }

    @objc private func previewQualityChanged(_ sender: NSSlider) {
        appState.settings.previewQuality = UInt32(sender.integerValue)
        appState.saveCurrentSettings()
    }
}
