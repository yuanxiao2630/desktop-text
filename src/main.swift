import AppKit
import ServiceManagement

// MARK: - Local document

struct SavedColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .white
        red = c.redComponent; green = c.greenComponent
        blue = c.blueComponent; alpha = c.alphaComponent
    }

    var color: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

struct DesktopNote: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var title = "我的桌面文字"
    var text = "理性干不过惯性"
    var fontFamily = "PingFang SC"
    var fontSize: Double = 36
    var bold = true
    var italic = false
    var underline = false
    var shadow = true
    var foreground = SavedColor(.white)
    var hasBackground = false
    var background = SavedColor(NSColor(srgbRed: 1, green: 0.97, blue: 0.86, alpha: 0.95))
    var opacity: Double = 1
    var alignment = 0
    var lineSpacing: Double = 5
    var x: Double = 80
    var y: Double = 120
    var width: Double = 520
    var height: Double = 210
    var locked = false
    var onTop = false
    var visible = true

    var frame: NSRect {
        get { NSRect(x: x, y: y, width: width, height: height) }
        set { x = newValue.minX; y = newValue.minY; width = newValue.width; height = newValue.height }
    }

    var font: NSFont {
        let base = NSFont(name: fontFamily, size: fontSize)
            ?? NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: 5, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        return traits.isEmpty ? base : NSFontManager.shared.convert(base, toHaveTrait: traits)
    }

    var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = [NSTextAlignment.left, .center, .right][min(max(alignment, 0), 2)]
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        var result: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: foreground.color, .paragraphStyle: paragraph,
            .underlineStyle: underline ? NSUnderlineStyle.single.rawValue : 0
        ]
        if shadow {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.62)
            s.shadowBlurRadius = 4
            s.shadowOffset = NSSize(width: 0, height: -1)
            result[.shadow] = s
        }
        return result
    }

    func sameStyle(as other: DesktopNote) -> Bool {
        fontFamily == other.fontFamily && fontSize == other.fontSize &&
        bold == other.bold && italic == other.italic && underline == other.underline &&
        shadow == other.shadow && foreground == other.foreground &&
        alignment == other.alignment && lineSpacing == other.lineSpacing
    }
}

struct LocalDocument: Codable {
    var version = 1
    var notes: [DesktopNote] = []
    var trash: [DesktopNote] = []
}

final class NoteStore {
    let directory: URL
    var document: LocalDocument
    var pendingSave: DispatchWorkItem?
    var onSave: ((String) -> Void)?
    var loadMessage: String?
    var fileURL: URL { directory.appendingPathComponent("notes.json") }

    init(directory: URL) {
        self.directory = directory
        let url = directory.appendingPathComponent("notes.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                document = try JSONDecoder().decode(LocalDocument.self, from: Data(contentsOf: url))
            } catch {
                document = LocalDocument()
                let backup = directory.appendingPathComponent("notes-recovery-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: url, to: backup)
                loadMessage = "旧数据未能读取，已保留恢复副本。"
            }
        } else {
            document = LocalDocument()
            var note = DesktopNote()
            if let screen = NSScreen.main?.visibleFrame {
                note.frame = NSRect(x: screen.maxX - 580, y: screen.maxY - 290, width: 520, height: 210)
            }
            document.notes = [note]
        }
        for index in document.notes.indices {
            sanitize(&document.notes[index])
        }
    }

    private func sanitize(_ note: inout DesktopNote) {
        note.fontSize = note.fontSize.isFinite ? min(max(note.fontSize, 8), 240) : 36
        note.opacity = note.opacity.isFinite ? min(max(note.opacity, 0.2), 1) : 1
        note.width = note.width.isFinite ? min(max(note.width, 180), 2000) : 520
        note.height = note.height.isFinite ? min(max(note.height, 110), 2000) : 210
        note.lineSpacing = note.lineSpacing.isFinite ? min(max(note.lineSpacing, 0), 40) : 5
        if !note.x.isFinite { note.x = 80 }
        if !note.y.isFinite { note.y = 120 }
    }

    func scheduleSave() {
        pendingSave?.cancel()
        onSave?("正在保存…")
        let item = DispatchWorkItem { [weak self] in self?.flush() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    @discardableResult func flush() -> Bool {
        pendingSave?.cancel()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: fileURL, options: .atomic)
            onSave?("已自动保存 · 仅存储在本机")
            return true
        } catch {
            onSave?("保存失败：\(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Desktop text windows

final class NoteWindow: NSWindow {
    var isLocked = false
    override var canBecomeKey: Bool { !isLocked }
    override var canBecomeMain: Bool { false }
}

final class NoteTextView: NSTextView {
    var onLock: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onLock?() }
        else { super.keyDown(with: event) }
    }
}

final class DragHeader: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class ResizeGrip: NSView {
    var onEnd: (() -> Void)?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.setStroke()
        for offset in [CGFloat(4), CGFloat(9)] {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.maxX - offset - 6, y: 4))
            path.line(to: NSPoint(x: bounds.maxX - 4, y: offset + 6))
            path.lineWidth = 1.5
            path.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let origin = NSEvent.mouseLocation
        let start = window.frame
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let current = NSEvent.mouseLocation
            let width = min(max(start.width + current.x - origin.x, 180), 2000)
            let height = min(max(start.height - current.y + origin.y, 110), 2000)
            window.setFrame(NSRect(x: start.minX, y: start.maxY - height, width: width, height: height), display: true)
        }
        onEnd?()
    }
}

