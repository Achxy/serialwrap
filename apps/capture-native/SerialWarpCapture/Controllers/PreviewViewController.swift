import Cocoa
import Combine

/// View controller for the live video preview
class PreviewViewController: NSViewController {

    /// The preview image view
    private var previewImageView: NSImageView!

    /// Stats overlay
    private var statsLabel: NSTextField!

    /// Status overlay
    private var statusLabel: NSTextField!

    /// Background view
    private var backgroundView: NSView!

    /// Current preview frame
    private var currentFrame: CGImage? {
        didSet {
            updatePreview()
        }
    }

    /// Whether preview is enabled
    var previewEnabled: Bool = true {
        didSet {
            previewImageView.isHidden = !previewEnabled
            if !previewEnabled {
                previewImageView.image = nil
            }
        }
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        // Background view
        backgroundView = NSView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.black.cgColor
        view.addSubview(backgroundView)

        // Preview image view
        previewImageView = NSImageView()
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        previewImageView.wantsLayer = true
        view.addSubview(previewImageView)

        // Status label (centered)
        statusLabel = NSTextField(labelWithString: "No Preview")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        view.addSubview(statusLabel)

        // Stats label (bottom right overlay)
        statsLabel = NSTextField(labelWithString: "")
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        statsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statsLabel.textColor = .white
        statsLabel.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        statsLabel.isBezeled = false
        statsLabel.drawsBackground = true
        statsLabel.isEditable = false
        statsLabel.isSelectable = false
        statsLabel.isHidden = true
        view.addSubview(statsLabel)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            previewImageView.topAnchor.constraint(equalTo: view.topAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            statsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            statsLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
    }

    /// Update the preview with a new frame
    func updateFrame(_ frame: CGImage) {
        currentFrame = frame
    }

    /// Update stats display
    func updateStats(_ stats: PipelineStats) {
        let fpsText = String(format: "%.1f fps", stats.currentFps)
        let bitrateText = formatBitrate(stats.currentBitrateBps)
        let framesText = "Frames: \(stats.framesSent)"

        statsLabel.stringValue = " \(fpsText) | \(bitrateText) | \(framesText) "
        statsLabel.isHidden = false
    }

    /// Update status message
    func updateStatus(_ message: String, showPreview: Bool = false) {
        statusLabel.stringValue = message
        statusLabel.isHidden = showPreview
        previewImageView.isHidden = !showPreview
    }

    /// Clear the preview
    func clearPreview() {
        currentFrame = nil
        previewImageView.image = nil
        statsLabel.isHidden = true
        statusLabel.isHidden = false
        statusLabel.stringValue = "No Preview"
    }

    private func updatePreview() {
        guard let frame = currentFrame else {
            return
        }

        let image = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
        previewImageView.image = image
        statusLabel.isHidden = true
    }

    private func formatBitrate(_ bps: UInt64) -> String {
        let mbps = Double(bps) / 1_000_000
        return String(format: "%.1f Mbps", mbps)
    }
}
