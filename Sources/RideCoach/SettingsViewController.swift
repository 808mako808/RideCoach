import AppKit

@MainActor
final class SettingsViewController: NSViewController, NSWindowDelegate {
    private weak var store: RideCoachStore?

    private let clientIdField = NSTextField()
    private let clientSecretField = NSSecureTextField()
    private let ollamaBaseURLField = NSTextField()
    private let ollamaModelPopup = NSPopUpButton()
    private let autoCheckButton = NSButton(checkboxWithTitle: "Check automatically", target: nil, action: nil)
    private let notificationsButton = NSButton(checkboxWithTitle: "Notify when new rides are analyzed", target: nil, action: nil)
    private let cadenceControl = NSSegmentedControl(labels: CheckCadence.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let checkTimePicker = NSDatePicker()
    private let weekdayPopup = NSPopUpButton()
    private let scheduleNote = NSTextField(wrappingLabelWithString: "")
    private var weekdayRow: NSView?
    private var checkTimeRow: NSView?

    init(store: RideCoachStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 560))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        scrollView.documentView = documentView

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 24),

            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24)
        ])

        configureFields()

        let weekdayRow = labeledPopup("Weekly day", weekdayPopup)
        let checkTimeRow = labeledDatePicker("Check time", checkTimePicker)
        self.weekdayRow = weekdayRow
        self.checkTimeRow = checkTimeRow

        stack.addArrangedSubview(headerView())
        stack.addArrangedSubview(section(title: "AI Analysis Caution", views: [
            note("Ride Coach Beta uses local AI analysis from Ollama. AI output may be incomplete, inaccurate, or overconfident, and it may miss important training, medical, weather, equipment, traffic, or safety context. Treat the analysis as a helpful reflection aid, not professional coaching, medical advice, or a substitute for your own judgment.")
        ]))
        stack.addArrangedSubview(section(title: "Strava", views: [
            labeledField("Client ID", clientIdField),
            labeledField("Client Secret", clientSecretField),
            note("Set the Strava app callback domain to localhost and use http://localhost:8754/callback as the redirect URL."),
            buttonRow([
                button("Open Strava API Settings", action: #selector(openStravaSettings)),
                button("Show Strava Icon", action: #selector(revealStravaIcon)),
                button("Copy Icon Path", action: #selector(copyStravaIconPath)),
                button(store?.isConnectedToStrava == true ? "Reconnect Strava" : "Connect Strava", action: #selector(connectStrava)),
                button("Disconnect", action: #selector(disconnectStrava))
            ]),
            note("Use the included Strava icon PNG when Strava asks for an application icon.")
        ]))
        stack.addArrangedSubview(section(title: "Ollama", views: [
            labeledField("Base URL", ollamaBaseURLField),
            labeledPopup("Model", ollamaModelPopup),
            buttonRow([
                button("Check Ollama", action: #selector(checkOllama)),
                button("Install Selected Model", action: #selector(installSelectedOllamaModel)),
                button("Open Ollama Download", action: #selector(openOllamaDownload))
            ]),
            note("Ride Coach uses a local Ollama server. Install Ollama separately, start it, then install the selected model.")
        ]))
        stack.addArrangedSubview(section(title: "Checks", views: [
            autoCheckButton,
            notificationsButton,
            cadenceControl,
            weekdayRow,
            checkTimeRow,
            scheduleNote,
            buttonRow([
                button("Check Now", action: #selector(checkNow)),
                button("Reanalyze Latest", action: #selector(reanalyzeLatest)),
                button("Send Test Notification", action: #selector(sendTestNotification)),
                button("Open Notification Settings", action: #selector(openNotificationSettings))
            ]),
            note("Reanalyze Latest clears saved ride analysis state and runs a fresh check with the current Ollama model.")
        ]))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refreshFromStore()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(clientIdField)
    }

    func windowWillClose(_ notification: Notification) {
        saveToStore()
    }

    private func configureFields() {
        [clientIdField, clientSecretField, ollamaBaseURLField].forEach { field in
            field.isEditable = true
            field.isSelectable = true
            field.target = self
            field.action = #selector(saveToStore)
            field.translatesAutoresizingMaskIntoConstraints = false
        }

        ollamaModelPopup.removeAllItems()
        for model in OllamaModelOption.allCases {
            ollamaModelPopup.addItem(withTitle: model.menuTitle)
            ollamaModelPopup.lastItem?.representedObject = model.rawValue
        }
        ollamaModelPopup.target = self
        ollamaModelPopup.action = #selector(saveToStore)
        ollamaModelPopup.translatesAutoresizingMaskIntoConstraints = false

        autoCheckButton.target = self
        autoCheckButton.action = #selector(saveToStore)
        notificationsButton.target = self
        notificationsButton.action = #selector(saveToStore)
        cadenceControl.target = self
        cadenceControl.action = #selector(saveToStore)

        weekdayPopup.removeAllItems()
        for weekday in WeekdayOption.allCases {
            weekdayPopup.addItem(withTitle: weekday.title)
            weekdayPopup.lastItem?.representedObject = weekday.rawValue
        }
        weekdayPopup.target = self
        weekdayPopup.action = #selector(saveToStore)
        weekdayPopup.translatesAutoresizingMaskIntoConstraints = false

        checkTimePicker.datePickerElements = [.hourMinute]
        checkTimePicker.datePickerStyle = .textFieldAndStepper
        checkTimePicker.target = self
        checkTimePicker.action = #selector(saveToStore)
        checkTimePicker.translatesAutoresizingMaskIntoConstraints = false

        scheduleNote.textColor = .secondaryLabelColor
        scheduleNote.font = .systemFont(ofSize: 12)
    }

    private func refreshFromStore() {
        guard let store else { return }
        clientIdField.stringValue = store.clientId
        clientSecretField.stringValue = store.clientSecret
        ollamaBaseURLField.stringValue = store.ollamaBaseURL
        selectModel(store.ollamaModel)
        autoCheckButton.state = store.autoCheckEnabled ? .on : .off
        notificationsButton.state = store.notificationsEnabled ? .on : .off
        cadenceControl.selectedSegment = CheckCadence.allCases.firstIndex(of: store.cadence) ?? 0
        selectWeekday(store.scheduledWeekday)
        checkTimePicker.dateValue = dateForTime(hour: store.scheduledHour, minute: store.scheduledMinute)
        refreshScheduleControls()
    }

    @objc private func saveToStore() {
        guard let store else { return }
        store.clientId = clientIdField.stringValue
        store.clientSecret = clientSecretField.stringValue
        store.ollamaBaseURL = ollamaBaseURLField.stringValue
        store.ollamaModel = ollamaModelPopup.selectedItem?.representedObject as? String ?? OllamaModelOption.llamaSmall.rawValue
        store.autoCheckEnabled = autoCheckButton.state == .on
        store.notificationsEnabled = notificationsButton.state == .on
        store.cadence = CheckCadence.allCases[max(0, cadenceControl.selectedSegment)]
        let components = Calendar.current.dateComponents([.hour, .minute], from: checkTimePicker.dateValue)
        store.scheduledHour = components.hour ?? 8
        store.scheduledMinute = components.minute ?? 0
        store.scheduledWeekday = weekdayPopup.selectedItem?.representedObject as? Int ?? 2
        refreshScheduleControls()
    }

    @objc private func openStravaSettings() {
        NSWorkspace.shared.open(URL(string: "https://www.strava.com/settings/api")!)
    }

    @objc private func revealStravaIcon() {
        store?.revealStravaIcon()
    }

    @objc private func copyStravaIconPath() {
        store?.copyStravaIconPath()
    }

    @objc private func connectStrava() {
        saveToStore()
        store?.connectStrava()
    }

    @objc private func disconnectStrava() {
        store?.disconnectStrava()
    }

    @objc private func checkNow() {
        saveToStore()
        Task { await store?.checkNow() }
    }

    @objc private func reanalyzeLatest() {
        saveToStore()
        Task { await store?.reanalyzeLatest() }
    }

    @objc private func sendTestNotification() {
        saveToStore()
        store?.sendTestNotification()
    }

    @objc private func openNotificationSettings() {
        store?.openNotificationSettings()
    }

    @objc private func checkOllama() {
        saveToStore()
        Task { await store?.checkOllama() }
    }

    @objc private func installSelectedOllamaModel() {
        saveToStore()
        Task { await store?.installSelectedOllamaModel() }
    }

    @objc private func openOllamaDownload() {
        store?.openOllamaDownload()
    }

    private func headerView() -> NSView {
        let title = NSTextField(labelWithString: "\(AppInfo.displayName) Settings")
        title.font = .boldSystemFont(ofSize: 22)

        let subtitle = NSTextField(wrappingLabelWithString: "Version \(AppInfo.version). Connect Strava, choose your local Ollama model, and set how often Ride Coach looks for new rides.")
        subtitle.textColor = .secondaryLabelColor

        return verticalStack([title, subtitle], spacing: 4)
    }

    private func section(title: String, views: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 14)
        return verticalStack([titleLabel] + views, spacing: 8)
    }

    private func labeledField(_ label: String, _ field: NSTextField) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.textColor = .secondaryLabelColor
        let stack = verticalStack([labelView, field], spacing: 4)
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 440).isActive = true
        return stack
    }

    private func labeledPopup(_ label: String, _ popup: NSPopUpButton) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.textColor = .secondaryLabelColor
        let stack = verticalStack([labelView, popup], spacing: 4)
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        return stack
    }

    private func labeledDatePicker(_ label: String, _ picker: NSDatePicker) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.textColor = .secondaryLabelColor
        let stack = verticalStack([labelView, picker], spacing: 4)
        picker.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        return stack
    }

    private func selectModel(_ model: String) {
        let selectedModel = OllamaModelOption.allCases.first { $0.rawValue == model } ?? .llamaSmall
        for item in ollamaModelPopup.itemArray where item.representedObject as? String == selectedModel.rawValue {
            ollamaModelPopup.select(item)
            return
        }
    }

    private func selectWeekday(_ weekday: Int) {
        let selectedWeekday = WeekdayOption(rawValue: weekday) ?? .monday
        for item in weekdayPopup.itemArray where item.representedObject as? Int == selectedWeekday.rawValue {
            weekdayPopup.select(item)
            return
        }
    }

    private func dateForTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func refreshScheduleControls() {
        let cadence = CheckCadence.allCases[max(0, cadenceControl.selectedSegment)]
        let usesWallClockSchedule = cadence != .hourly
        weekdayRow?.isHidden = cadence != .weekly
        checkTimeRow?.isHidden = !usesWallClockSchedule
        scheduleNote.stringValue = scheduleDescription(for: cadence)
        scheduleNote.isHidden = autoCheckButton.state != .on
    }

    private func scheduleDescription(for cadence: CheckCadence) -> String {
        guard let store else { return "" }
        switch cadence {
        case .hourly:
            return "Hourly checks run one hour after the app starts, then every hour while Ride Coach is open."
        case .daily:
            return "Daily checks run at the selected local time. Next check: \(scheduleDateFormatter.string(from: store.nextCheckDate(after: Date())))."
        case .weekly:
            return "Weekly checks run on the selected day and local time. Next check: \(scheduleDateFormatter.string(from: store.nextCheckDate(after: Date())))."
        }
    }

    private func note(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 12)
        return label
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func buttonRow(_ buttons: [NSButton]) -> NSView {
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }
}

private enum WeekdayOption: Int, CaseIterable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var title: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }
}

private let scheduleDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()
