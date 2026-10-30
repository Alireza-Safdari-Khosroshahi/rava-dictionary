import AppKit
import AVFoundation

private let teal = NSColor(calibratedRed: 0.08, green: 0.43, blue: 0.43, alpha: 1)
private let ink = NSColor.labelColor

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                   color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = NSFont.systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.maximumNumberOfLines = 0
    field.lineBreakMode = .byWordWrapping
    return field
}

private func stack(_ orientation: NSUserInterfaceLayoutOrientation, spacing: CGFloat = 0) -> NSStackView {
    let view = NSStackView()
    view.orientation = orientation
    view.spacing = spacing
    view.alignment = orientation == .horizontal ? .centerY : .leading
    view.distribution = .fill
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}

final class AppController: NSObject, NSApplicationDelegate, NSSearchFieldDelegate,
                           NSTableViewDataSource, NSTableViewDelegate {
    private var window: NSWindow!
    private let store = DictionaryStore()
    private var results: [Word] = []
    private var current: Word?
    private var favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
    private var savedOnly = false
    private let speaker = AVSpeechSynthesizer()
    private let search = NSSearchField()
    private let directionPicker = NSPopUpButton()
    private let table = NSTableView()
    private let countLabel = label("", size: 11, weight: .semibold, color: .secondaryLabelColor)
    private let titleLabel = label("Select a word", size: 36, weight: .bold, color: ink)
    private let ipaLabel = label("", size: 15, color: .secondaryLabelColor)
    private let favoriteButton = NSButton(title: "Save", target: nil, action: nil)
    private let speakButton = NSButton(title: "Speak", target: nil, action: nil)
    private let details = stack(.vertical, spacing: 14)
    private let segment = NSSegmentedControl(labels: ["All words", "Saved"], trackingMode: .selectOne,
                                             target: nil, action: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "Rava", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        makeMenu()
        buildWindow()
        runSearch()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(search)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func makeMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Data & Licenses…", action: #selector(showLicenses(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Rava", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 690),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Rava Dictionary"
        window.center()
        window.minSize = NSSize(width: 820, height: 540)

        let root = stack(.horizontal)
        root.alignment = .top
        window.contentView = root
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        sidebar.widthAnchor.constraint(equalToConstant: 350).isActive = true
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(sidebar)
        root.addArrangedSubview(divider)
        root.addArrangedSubview(content)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            sidebar.heightAnchor.constraint(equalTo: root.heightAnchor),
            divider.heightAnchor.constraint(equalTo: root.heightAnchor),
            content.heightAnchor.constraint(equalTo: root.heightAnchor)
        ])
        buildSidebar(sidebar)
        buildDetail(content)
    }

    private func buildSidebar(_ parent: NSView) {
        let heading = label("Rava", size: 28, weight: .bold, color: ink)
        let symbol = NSImageView(image: NSImage(systemSymbolName: "character.book.closed.fill",
                                               accessibilityDescription: "Dictionary")!)
        symbol.contentTintColor = teal
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.widthAnchor.constraint(equalToConstant: 28).isActive = true
        symbol.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let badge = label("OFFLINE", size: 10, weight: .bold, color: teal)
        let headingRow = stack(.horizontal, spacing: 9)
        headingRow.addArrangedSubview(symbol)
        headingRow.addArrangedSubview(heading)
        headingRow.addArrangedSubview(NSView())
        headingRow.addArrangedSubview(badge)
        let subtitle = label("English · Persian · German", size: 13,
                             color: .secondaryLabelColor)
        directionPicker.addItems(withTitles: Direction.allCases.map(\.title))
        directionPicker.selectItem(at: 0)
        directionPicker.target = self
        directionPicker.action = #selector(changeDirection(_:))
        search.placeholderString = "Search English words"
        search.delegate = self
        search.sendsSearchStringImmediately = true
        segment.selectedSegment = 0
        segment.target = self
        segment.action = #selector(changeSegment(_:))
        let header = stack(.vertical, spacing: 13)
        for view in [headingRow, subtitle, directionPicker, search, segment, countLabel] {
            header.addArrangedSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        }
        parent.addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -20),
            header.topAnchor.constraint(equalTo: parent.topAnchor, constant: 22)
        ])
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("words"))
        column.title = "Words"
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 61
        table.selectionHighlightStyle = .regular
        table.delegate = self
        table.dataSource = self
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        parent.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }

    private func buildDetail(_ parent: NSView) {
        let header = stack(.horizontal, spacing: 10)
        let wordHead = stack(.vertical, spacing: 4)
        wordHead.addArrangedSubview(titleLabel)
        wordHead.addArrangedSubview(ipaLabel)
        header.addArrangedSubview(wordHead)
        header.addArrangedSubview(NSView())
        favoriteButton.target = self
        favoriteButton.action = #selector(toggleFavorite(_:))
        favoriteButton.bezelStyle = .rounded
        header.addArrangedSubview(favoriteButton)
        speakButton.target = self
        speakButton.action = #selector(speak(_:))
        speakButton.bezelStyle = .rounded
        header.addArrangedSubview(speakButton)
        parent.addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 30),
            header.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -30),
            header.topAnchor.constraint(equalTo: parent.topAnchor, constant: 26),
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: 65)
        ])
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            line.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18)
        ])
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(details)
        scroll.documentView = document
        parent.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 18),
            scroll.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -18),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            details.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            details.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            details.topAnchor.constraint(equalTo: document.topAnchor),
            details.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        showWelcome()
    }

    private func clearDetails() {
        for view in details.arrangedSubviews {
            details.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func showWelcome() {
        titleLabel.stringValue = "Find the right word"
        ipaLabel.stringValue = "Fast, private, and entirely offline"
        favoriteButton.isHidden = true
        speakButton.isHidden = true
        clearDetails()
        details.addArrangedSubview(label("Choose a language direction, then search a word.",
                                          size: 16, color: .secondaryLabelColor))
    }

    private func show(_ word: Word) {
        current = word
        titleLabel.stringValue = word.english
        ipaLabel.stringValue = [word.ipa.isEmpty ? "" : "/\(word.ipa)/", word.level]
            .filter { !$0.isEmpty }.joined(separator: "   ·   ")
        favoriteButton.isHidden = false
        speakButton.isHidden = false
        favoriteButton.title = favorites.contains(word.id) ? "★ Saved" : "☆ Save"
        clearDetails()
        if word.direction.usesBridge {
            details.addArrangedSubview(label("Translations via English · check important meanings",
                                              size: 12, color: .secondaryLabelColor))
        }
        let senses = store?.senses(for: word) ?? []
        details.addArrangedSubview(label("\(senses.count) MEANINGS", size: 11,
                                          weight: .bold, color: .secondaryLabelColor))
        for sense in senses {
            let card = stack(.vertical, spacing: 8)
            card.edgeInsets = NSEdgeInsets(top: 15, left: 16, bottom: 15, right: 16)
            card.wantsLayer = true
            card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            card.layer?.cornerRadius = 11
            card.addArrangedSubview(label(sense.partOfSpeech.uppercased(), size: 11,
                                          weight: .bold, color: teal))
            if !sense.meaning.isEmpty {
                let translation = label(sense.meaning, size: 22, weight: .medium, color: ink)
                translation.alignment = word.direction.targetsPersian ? .right : .left
                card.addArrangedSubview(translation)
                translation.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -32).isActive = true
            }
            if !sense.definition.isEmpty {
                card.addArrangedSubview(label(sense.definition, size: 14, color: ink))
            }
            if !sense.bridge.isEmpty {
                card.addArrangedSubview(label("via English: \(sense.bridge)", size: 12,
                                              color: .secondaryLabelColor))
            }
            if !sense.example.isEmpty {
                card.addArrangedSubview(label(sense.example, size: 13,
                                              color: .secondaryLabelColor))
            }
            if !sense.persianExample.isEmpty {
                let example = label(sense.persianExample, size: 13,
                                    color: .secondaryLabelColor)
                example.alignment = .right
                card.addArrangedSubview(example)
                example.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -32).isActive = true
            }
            details.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true
        }
    }

    private func runSearch() {
        let direction = Direction.allCases[directionPicker.indexOfSelectedItem]
        let all = savedOnly && search.stringValue.isEmpty
            ? (store?.words(ids: favorites, direction: direction) ?? [])
            : (store?.search(search.stringValue, direction: direction) ?? [])
        results = savedOnly ? all.filter { favorites.contains($0.id) } : all
        let countKind = savedOnly ? "SAVED WORDS" : (search.stringValue.isEmpty ? "COMMON WORDS" : "RESULTS")
        countLabel.stringValue = "\(results.count) \(countKind)"
        table.reloadData()
        if let current, !results.contains(where: { $0.id == current.id }) {
            self.current = nil
            showWelcome()
        }
    }

    func controlTextDidChange(_ obj: Notification) { runSearch() }
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let word = results[row]
        let cell = NSView()
        let english = label(word.english + (favorites.contains(word.id) ? "  ★" : ""),
                            size: 16, weight: .semibold, color: ink)
        let meaning = label(word.preview, size: 12, color: .secondaryLabelColor)
        english.translatesAutoresizingMaskIntoConstraints = false
        meaning.translatesAutoresizingMaskIntoConstraints = false
        english.lineBreakMode = .byTruncatingTail
        english.maximumNumberOfLines = 1
        meaning.lineBreakMode = .byTruncatingTail
        meaning.maximumNumberOfLines = 1
        cell.addSubview(english)
        cell.addSubview(meaning)
        NSLayoutConstraint.activate([
            english.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            english.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            english.topAnchor.constraint(equalTo: cell.topAnchor, constant: 9),
            meaning.leadingAnchor.constraint(equalTo: english.leadingAnchor),
            meaning.trailingAnchor.constraint(equalTo: english.trailingAnchor),
            meaning.topAnchor.constraint(equalTo: english.bottomAnchor, constant: 4)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        if row >= 0 && row < results.count { show(results[row]) }
    }

    @objc private func changeSegment(_ sender: NSSegmentedControl) {
        savedOnly = sender.selectedSegment == 1
        runSearch()
    }

    @objc private func changeDirection(_ sender: NSPopUpButton) {
        let direction = Direction.allCases[sender.indexOfSelectedItem]
        search.stringValue = ""
        search.placeholderString = "Search \(direction.title.components(separatedBy: " → ")[0]) words"
        current = nil
        showWelcome()
        runSearch()
        window.makeFirstResponder(search)
    }

    @objc private func toggleFavorite(_ sender: NSButton) {
        guard let word = current else { return }
        if favorites.contains(word.id) { favorites.remove(word.id) }
        else { favorites.insert(word.id) }
        UserDefaults.standard.set(Array(favorites), forKey: "favorites")
        favoriteButton.title = favorites.contains(word.id) ? "★ Saved" : "☆ Save"
        runSearch()
    }

    @objc private func speak(_ sender: NSButton) {
        guard let word = current else { return }
        let utterance = AVSpeechUtterance(string: word.english)
        utterance.voice = AVSpeechSynthesisVoice(language: word.direction.sourceLanguage)
        speaker.speak(utterance)
    }

    @objc private func showLicenses(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Rava Dictionary data"
        alert.informativeText = "English–Persian data: Openjam (MIT). German–English data: WikDict by Karl Bartel, from Wiktionary via DBnary (CC BY-SA 4.0). German–Persian entries are derived via English and distributed under CC BY-SA 4.0. Full attribution is included with the app and on GitHub."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let application = NSApplication.shared
let controller = AppController()
application.delegate = controller
application.run()
