import Cocoa
import Combine

/// Main content area view controller
class ContentViewController: NSViewController {

    private var scrollView: NSScrollView!
    private var contentStackView: NSStackView!
    private var currentItem: SidebarItem = .displays
    private var appState = AppState.shared
    private var cancellables = Set<AnyCancellable>()

    // Content views
    private var displaysView: DisplaysContentView!
    private var appSettingsView: AppSettingsView!
    private var aboutView: AboutView!

    override func loadView() {
        self.view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScrollView()
        setupContentViews()
        bindState()
    }

    private func setupScrollView() {
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        contentStackView = NSStackView()
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.orientation = .vertical
        contentStackView.alignment = .leading
        contentStackView.spacing = 20

        scrollView.documentView = contentStackView

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor, constant: -40)
        ])
    }

    private func setupContentViews() {
        displaysView = DisplaysContentView()
        appSettingsView = AppSettingsView()
        aboutView = AboutView()
    }

    private func bindState() {
        // Observe state changes using Combine
        appState.$connectionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateViews()
            }
            .store(in: &cancellables)

        appState.$isStreaming
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateViews()
            }
            .store(in: &cancellables)
    }

    private func updateViews() {
        displaysView.updateState()
    }

    func showContent(for item: SidebarItem) {
        currentItem = item

        // Remove all current views
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch item {
        case .displays:
            contentStackView.addArrangedSubview(displaysView)
            displaysView.widthAnchor.constraint(equalTo: contentStackView.widthAnchor).isActive = true
        case .app:
            contentStackView.addArrangedSubview(appSettingsView)
            appSettingsView.widthAnchor.constraint(equalTo: contentStackView.widthAnchor).isActive = true
        case .about:
            contentStackView.addArrangedSubview(aboutView)
            aboutView.widthAnchor.constraint(equalTo: contentStackView.widthAnchor).isActive = true
        }
    }
}
