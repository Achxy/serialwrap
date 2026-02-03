import Cocoa
import Combine

/// Main displays content view with BetterDisplay-style cards
class DisplaysContentView: NSView {

    private var appState = AppState.shared
    private var cancellables = Set<AnyCancellable>()

    // UI Components
    private var stackView: NSStackView!
    private var headerView: HeaderView!
    private var virtualDisplayCard: SettingsCardView!
    private var streamSettingsCard: SettingsCardView!
    private var previewCard: SettingsCardView!
    private var statsCard: SettingsCardView!

    // Controls
    private var createDisplayButton: NSButton!
    private var startStreamButton: NSButton!
    private var resolutionPopup: NSPopUpButton!
    private var fpsPopup: NSPopUpButton!
    private var bitratePopup: NSPopUpButton!
    private var hidpiSwitch: NSSwitch!
    private var previewImageView: NSImageView!
    private var statusIndicator: StatusIndicatorView!

    // Stats labels
    private var fpsLabel: NSTextField!
    private var bitrateLabel: NSTextField!
    private var framesLabel: NSTextField!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        bindState()
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

        // Header with status indicator
        setupHeader()

        // Virtual Display Card
        setupVirtualDisplayCard()

        // Stream Settings Card
        setupStreamSettingsCard()

        // Preview Card
        setupPreviewCard()