final class NoteOverlay: NSObject, NSWindowDelegate, NSTextViewDelegate {
    let id: String
    unowned let app: AppDelegate
    let window: NoteWindow
    let body = NSView()
    let header = DragHeader()
    let title = NSTextField(labelWithString: "")
    let scroll = NSScrollView()
    let textView = NoteTextView()
    let grip = ResizeGrip()
    var lastNote: DesktopNote?
    var applyingFrame = false

    init(note: DesktopNote, app: AppDelegate) {
        self.id = note.id
        self.app = app
        window = NoteWindow(contentRect: note.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = "桌面文字 · \(note.title)"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
        window.delegate = self
        window.minSize = NSSize(width: 180, height: 110)
        let root = NSView()
        root.wantsLayer = true
        window.contentView = root

        body.wantsLayer = true
        body.layer?.cornerRadius = 14
        body.layer?.masksToBounds = true
        root.addSubview(body)
        header.material = .hudWindow
        header.blendingMode = .behindWindow
        header.state = .active
        header.wantsLayer = true
        header.layer?.cornerRadius = 9
        header.layer?.masksToBounds = true
        root.addSubview(header)
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.textColor = .secondaryLabelColor
        header.addSubview(title)
        let edit = NSButton(image: NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "字体与样式")!, target: self, action: #selector(openEditor))
        edit.bezelStyle = .inline
        edit.toolTip = "打开字体与样式设置"
        header.addSubview(edit)
        let lock = NSButton(image: NSImage(systemSymbolName: "lock", accessibilityDescription: "锁定文字")!, target: self, action: #selector(lockNote))
        lock.bezelStyle = .inline
        lock.toolTip = "锁定位置并开启鼠标穿透，也可按 Esc"
        header.addSubview(lock)

        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.allowsUndo = true
        textView.delegate = self
        textView.setAccessibilityLabel("桌面文字内容")
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.onLock = { [weak self] in self?.lockNote() }
        scroll.documentView = textView
        body.addSubview(scroll)
        body.addSubview(grip)
        grip.setAccessibilityLabel("拖动调整文字框大小")
        grip.onEnd = { [weak self] in self?.rememberFrame() }

        [body, header, title, edit, lock, scroll, grip].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            body.topAnchor.constraint(equalTo: root.topAnchor, constant: 34),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 29),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: edit.leadingAnchor, constant: -6),
            lock.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -7),
            lock.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            lock.widthAnchor.constraint(equalToConstant: 25),
            edit.trailingAnchor.constraint(equalTo: lock.leadingAnchor, constant: -7),
            edit.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            edit.widthAnchor.constraint(equalToConstant: 25),
            scroll.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: body.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            grip.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            grip.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            grip.widthAnchor.constraint(equalToConstant: 25),
            grip.heightAnchor.constraint(equalToConstant: 25)
        ])
        update(note)
    }

    func update(_ note: DesktopNote) {
        window.title = "桌面文字 · \(note.title)"
        title.stringValue = "\(note.title)  ·  拖动此处定位"
        let contentChanged = textView.string != note.text
        if contentChanged && !textView.hasMarkedText() {
            let selection = textView.selectedRange()
            textView.string = note.text
            textView.setSelectedRange(NSRange(location: min(selection.location, (note.text as NSString).length), length: 0))
        }
        if lastNote == nil || !note.sameStyle(as: lastNote!) || contentChanged {
            if !textView.hasMarkedText() {
                textView.textStorage?.setAttributes(note.attributes, range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
                textView.typingAttributes = note.attributes
            }
        }
        textView.insertionPointColor = note.foreground.color
        textView.isEditable = !note.locked
        textView.isSelectable = !note.locked
        scroll.hasVerticalScroller = !note.locked
        header.isHidden = note.locked
        grip.isHidden = note.locked
        body.layer?.borderWidth = note.locked ? 0 : 1
        body.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.65).cgColor
        body.layer?.backgroundColor = note.hasBackground ? note.background.color.cgColor : NSColor.clear.cgColor
        body.alphaValue = note.opacity

        if window.isKeyWindow && note.locked { window.resignKey() }
        window.isLocked = note.locked
        let desiredLevel: NSWindow.Level = note.locked
            ? (note.onTop ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1))
            : .normal
        if window.level != desiredLevel { window.level = desiredLevel }
        let desiredBehavior: NSWindow.CollectionBehavior = note.onTop
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            : [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if window.collectionBehavior != desiredBehavior { window.collectionBehavior = desiredBehavior }
        if window.frame != note.frame {
            applyingFrame = true
            window.setFrame(note.frame, display: true)
            applyingFrame = false
        }
        if note.visible && !app.hideAll {
            if !window.isVisible { window.orderFrontRegardless() }
        } else {
            window.orderOut(nil)
        }
        window.ignoresMouseEvents = note.locked
        lastNote = note
    }

    @objc func openEditor() { app.showManager(select: id) }
    @objc func lockNote() { app.change(id) { $0.locked = true } }

    func textDidChange(_ notification: Notification) {
        guard !textView.hasMarkedText() else { return }
        let text = textView.string
        app.change(id) { $0.text = text }
    }

    func windowDidMove(_ notification: Notification) { rememberFrame() }
    func windowDidResize(_ notification: Notification) { rememberFrame() }
    func rememberFrame() {
        guard !applyingFrame, let note = app.note(id), !note.locked else { return }
        let frame = window.frame
        if note.frame != frame { app.change(id) { $0.frame = frame } }
    }
}

// MARK: - Editing window

func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let value = NSTextField(labelWithString: text)
    value.font = .systemFont(ofSize: size, weight: weight)
    value.textColor = color
    value.lineBreakMode = .byWordWrapping
    return value
}

