import Cocoa

/// Sidebar navigation items
enum SidebarItem: Int, CaseIterable {
    case displays
    case app
    case about

    var title: String {
        switch self {
        case .displays: return "Displays"
        case .app: return "App"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .displays: return "display.2"
        case .app: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

protocol SidebarViewControllerDelegate: AnyObject {
    func sidebarDidSelectItem(_ item: SidebarItem)
}

/// Sidebar view controller with BetterDisplay-style navigation
class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    weak var delegate: SidebarViewControllerDelegate?

    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var visualEffectView: NSVisualEffectView!
    private var selectedItem: SidebarItem = .displays

    override func loadView() {
        // Create visual effect view for sidebar translucency
        visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active

        self.view = visualEffectView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
    }

    private func setupTableView() {
        // Create scroll view
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // Create table view
        tableView = NSTableView()
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.rowHeight = 32
        tableView.style = .sourceList
        tableView.selectionHighlightStyle = .sourceList
        tableView.dataSource = self
        tableView.delegate = self

        // Add column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        column.width = 220
        tableView.addTableColumn(column)

        scrollView.documentView = tableView

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 50),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func selectItem(_ item: SidebarItem) {
        selectedItem = item
        tableView.selectRowIndexes(IndexSet(integer: item.rawValue), byExtendingSelection: false)
        delegate?.sidebarDidSelectItem(item)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return SidebarItem.allCases.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = SidebarItem.allCases[row]

        let cellIdentifier = NSUserInterfaceItemIdentifier("SidebarCell")
        var cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? SidebarCellView

        if cellView == nil {
            cellView = SidebarCellView()
            cellView?.identifier = cellIdentifier
        }

        cellView?.configure(with: item)
        return cellView
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard tableView.selectedRow >= 0 else { return }
        let item = SidebarItem.allCases[tableView.selectedRow]
        selectedItem = item
        delegate?.sidebarDidSelectItem(item)
    }
}

/// Custom cell view for sidebar items
class SidebarCellView: NSTableCellView {

    private var iconImageView: NSImageView!
    private var titleLabel: NSTextField!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconImageView = NSImageView()
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.contentTintColor = .secondaryLabelColor
        addSubview(iconImageView)

        titleLabel = NSTextField(labelWithString: "")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 18),
            iconImageView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(with item: SidebarItem) {
        titleLabel.stringValue = item.title
        if #available(macOS 11.0, *) {
            iconImageView.image = NSImage(systemSymbolName: item.icon, accessibilityDescription: item.title)
        } else {
            // Fallback for older macOS versions
            iconImageView.image = nil
        }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            switch backgroundStyle {
            case .emphasized:
                titleLabel.textColor = .white
                iconImageView.contentTintColor = .white
            default:
                titleLabel.textColor = .labelColor
                iconImageView.contentTintColor = .secondaryLabelColor
            }
        }
    }
}