        // Stats Card
        setupStatsCard()
    }

    private func setupHeader() {
        headerView = HeaderView(title: "Virtual Display")
        stackView.addArrangedSubview(headerView)
        headerView.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    private func setupVirtualDisplayCard() {
        virtualDisplayCard = SettingsCardView(title: "Virtual Display")

        // Resolution row
        let resolutionRow = SettingsRowView(label: "Resolution")
        resolutionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        resolutionPopup.translatesAutoresizingMaskIntoConstraints = false
        for (name, _, _) in StreamConfig.resolutions {
            resolutionPopup.addItem(withTitle: name)
        }
        resolutionPopup.target = self
        resolutionPopup.action = #selector(resolutionChanged(_:))
        resolutionRow.addControl(resolutionPopup)
        virtualDisplayCard.addRow(resolutionRow)

        // FPS row
        let fpsRow = SettingsRowView(label: "Frame Rate")
        fpsPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        fpsPopup.translatesAutoresizingMaskIntoConstraints = false
        for fps in StreamConfig.frameRates {
            fpsPopup.addItem(withTitle: "\(fps) fps")
        }
        fpsPopup.selectItem(at: 1) // 60fps default
        fpsPopup.target = self
        fpsPopup.action = #selector(fpsChanged(_:))
        fpsRow.addControl(fpsPopup)
        virtualDisplayCard.addRow(fpsRow)

        // HiDPI row
        let hidpiRow = SettingsRowView(label: "HiDPI (Retina)")
        hidpiSwitch = NSSwitch()
        hidpiSwitch.translatesAutoresizingMaskIntoConstraints = false
        hidpiSwitch.target = self
        hidpiSwitch.action = #selector(hidpiChanged(_:))
        hidpiRow.addControl(hidpiSwitch)
        virtualDisplayCard.addRow(hidpiRow)

        // Create button row
        let buttonRow = NSView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        createDisplayButton = NSButton(title: "Create Virtual Display", target: self, action: #selector(createDisplayTapped(_:)))
        createDisplayButton.translatesAutoresizingMaskIntoConstraints = false
        createDisplayButton.bezelStyle = .rounded
        createDisplayButton.controlSize = .large
        buttonRow.addSubview(createDisplayButton)

        NSLayoutConstraint.activate([
            buttonRow.heightAnchor.constraint(equalToConstant: 40),
            createDisplayButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            createDisplayButton.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor)
        ])

        virtualDisplayCard.addCustomView(buttonRow)

        stackView.addArrangedSubview(virtualDisplayCard)
        virtualDisplayCard.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    private func setupStreamSettingsCard() {
        streamSettingsCard = SettingsCardView(title: "Streaming")

        // Bitrate row
        let bitrateRow = SettingsRowView(label: "Bitrate")
        bitratePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        bitratePopup.translatesAutoresizingMaskIntoConstraints = false
        for bitrate in StreamConfig.bitrates {
            bitratePopup.addItem(withTitle: "\(bitrate) Mbps")
        }
        bitratePopup.selectItem(at: 3) // 20 Mbps default
        bitratePopup.target = self
        bitratePopup.action = #selector(bitrateChanged(_:))
        bitrateRow.addControl(bitratePopup)
        streamSettingsCard.addRow(bitrateRow)

        // Status row
        let statusRow = SettingsRowView(label: "Status")
        statusIndicator = StatusIndicatorView()
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false
        statusRow.addControl(statusIndicator)
        streamSettingsCard.addRow(statusRow)

        // Start button row
        let buttonRow = NSView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        startStreamButton = NSButton(title: "Start Streaming", target: self, action: #selector(startStreamTapped(_:)))
        startStreamButton.translatesAutoresizingMaskIntoConstraints = false
        startStreamButton.bezelStyle = .rounded
        startStreamButton.controlSize = .large
        startStreamButton.isEnabled = false
        buttonRow.addSubview(startStreamButton)

        NSLayoutConstraint.activate([
            buttonRow.heightAnchor.constraint(equalToConstant: 40),
            startStreamButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            startStreamButton.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor)
        ])

        streamSettingsCard.addCustomView(buttonRow)

        stackView.addArrangedSubview(streamSettingsCard)
        streamSettingsCard.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    private func setupPreviewCard() {
        previewCard = SettingsCardView(title: "Preview")

        previewImageView = NSImageView()
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.backgroundColor = NSColor.black.cgColor
        previewImageView.layer?.cornerRadius = 8

        NSLayoutConstraint.activate([
            previewImageView.heightAnchor.constraint(equalToConstant: 200)
        ])

        previewCard.addCustomView(previewImageView)

        stackView.addArrangedSubview(previewCard)
        previewCard.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    private func setupStatsCard() {
        statsCard = SettingsCardView(title: "Statistics")

        // FPS row
        let fpsRow = SettingsRowView(label: "FPS")
        fpsLabel = NSTextField(labelWithString: "0.0")
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false
        fpsLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        fpsRow.addControl(fpsLabel)
        statsCard.addRow(fpsRow)

        // Bitrate row
        let bitrateStatRow = SettingsRowView(label: "Bitrate")
        bitrateLabel = NSTextField(labelWithString: "0 Mbps")
        bitrateLabel.translatesAutoresizingMaskIntoConstraints = false
        bitrateLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        bitrateStatRow.addControl(bitrateLabel)
        statsCard.addRow(bitrateStatRow)

        // Frames row
        let framesRow = SettingsRowView(label: "Frames")
        framesLabel = NSTextField(labelWithString: "0 captured / 0 encoded / 0 dropped")
        framesLabel.translatesAutoresizingMaskIntoConstraints = false
        framesLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        framesLabel.textColor = .secondaryLabelColor
        framesRow.addControl(framesLabel)
        statsCard.addRow(framesRow)

        stackView.addArrangedSubview(statsCard)
        statsCard.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    private func bindState() {
        appState.$virtualDisplayId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)

        appState.$isStreaming
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)

        appState.$streamStats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.updateStats(stats)
            }
            .store(in: &cancellables)

        appState.$previewFrame
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                if let frame = frame {
                    self?.previewImageView.image = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
                }
            }
            .store(in: &cancellables)
    }

    func updateState() {
        let hasDisplay = appState.virtualDisplayId != nil
        let isStreaming = appState.isStreaming

        // Update buttons
        createDisplayButton.title = hasDisplay ? "Destroy Virtual Display" : "Create Virtual Display"
        startStreamButton.isEnabled = hasDisplay
        startStreamButton.title = isStreaming ? "Stop Streaming" : "Start Streaming"

        // Update status indicator
        if isStreaming {
            statusIndicator.setStatus(.streaming, text: "Streaming")
        } else if hasDisplay {
            statusIndicator.setStatus(.ready, text: "Ready")
        } else {
            statusIndicator.setStatus(.idle, text: "No display")
        }

        // Disable settings while streaming
        resolutionPopup.isEnabled = !isStreaming && !hasDisplay
        fpsPopup.isEnabled = !isStreaming && !hasDisplay
        hidpiSwitch.isEnabled = !isStreaming && !hasDisplay
        bitratePopup.isEnabled = !isStreaming
    }

    private func updateStats(_ stats: StreamStats) {
        fpsLabel.stringValue = String(format: "%.1f", stats.fps)
        bitrateLabel.stringValue = "\(stats.bitrateBps / 1_000_000) Mbps"
        framesLabel.stringValue = "\(stats.framesCaptured) captured / \(stats.framesEncoded) encoded / \(stats.framesDropped) dropped"
    }

    // MARK: - Actions

    @objc private func resolutionChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0 && index < StreamConfig.resolutions.count else { return }
        let (_, width, height) = StreamConfig.resolutions[index]
        appState.streamConfig.width = width
        appState.streamConfig.height = height
    }

    @objc private func fpsChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0 && index < StreamConfig.frameRates.count else { return }
        appState.streamConfig.fps = StreamConfig.frameRates[index]
    }

    @objc private func bitrateChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0 && index < StreamConfig.bitrates.count else { return }
        appState.streamConfig.bitrateMbps = StreamConfig.bitrates[index]
    }

    @objc private func hidpiChanged(_ sender: NSSwitch) {
        appState.streamConfig.hidpi = sender.state == .on
    }

    @objc private func createDisplayTapped(_ sender: NSButton) {
        if appState.virtualDisplayId != nil {
            // Destroy display
            StreamingService.shared.destroyVirtualDisplay()
        } else {
            // Create display
            do {
                let _ = try StreamingService.shared.createVirtualDisplay(config: appState.streamConfig)
            } catch {
                showError(error)
            }
        }
    }

    @objc private func startStreamTapped(_ sender: NSButton) {
        if appState.isStreaming {
            StreamingService.shared.stopStreaming()
        } else {
            Task {
                do {
                    try await StreamingService.shared.startStreaming(config: appState.streamConfig)
                } catch {
                    await MainActor.run {
                        showError(error)
                    }
                }
            }
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Header View

class HeaderView: NSView {
    private var titleLabel: NSTextField!

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Status Indicator View

enum StatusState {
    case idle
    case ready
    case streaming
    case error
}

class StatusIndicatorView: NSView {
    private var dotView: NSView!
    private var statusLabel: NSTextField!
    private var pulseAnimation: CABasicAnimation?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        dotView = NSView()
        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 5
        dotView.layer?.backgroundColor = NSColor.systemGray.cgColor
        addSubview(dotView)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 10),
            dotView.heightAnchor.constraint(equalToConstant: 10),

            statusLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 6),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    func setStatus(_ status: StatusState, text: String) {
        statusLabel.stringValue = text

        // Remove existing animation
        dotView.layer?.removeAllAnimations()

        switch status {
        case .idle:
            dotView.layer?.backgroundColor = NSColor.systemGray.cgColor
        case .ready:
            dotView.layer?.backgroundColor = NSColor.systemGreen.cgColor
        case .streaming:
            dotView.layer?.backgroundColor = NSColor.systemGreen.cgColor
            addPulseAnimation()
        case .error:
            dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        }
    }

    private func addPulseAnimation() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        dotView.layer?.add(pulse, forKey: "pulse")
    }
}