func stack(_ views: [NSView], vertical: Bool = false, spacing: CGFloat = 10) -> NSStackView {
    let result = NSStackView(views: views)
    result.orientation = vertical ? .vertical : .horizontal
    result.alignment = vertical ? .leading : .centerY
    result.spacing = spacing
    return result
}

final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class ManagerController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSTextFieldDelegate, NSComboBoxDelegate {
    unowned let app: AppDelegate
    let table = NSTableView()
    let titleField = NSTextField()
    let bodyEditor = NSTextView()
    let fontBox = NSComboBox()
    let sizeSlider = NSSlider(value: 36, minValue: 8, maxValue: 120, target: nil, action: nil)
    let sizeField = NSTextField(string: "36")
    let boldButton = NSButton(checkboxWithTitle: "粗体", target: nil, action: nil)
    let italicButton = NSButton(checkboxWithTitle: "斜体", target: nil, action: nil)
    let underlineButton = NSButton(checkboxWithTitle: "下划线", target: nil, action: nil)
    let shadowButton = NSButton(checkboxWithTitle: "文字阴影", target: nil, action: nil)
    let foreground = NSColorWell()
    let background = NSColorWell()
    let backgroundChoice = NSSegmentedControl(labels: ["纯文字", "便签底色"], trackingMode: .selectOne, target: nil, action: nil)
    let alignment = NSSegmentedControl(labels: ["左对齐", "居中", "右对齐"], trackingMode: .selectOne, target: nil, action: nil)
    let spacingSlider = NSSlider(value: 5, minValue: 0, maxValue: 30, target: nil, action: nil)
    let spacingValue = label("5")
    let opacitySlider = NSSlider(value: 1, minValue: 0.2, maxValue: 1, target: nil, action: nil)
    let opacityValue = label("100%")
    let mode = NSSegmentedControl(labels: ["贴在桌面", "始终置顶"], trackingMode: .selectOne, target: nil, action: nil)
    let visibleButton = NSButton(checkboxWithTitle: "显示这段文字", target: nil, action: nil)
    let lockButton = NSButton()
    let statusLabel = label("已自动保存 · 仅存储在本机", size: 11, color: .secondaryLabelColor)
    let lockHint = label("", size: 12, color: .secondaryLabelColor)
    let countLabel = label("", size: 11, color: .secondaryLabelColor)
    var selectedID: String?
    var renderedID: String?
    var updating = false
    var editControls: [NSControl] = []

    init(app: AppDelegate) {
        self.app = app
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
        let frame = NSRect(x: 0, y: 0, width: min(1060, screen.width - 60), height: min(810, screen.height - 60))
        let w = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "桌面文字"
        w.minSize = NSSize(width: 850, height: 600)
        w.isReleasedWhenClosed = false
        w.center()
        super.init(window: w)
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func build() {
        guard let window, let root = window.contentView else { return }
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        let divider = NSBox()
        divider.boxType = .separator
        let detail = NSView()
        [sidebar, divider, detail].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 205),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            detail.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            detail.topAnchor.constraint(equalTo: root.topAnchor),
            detail.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        let brand = label("桌面文字", size: 23, weight: .semibold)
        let tagline = label("把重要的事，留在眼前。", size: 11, color: .secondaryLabelColor)
        let newButton = NSButton(title: "＋ 新增文字", target: app, action: #selector(AppDelegate.addNote))
        newButton.bezelStyle = .rounded
        newButton.controlSize = .large
        let listScroll = NSScrollView()
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note")))
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 57
        table.intercellSpacing = NSSize(width: 0, height: 5)
        table.style = .sourceList
        table.delegate = self
        table.dataSource = self
        table.setAccessibilityLabel("桌面文字列表")
        listScroll.documentView = table
        let lockAll = NSButton(title: "锁定全部文字", target: app, action: #selector(AppDelegate.lockAll))
        lockAll.bezelStyle = .rounded
        let help = NSButton(title: "使用说明", target: app, action: #selector(AppDelegate.showHelp))
        help.bezelStyle = .inline
        let sideStack = stack([brand, tagline, newButton, countLabel, listScroll, lockAll, help], vertical: true, spacing: 13)
        sideStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sideStack)
        NSLayoutConstraint.activate([
            sideStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            sideStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),
            sideStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 25),
            sideStack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -18),
            listScroll.widthAnchor.constraint(equalTo: sideStack.widthAnchor),
            listScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
            newButton.widthAnchor.constraint(equalTo: sideStack.widthAnchor),
            lockAll.widthAnchor.constraint(equalTo: sideStack.widthAnchor)
        ])
        listScroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let heading = label("编辑桌面文字", size: 23, weight: .semibold)
        let subtitle = label("解锁后可直接在桌面输入；锁定后固定位置，鼠标点击穿透。", size: 12, color: .secondaryLabelColor)
        lockButton.target = self
        lockButton.action = #selector(toggleLock)
        lockButton.bezelStyle = .rounded
        lockButton.controlSize = .large
        let headingColumn = stack([heading, subtitle], vertical: true, spacing: 6)
        let spacer = NSView()
        let headingRow = stack([headingColumn, spacer, lockButton])
        headingColumn.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headingRow.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(headingRow)

        let scroller = NSScrollView()
        scroller.hasVerticalScroller = true
        scroller.autohidesScrollers = true
        scroller.drawsBackground = false
        scroller.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(scroller)
        let content = FlippedDocumentView()
        content.translatesAutoresizingMaskIntoConstraints = false
        scroller.documentView = content
        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 16
        form.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(form)
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalTo: scroller.contentView.widthAnchor),
            form.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            form.topAnchor.constraint(equalTo: content.topAnchor, constant: 3),
            form.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        ])

        titleField.placeholderString = "给这段文字起个名字"
        titleField.delegate = self
        titleField.setAccessibilityLabel("文字名称")
        titleField.font = .systemFont(ofSize: 14)
        let titleSection = stack([label("文字名称", size: 12, weight: .semibold), titleField], vertical: true, spacing: 7)
        titleField.widthAnchor.constraint(equalTo: titleSection.widthAnchor).isActive = true
        addFullWidth(titleSection, to: form)

        let editorScroll = NSScrollView()
        editorScroll.borderType = .bezelBorder
        editorScroll.hasVerticalScroller = true
        editorScroll.autohidesScrollers = true
        bodyEditor.isRichText = false
        bodyEditor.font = .systemFont(ofSize: 15)
        bodyEditor.textColor = .labelColor
        bodyEditor.backgroundColor = .textBackgroundColor
        bodyEditor.textContainerInset = NSSize(width: 12, height: 12)
        bodyEditor.isVerticallyResizable = true
        bodyEditor.isHorizontallyResizable = false
        bodyEditor.autoresizingMask = [.width]
        bodyEditor.textContainer?.widthTracksTextView = true
        bodyEditor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        bodyEditor.allowsUndo = true
        bodyEditor.delegate = self
        bodyEditor.setAccessibilityLabel("编辑文字内容")
        editorScroll.documentView = bodyEditor
        editorScroll.heightAnchor.constraint(equalToConstant: 112).isActive = true
        let textSection = stack([label("文字内容", size: 12, weight: .semibold), editorScroll], vertical: true, spacing: 7)
        editorScroll.widthAnchor.constraint(equalTo: textSection.widthAnchor).isActive = true
        addFullWidth(textSection, to: form)

        fontBox.addItems(withObjectValues: NSFontManager.shared.availableFontFamilies.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        fontBox.numberOfVisibleItems = 14
        fontBox.completes = true
        fontBox.isEditable = true
        fontBox.delegate = self
        fontBox.target = self
        fontBox.action = #selector(fontChanged)
        fontBox.setAccessibilityLabel("字体")
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        sizeSlider.setAccessibilityLabel("字号滑块")
        sizeField.delegate = self
        sizeField.alignment = .center
        sizeField.setAccessibilityLabel("字号")
        sizeField.widthAnchor.constraint(equalToConstant: 52).isActive = true
        sizeSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        let fontColumn = stack([label("字体", size: 12, weight: .semibold), fontBox], vertical: true, spacing: 7)
        fontBox.widthAnchor.constraint(equalTo: fontColumn.widthAnchor).isActive = true
        let sizeColumn = stack([label("字号", size: 12, weight: .semibold), stack([sizeSlider, sizeField, label("pt", size: 11, color: .secondaryLabelColor)])], vertical: true, spacing: 7)
        let fontRow = stack([fontColumn, sizeColumn], spacing: 24)
        fontColumn.widthAnchor.constraint(equalTo: fontRow.widthAnchor, multiplier: 0.43).isActive = true
        addFullWidth(fontRow, to: form)

        [boldButton, italicButton, underlineButton, shadowButton].forEach {
            $0.target = self; $0.action = #selector(styleChanged)
        }
        addFullWidth(stack([boldButton, italicButton, underlineButton, shadowButton], spacing: 22), to: form)
        foreground.target = self
        foreground.action = #selector(colorChanged)
        foreground.setAccessibilityLabel("文字颜色")
        background.target = self
        background.action = #selector(colorChanged)
        background.setAccessibilityLabel("便签底色")
        [foreground, background].forEach { $0.widthAnchor.constraint(equalToConstant: 47).isActive = true; $0.heightAnchor.constraint(equalToConstant: 26).isActive = true }
        backgroundChoice.target = self
        backgroundChoice.action = #selector(backgroundChanged)
        let colorRow = stack([label("文字颜色", size: 12), foreground, NSView(), backgroundChoice, background], spacing: 12)
        addFullWidth(colorRow, to: form)

        alignment.target = self
        alignment.action = #selector(alignmentChanged)
        spacingSlider.target = self
        spacingSlider.action = #selector(lineSpacingChanged)
        spacingSlider.setAccessibilityLabel("行距")
        spacingValue.widthAnchor.constraint(equalToConstant: 24).isActive = true
        let paragraphRow = stack([alignment, NSView(), label("行距", size: 12), spacingSlider, spacingValue], spacing: 12)
        spacingSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        addFullWidth(paragraphRow, to: form)

        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        opacitySlider.setAccessibilityLabel("文字透明度")
        opacityValue.widthAnchor.constraint(equalToConstant: 45).isActive = true
        let opacityRow = stack([label("不透明度", size: 12), opacitySlider, opacityValue], spacing: 14)
        addFullWidth(opacityRow, to: form)
        let separator = NSBox()
        separator.boxType = .separator
        addFullWidth(separator, to: form)

        mode.target = self
        mode.action = #selector(modeChanged)
        visibleButton.target = self
        visibleButton.action = #selector(visibilityChanged)
        addFullWidth(stack([label("显示方式", size: 12, weight: .semibold), mode, NSView(), visibleButton], spacing: 13), to: form)
        addFullWidth(label("贴在桌面：其他窗口可盖住文字。始终置顶：文字显示在普通窗口上方。", size: 11, color: .secondaryLabelColor), to: form)
        let locate = NSButton(title: "移到当前屏幕", target: self, action: #selector(centerNote))
        locate.bezelStyle = .rounded
        let duplicate = NSButton(title: "复制这段文字", target: self, action: #selector(duplicateNote))
        duplicate.bezelStyle = .rounded
        let remove = NSButton(title: "删除", target: self, action: #selector(deleteNote))
        remove.bezelStyle = .rounded
        remove.toolTip = "移到应用内废纸篓，可从菜单栏恢复"
        addFullWidth(stack([locate, duplicate, NSView(), remove], spacing: 12), to: form)
        addFullWidth(lockHint, to: form)

        let desktopButton = NSButton(title: "收起编辑窗口", target: self, action: #selector(viewDesktop))
        desktopButton.toolTip = "收起后切回桌面查看文字；需要在其他应用上方显示时，请选择「始终置顶」"
        desktopButton.bezelStyle = .rounded
        desktopButton.controlSize = .large
        let footer = stack([statusLabel, NSView(), desktopButton], spacing: 12)
        footer.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(footer)
        NSLayoutConstraint.activate([
            headingRow.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 27),
            headingRow.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -27),
            headingRow.topAnchor.constraint(equalTo: detail.topAnchor, constant: 23),
            scroller.leadingAnchor.constraint(equalTo: headingRow.leadingAnchor),
            scroller.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -19),
            scroller.topAnchor.constraint(equalTo: headingRow.bottomAnchor, constant: 22),
            scroller.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -15),
            footer.leadingAnchor.constraint(equalTo: headingRow.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: headingRow.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: detail.bottomAnchor, constant: -18)
        ])
        editControls = [titleField, fontBox, sizeSlider, sizeField, boldButton, italicButton, underlineButton,
                        shadowButton, foreground, background, backgroundChoice, alignment, spacingSlider,
                        opacitySlider, mode, locate]
    }

    func addFullWidth(_ view: NSView, to form: NSStackView) {
        form.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
    }

    func refresh(select id: String? = nil) {
        updating = true
        defer { updating = false }
        if let id { selectedID = id }
        if !app.store.document.notes.contains(where: { $0.id == selectedID }) {
            selectedID = app.store.document.notes.first?.id
        }
        table.reloadData()
        if let index = app.store.document.notes.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
        countLabel.stringValue = "\(app.store.document.notes.count) 段文字 · 自动保存"
        guard let id = selectedID, let note = app.note(id) else {
            titleField.stringValue = ""
            bodyEditor.string = ""
            lockButton.isEnabled = false
            editControls.forEach { $0.isEnabled = false }
            bodyEditor.isEditable = false
            lockHint.stringValue = "点击左侧「新增文字」开始。删除的文字可在菜单栏中恢复。"
            return
        }
        if renderedID != id {
            bodyEditor.undoManager?.removeAllActions()
            renderedID = id
        }
        if titleField.stringValue != note.title { titleField.stringValue = note.title }
        if bodyEditor.string != note.text && !bodyEditor.hasMarkedText() { bodyEditor.string = note.text }
        fontBox.stringValue = note.fontFamily
        sizeSlider.doubleValue = min(note.fontSize, 120)
        if window?.firstResponder !== sizeField.currentEditor() { sizeField.stringValue = String(Int(note.fontSize)) }
        boldButton.state = note.bold ? .on : .off
        italicButton.state = note.italic ? .on : .off
        underlineButton.state = note.underline ? .on : .off
        shadowButton.state = note.shadow ? .on : .off
        foreground.color = note.foreground.color
        background.color = note.background.color
        backgroundChoice.selectedSegment = note.hasBackground ? 1 : 0
        alignment.selectedSegment = note.alignment
        spacingSlider.doubleValue = note.lineSpacing
        spacingValue.stringValue = String(Int(note.lineSpacing))
        opacitySlider.doubleValue = note.opacity
        opacityValue.stringValue = "\(Int(note.opacity * 100))%"
        mode.selectedSegment = note.onTop ? 1 : 0
        visibleButton.state = note.visible ? .on : .off
        lockButton.isEnabled = true
        lockButton.title = note.locked ? "解锁并编辑" : "锁定这段文字"
        lockButton.image = NSImage(systemSymbolName: note.locked ? "lock.open" : "lock", accessibilityDescription: nil)
        lockButton.imagePosition = .imageLeading
        lockButton.bezelColor = note.locked ? nil : .controlAccentColor
        editControls.forEach { $0.isEnabled = !note.locked }
        background.isEnabled = !note.locked && note.hasBackground
        bodyEditor.isEditable = !note.locked
        bodyEditor.isSelectable = !note.locked
        lockHint.stringValue = note.locked
            ? "已锁定：桌面上的文字不会响应鼠标。点击右上方「解锁并编辑」可修改。"
            : "桌面编辑：拖动上方小条定位，拖动右下角调整文字框；按 Esc 即可锁定。"
    }

    func mutate(_ block: (inout DesktopNote) -> Void) {
        guard !updating, let id = selectedID else { return }
        app.change(id, block)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { app.store.document.notes.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let note = app.store.document.notes[row]
        let name = label(note.title.isEmpty ? "未命名文字" : note.title, size: 12, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        name.maximumNumberOfLines = 1
        let description = label("\(note.locked ? "已锁定" : "可编辑") · \(note.onTop ? "置顶" : "桌面")\(note.visible ? "" : " · 已隐藏")", size: 10, color: .secondaryLabelColor)
        let column = stack([name, description], vertical: true, spacing: 5)
        column.edgeInsets = NSEdgeInsets(top: 9, left: 8, bottom: 6, right: 6)
        return column
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updating, table.selectedRow >= 0, table.selectedRow < app.store.document.notes.count else { return }
        selectedID = app.store.document.notes[table.selectedRow].id
        refresh()
    }
    func textDidChange(_ notification: Notification) {
        guard !updating, !bodyEditor.hasMarkedText() else { return }
        let text = bodyEditor.string
        mutate { $0.text = text }
    }
    func controlTextDidChange(_ obj: Notification) {
        guard !updating, let field = obj.object as? NSTextField, field === titleField else { return }
        let value = titleField.stringValue
        mutate { $0.title = value }
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard !updating else { return }
        if obj.object as? NSTextField === sizeField {
            let value = min(max(sizeField.doubleValue, 8), 240)
            mutate { $0.fontSize = value }
            sizeField.stringValue = String(Int(value))
        } else if obj.object as? NSComboBox === fontBox {
            fontChanged()
        }
    }
    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard !updating else { return }
        if fontBox.indexOfSelectedItem >= 0, let value = fontBox.objectValueOfSelectedItem as? String {
            mutate { $0.fontFamily = value }
        }
    }
    @objc func fontChanged() {
        guard !updating else { return }
        let value = fontBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let families = NSFontManager.shared.availableFontFamilies
        if let family = families.first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            mutate { $0.fontFamily = family }
        } else if let font = NSFont(name: value, size: 16) {
            mutate { $0.fontFamily = font.familyName ?? value }
        } else {
            refresh()
        }
    }
    @objc func sizeChanged() { let value = sizeSlider.doubleValue.rounded(); mutate { $0.fontSize = value }; sizeField.stringValue = String(Int(value)) }
    @objc func styleChanged() {
        let b = boldButton.state == .on, i = italicButton.state == .on
        let u = underlineButton.state == .on, s = shadowButton.state == .on
        mutate { $0.bold = b; $0.italic = i; $0.underline = u; $0.shadow = s }
    }
    @objc func colorChanged() {
        let fg = SavedColor(foreground.color), bg = SavedColor(background.color)
        mutate { $0.foreground = fg; $0.background = bg }
    }
    @objc func backgroundChanged() { let value = backgroundChoice.selectedSegment == 1; mutate { $0.hasBackground = value } }
    @objc func alignmentChanged() { let value = alignment.selectedSegment; mutate { $0.alignment = value } }
    @objc func lineSpacingChanged() { let value = spacingSlider.doubleValue.rounded(); mutate { $0.lineSpacing = value } }
    @objc func opacityChanged() { let value = opacitySlider.doubleValue; mutate { $0.opacity = value } }
    @objc func modeChanged() { let value = mode.selectedSegment == 1; mutate { $0.onTop = value } }
    @objc func visibilityChanged() { let value = visibleButton.state == .on; mutate { $0.visible = value } }
    @objc func toggleLock() { mutate { $0.locked.toggle() } }
    @objc func centerNote() { if let id = selectedID { app.center(id) } }
    @objc func duplicateNote() { if let id = selectedID { app.duplicate(id) } }
    @objc func deleteNote() { if let id = selectedID { app.remove(id) } }
    @objc func viewDesktop() {
        window?.makeFirstResponder(nil)
        app.store.flush()
        window?.orderOut(nil)
        for overlay in app.overlays.values where overlay.window.isVisible {
            overlay.window.orderFrontRegardless()
        }
    }
}

