import Cocoa

/// Main window controller that sets up the split view layout similar to BetterDisplay
class MainWindowController: NSWindowController, NSWindowDelegate {

    private var splitViewController: NSSplitViewController!
    private var sidebarViewController: SidebarViewController!
    private var mainContentViewController: ContentViewController!

    init() {
        // Create the main window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SerialWarp Capture"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 700, height: 500)
        window.center()

        // Enable toolbar to get the unified title bar look
        window.toolbarStyle = .unified

        super.init(window: window)

        window.delegate = self
        setupSplitView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSplitView() {
        splitViewController = NSSplitViewController()
        splitViewController.splitView.dividerStyle = .thin

        // Create sidebar
        sidebarViewController = SidebarViewController()
        sidebarViewController.delegate = self
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 280
        sidebarItem.canCollapse = true
        sidebarItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings

        // Create content area
        mainContentViewController = ContentViewController()
        let contentItem = NSSplitViewItem(viewController: mainContentViewController)
        contentItem.minimumThickness = 400

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(contentItem)

        window?.contentViewController = splitViewController

        // Configure initial sidebar selection
        sidebarViewController.selectItem(.displays)
    }

    func windowWillClose(_ notification: Notification) {
        // Clean up when window closes
    }
}

// MARK: - SidebarViewControllerDelegate
extension MainWindowController: SidebarViewControllerDelegate {
    func sidebarDidSelectItem(_ item: SidebarItem) {
        mainContentViewController.showContent(for: item)
    }
}
