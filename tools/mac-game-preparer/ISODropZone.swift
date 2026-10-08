import AppKit

final class ISODropZone: NSView {
    var onChoose: (() -> Void)?
    var onDrop: ((URL) -> Void)?
    var isEnabled = true { didSet { if !isEnabled { highlighted = false }; needsDisplay = true } }
    private var highlighted = false
    private let heading = NSTextField(labelWithString: "Drop your game here")
    private let detail = NSTextField(labelWithString: "ISO, RAR, ZIP, 7z or extracted folder · click to choose")
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityLabel("Drop your game here, ISO, RAR, ZIP, 7z or extracted folder · click to choose")
        setAccessibilityRole(.button)
        let symbol = NSImageView(image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "ISO import") ?? NSImage())
        symbol.contentTintColor = .systemTeal
        heading.font = .systemFont(ofSize: 19, weight: .semibold)
        heading.textColor = .systemTeal
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        let text = NSStackView(views: [heading, detail])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 6
        let content = NSStackView(views: [symbol, text])
        content.orientation = .horizontal; content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            symbol.widthAnchor.constraint(equalToConstant: 32),
            symbol.heightAnchor.constraint(equalToConstant: 36),
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14)
        NSColor.systemTeal.withAlphaComponent(isEnabled ? (highlighted ? 0.20 : 0.07) : 0.03).setFill()
        border.fill()
        NSColor.systemTeal.withAlphaComponent(isEnabled ? 0.85 : 0.25).setStroke()
        border.lineWidth = highlighted ? 2.5 : 1.5
        if !highlighted { border.setLineDash([7, 5], count: 2, phase: 0) }
        border.stroke()
    }
    static func acceptedISO(_ urls: [URL]) -> URL? {
        GameInput.selected(urls)
    }
    private func candidate(_ sender: NSDraggingInfo) -> URL? {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return Self.acceptedISO(urls)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlighted = isEnabled && candidate(sender) != nil
        needsDisplay = true
        return highlighted ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { isEnabled && candidate(sender) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false; needsDisplay = true
        guard isEnabled, let url = candidate(sender) else { return false }
        onDrop?(url)
        return true
    }
    override func mouseDown(with event: NSEvent) { if isEnabled { onChoose?() } }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }; onChoose?(); return true
    }
    func showSelected(_ selected: Bool) {
        heading.stringValue = selected ? "Game selected" : "Drop your game here"
        detail.stringValue = selected ? "Drop another game here or click to change it" : "ISO, RAR, ZIP, 7z or extracted folder · click to choose"
        setAccessibilityLabel(selected ? "Game selected. Drop another game or click to change it" : "Drop your game here, ISO, RAR, ZIP, 7z or extracted folder · click to choose")
    }
}