// MARK: - Menu bar application

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store: NoteStore
    var statusItem: NSStatusItem!
    var manager: ManagerController!
    var overlays: [String: NoteOverlay] = [:]
    var hideAll = false

    override init() {
        let arguments = CommandLine.arguments
        let directory: URL
        if let index = arguments.firstIndex(of: "--state-dir"), index + 1 < arguments.count {
            directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DesktopText", isDirectory: true)
        }
        store = NoteStore(directory: directory)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = " 桌面文字"
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "桌面文字")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "桌面文字：编辑、锁定或解锁"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        manager = ManagerController(app: self)
        store.onSave = { [weak self] text in self?.manager.statusLabel.stringValue = text }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        recoverOffscreenNotes()
        refresh()
        store.flush()
        showManager()
        if let message = store.loadMessage { manager.statusLabel.stringValue = message }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManager()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { store.flush() }

    func note(_ id: String) -> DesktopNote? { store.document.notes.first { $0.id == id } }
    func change(_ id: String, _ update: (inout DesktopNote) -> Void) {
        guard let index = store.document.notes.firstIndex(where: { $0.id == id }) else { return }
        update(&store.document.notes[index])
        refresh()
        store.scheduleSave()
    }
    func refresh() {
        let ids = Set(store.document.notes.map(\.id))
        for id in Array(overlays.keys) where !ids.contains(id) {
            overlays[id]?.window.orderOut(nil)
            overlays[id]?.window.close()
            overlays.removeValue(forKey: id)
        }
        for note in store.document.notes {
            if let overlay = overlays[note.id] { overlay.update(note) }
            else { overlays[note.id] = NoteOverlay(note: note, app: self) }
        }
        manager?.refresh()
        if manager?.window?.isKeyWindow == true { manager.window?.orderFront(nil) }
    }
    func showManager(select id: String? = nil) {
        manager.refresh(select: id)
        NSApp.activate(ignoringOtherApps: true)
        manager.showWindow(nil)
        manager.window?.makeKeyAndOrderFront(nil)
    }
    @objc func openManager() { showManager() }
    @objc func addNote() {
        var note = DesktopNote()
        note.title = store.document.notes.isEmpty ? "我的桌面文字" : "新文字 \(store.document.notes.count + 1)"
        note.text = "在这里写下你的提醒…"
        note.fontSize = 28
        if let screen = NSScreen.main?.visibleFrame {
            let offset = CGFloat(store.document.notes.count % 5) * 24
            note.frame = NSRect(x: screen.midX - 260 + offset, y: screen.midY - 105 - offset, width: 520, height: 210)
        }
        store.document.notes.append(note)
        hideAll = false
        refresh()
        showManager(select: note.id)
        store.scheduleSave()
    }
    @objc func lockAll() {
        manager.window?.makeFirstResponder(nil)
        for index in store.document.notes.indices { store.document.notes[index].locked = true }
        refresh()
        store.scheduleSave()
    }
    @objc func toggleHideAll() { hideAll.toggle(); refresh() }
    func center(_ id: String) {
        guard let screen = NSScreen.main?.visibleFrame, let note = note(id) else { return }
        var frame = note.frame
        frame.size.width = min(frame.width, screen.width - 40)
        frame.size.height = min(frame.height, screen.height - 40)
        frame.origin = NSPoint(x: screen.midX - frame.width / 2, y: screen.midY - frame.height / 2)
        change(id) { $0.frame = frame; $0.visible = true }
    }
    func duplicate(_ id: String) {
        guard var copy = note(id) else { return }
        copy.id = UUID().uuidString
        copy.title += " 副本"
        copy.x += 24; copy.y -= 24
        copy.locked = false
        copy.visible = true
        store.document.notes.append(copy)
        recoverOffscreenNotes()
        refresh()
        showManager(select: copy.id)
        store.scheduleSave()
    }
    func remove(_ id: String) {
        guard let index = store.document.notes.firstIndex(where: { $0.id == id }) else { return }
        store.document.trash.append(store.document.notes.remove(at: index))
        refresh()
        store.scheduleSave()
    }
    @objc func restoreDeleted() {
        guard var restored = store.document.trash.popLast() else { return }
        restored.visible = true
        store.document.notes.append(restored)
        recoverOffscreenNotes()
        refresh()
        showManager(select: restored.id)
        store.scheduleSave()
    }
    @objc func screensChanged() { recoverOffscreenNotes(); refresh(); store.scheduleSave() }
    func recoverOffscreenNotes() {
        guard let main = NSScreen.main?.visibleFrame else { return }
        for index in store.document.notes.indices {
            let frame = store.document.notes[index].frame
            let intersects = NSScreen.screens.contains { screen in
                let intersection = screen.visibleFrame.intersection(frame)
                return !intersection.isNull && intersection.width >= 120 && intersection.height >= 75
            }
            if !intersects {
                var adjusted = frame
                adjusted.size.width = min(frame.width, main.width - 40)
                adjusted.size.height = min(frame.height, main.height - 40)
                adjusted.origin = NSPoint(x: main.midX - adjusted.width / 2, y: main.midY - adjusted.height / 2)
                store.document.notes[index].frame = adjusted
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addMenuItem("管理与编辑…", action: #selector(openManager), key: ",", to: menu)
        addMenuItem("新增文字…", action: #selector(addNote), key: "n", to: menu)
        addMenuItem("锁定全部文字", action: #selector(lockAll), key: "l", to: menu)
        addMenuItem(hideAll ? "重新显示全部文字" : "临时隐藏全部文字", action: #selector(toggleHideAll), to: menu)
        menu.addItem(.separator())
        for note in store.document.notes {
            let title = note.title.isEmpty ? "未命名文字" : note.title
            let parent = NSMenuItem(title: "\(note.locked ? "🔒" : "✎") \(title)", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let edit = addMenuItem("解锁并编辑", action: #selector(menuEdit(_:)), to: submenu)
            edit.representedObject = note.id
            let lock = addMenuItem(note.locked ? "解锁文字" : "锁定文字", action: #selector(menuLock(_:)), to: submenu)
            lock.representedObject = note.id
            let visibility = addMenuItem(note.visible ? "隐藏这段文字" : "显示这段文字", action: #selector(menuVisibility(_:)), to: submenu)
            visibility.representedObject = note.id
            parent.submenu = submenu
            menu.addItem(parent)
        }
        if !store.document.trash.isEmpty {
            menu.addItem(.separator())
            addMenuItem("恢复最近删除的文字", action: #selector(restoreDeleted), to: menu)
        }
        menu.addItem(.separator())
        let login = addMenuItem("登录时自动启动", action: #selector(toggleLogin), to: menu)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        addMenuItem("使用说明…", action: #selector(showHelp), to: menu)
        menu.addItem(.separator())
        addMenuItem("退出桌面文字", action: #selector(quit), key: "q", to: menu)
    }
    @discardableResult func addMenuItem(_ title: String, action: Selector, key: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }
    @objc func menuEdit(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        change(id) { $0.locked = false; $0.visible = true }
        hideAll = false
        refresh()
        showManager(select: id)
    }
    @objc func menuLock(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        change(id) { $0.locked.toggle() }
    }
    @objc func menuVisibility(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        change(id) { $0.visible.toggle() }
    }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            if SMAppService.mainApp.status == .requiresApproval {
                let alert = NSAlert()
                alert.messageText = "请在系统设置中允许登录项"
                alert.informativeText = "在「系统设置 → 通用 → 登录项与扩展」中允许“桌面文字”自动启动。"
                alert.addButton(withTitle: "知道了")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "暂时无法设置自动启动"
            alert.informativeText = "你也可以在「系统设置 → 通用 → 登录项与扩展」中手动添加此应用。\n\n\(error.localizedDescription)"
            alert.addButton(withTitle: "知道了")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
    @objc func showHelp() {
        let alert = NSAlert()
        alert.messageText = "桌面文字 · 使用说明"
        alert.informativeText = """
        1. 在管理窗口输入文字，选择字体、字号和样式。
        2. 解锁时，可直接在桌面输入；拖动文字上方的小条定位，拖动右下角调整文字框。
        3. 点击「锁定这段文字」或在桌面编辑时按 Esc。锁定后，文字不会接收鼠标操作。
        4. 点击屏幕顶部「桌面文字」→「管理与编辑…」，即可解锁修改。

        「贴在桌面」会被其他窗口盖住；「始终置顶」显示在普通应用窗口上方。
        关闭管理窗口后，文字仍会显示。选择菜单栏中的「退出桌面文字」才会退出应用。
        内容、样式和位置自动保存在本机；删除的文字可在菜单栏中恢复。
        """
        alert.addButton(withTitle: "开始使用")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    @objc func quit() { NSApp.terminate(nil) }

    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于桌面文字", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        addMenuItem("管理与编辑…", action: #selector(openManager), key: ",", to: appMenu)
        addMenuItem("使用说明…", action: #selector(showHelp), to: appMenu)
        appMenu.addItem(.separator())
        addMenuItem("退出桌面文字", action: #selector(quit), key: "q", to: appMenu)
        appItem.submenu = appMenu
        main.addItem(appItem)
        let fileItem = NSMenuItem()
        fileItem.title = "文件"
        let fileMenu = NSMenu(title: "文件")
        addMenuItem("新增文字", action: #selector(addNote), key: "n", to: fileMenu)
        addMenuItem("锁定全部文字", action: #selector(lockAll), key: "l", to: fileMenu)
        fileItem.submenu = fileMenu
        main.addItem(fileItem)
        let editItem = NSMenuItem()
        editItem.title = "编辑"
        let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [
            ("撤销", Selector(("undo:")), "z"),
            ("剪切", #selector(NSText.cut(_:)), "x"),
            ("复制", #selector(NSText.copy(_:)), "c"),
            ("粘贴", #selector(NSText.paste(_:)), "v"),
            ("全选", #selector(NSText.selectAll(_:)), "a")
        ] { editMenu.addItem(withTitle: title, action: selector, keyEquivalent: key) }
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.insertItem(redo, at: 1)
        editItem.submenu = editMenu
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}

// MARK: - Native smoke tests

func runSelfTests() -> Int32 {
    var passed = 0
    var failed = 0
    func check(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL") \(message)")
        if condition { passed += 1 } else { failed += 1 }
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DesktopTextTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = NoteStore(directory: directory)
    check(store.document.notes.count == 1, "First launch creates an editable sample")
    var note = store.document.notes[0]
    note.text = "中文输入测试\n09:00 学习"
    note.fontFamily = "Songti SC"
    note.fontSize = 52
    note.bold = false
    note.underline = true
    note.locked = true
    note.onTop = true
    note.frame = NSRect(x: 140, y: 200, width: 480, height: 260)
    store.document.notes[0] = note
    check(store.flush(), "Document writes atomically")
    let reloaded = NoteStore(directory: directory)
    check(reloaded.document.notes[0] == note, "Text, font, style, lock, mode and position survive restart")
    check(note.font.pointSize == 52, "Selected font size is applied")
    check(note.attributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue, "Underline attribute is applied")
    let delegate = AppDelegate()
    delegate.hideAll = false
    let overlay = NoteOverlay(note: note, app: delegate)
    check(overlay.window.ignoresMouseEvents, "Locked overlay passes mouse events through")
    check(!overlay.window.canBecomeKey && !overlay.textView.isEditable && !overlay.textView.isSelectable, "Locked overlay cannot take keyboard focus or edit")
    check(overlay.header.isHidden && overlay.grip.isHidden, "Locked overlay hides editing controls")
    check(overlay.window.level == .floating, "Always-on-top mode uses the floating level")
    let lockedFrame = overlay.window.frame
    note.locked = false
    overlay.update(note)
    check(!overlay.window.ignoresMouseEvents && overlay.window.canBecomeKey && overlay.textView.isEditable, "Unlock restores desktop editing")
    check(overlay.window.frame == lockedFrame, "Lock and unlock preserve content position")
    let probe = NSWindow(contentRect: note.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    probe.isReleasedWhenClosed = false
    probe.backgroundColor = .windowBackgroundColor
    probe.level = .normal
    probe.orderFrontRegardless()
    overlay.window.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
    NSApp.updateWindows()
    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    let point = NSPoint(x: note.frame.midX, y: note.frame.midY)
    check(NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) == overlay.window.windowNumber,
          "Native hit testing reaches the unlocked text window")
    note.locked = true
    overlay.update(note)
    overlay.window.orderFrontRegardless()
    NSApp.updateWindows()
    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    let hitAfterLock = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
    check(hitAfterLock == probe.windowNumber,
          "Native hit testing passes through locked text to the window underneath")
    delegate.hideAll = true
    overlay.update(note)
    delegate.hideAll = false
    overlay.update(note)
    NSApp.updateWindows()
    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    check(NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) == probe.windowNumber,
          "Click-through remains active after hiding and showing locked text")
    probe.close()
    note.locked = true; note.onTop = false
    overlay.update(note)
    check(overlay.window.level.rawValue < NSWindow.Level.normal.rawValue, "Desktop mode remains below ordinary application windows")
    store.document.trash.append(store.document.notes.removeFirst())
    _ = store.flush()
    let deleted = NoteStore(directory: directory)
    check(deleted.document.notes.isEmpty && deleted.document.trash.count == 1, "Deletion remains recoverable after restart")
    overlay.window.close()
    print("RESULT \(passed) passed, \(failed) failed")
    return failed == 0 ? 0 : 1
}

let application = NSApplication.shared
if CommandLine.arguments.contains("--self-test") {
    var result: Int32 = 1
    DispatchQueue.main.async {
        result = runSelfTests()
        NSApp.stop(nil)
    }
    application.run()
    exit(result)
}
let delegate = AppDelegate()
application.delegate = delegate
application.run()
