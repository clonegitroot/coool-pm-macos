import SwiftUI
import PDFKit
import ImageIO
import UniformTypeIdentifiers

enum BusinessSettingsWindow {
    static let id = "coool-pm-settings"
}

struct BusinessSettingsCommands: Commands {
    let locale: Locale
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(AppLanguage.text("Settings…", fallback: "Settings…", locale: locale)) {
                openWindow(id: BusinessSettingsWindow.id)
            }.keyboardShortcut(",")
        }
    }
}

struct BusinessSettings: View {
    @AppStorage(BackupReminder.storageKey) private var backupReminderDays = BackupReminder.defaultDays
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system
    @AppStorage("appAppearance") private var appearance = AppAppearance.system
    @AppStorage("documentLanguage") private var documentLanguage = AppLanguage.german
    @AppStorage("libraryBackupRequested") private var libraryBackupRequested = false
    @AppStorage("onboardingRequested") private var onboardingRequested = false
    @AppStorage("libraryResetRequested") private var libraryResetRequested = false
    @ProtectedSetting("xrechnungJavaPath") private var xrechnungJavaPath = ""
    @ProtectedSetting("xrechnungValidatorPath") private var xrechnungValidatorPath = ""
    @ProtectedSetting("xrechnungRulesPath") private var xrechnungRulesPath = ""
    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale
    @AppStorage("projectAutosave") private var projectAutosave = true
    @State private var demo: DemoPresentation?
    @State private var profile = BusinessProfile.load()
    @State private var invoice = false
    @State private var german = true
    @State private var preview: PDFDocument?
    @State private var error = ""
    @State private var customInstalled = false
    @State private var copiedMCPConfiguration = false
    @AppStorage("mcpEnabled") private var mcpEnabled = false
    @AppStorage("requireLaunchAuthentication") private var requireLaunchAuthentication = false
    @AppStorage("localAISettingsRequested") private var localAISettingsRequested = false
    @State private var changingLock = false
    @AppStorage("mcpAllowWrite") private var includeMCPWrites = false
    @AppStorage("mcpAllowFinancials") private var includeMCPFinancials = false
    private enum Section: String, CaseIterable {
        case localAI = "Local AI", features = "Features", general = "General", business = "Business", rates = "Day rates", pricing = "Pricing categories", templates = "Templates", terms = "Terms", electronic = "XRechnung", library = "Library", updates = "Updates"

        var icon: String {
            switch self {
            case .localAI: "sparkles"
            case .features: "slider.horizontal.3"
            case .general: "gearshape"
            case .business: "building.2"
            case .rates: "chart.line.uptrend.xyaxis"
            case .pricing: "tag"
            case .templates: "doc.text"
            case .terms: "list.bullet.rectangle"
            case .electronic: "doc.badge.gearshape"
            case .library: "externaldrive"
            case .updates: "arrow.down.circle"
            }
        }
    }

    private enum DemoPresentation: String, Identifiable {
        case library, tour
        var id: Self { self }
    }

    private var navigationGroups: [(String, [Section])] {
        [("App", [.general, .features, .updates]),
         ("Business setup", [.business, .rates, .pricing]),
         ("Client documents", [.templates, .terms, .electronic]),
         ("Library and tools", [.library, .localAI])]
    }

    @State private var section = Section.general

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(navigationGroups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(group.0))
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 9)
                            ForEach(group.1.filter { visibleSections.contains($0) }, id: \.self) { item in
                                Button { section = item } label: {
                                    Label(LocalizedStringKey(item.rawValue), systemImage: item.icon)
                                        .font(.callout.weight(section == item ? .semibold : .regular))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 9).padding(.vertical, 6)
                                        .background(section == item ? Color.accentColor.opacity(0.12) : .clear,
                                                    in: RoundedRectangle(cornerRadius: 7))
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(section == item ? .isSelected : [])
                            }
                        }
                    }
                }.padding(12)
            }.frame(width: 196)
                .background(.bar)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringKey(section.rawValue)).font(.title2.bold())
                if section == .templates || section == .terms {
                    HSplitView {
                        settingsForm.frame(minWidth: 280, idealWidth: 430)
                        documentPreview.frame(minWidth: 230, idealWidth: 390)
                    }
                } else {
                    settingsForm.frame(maxWidth: 610, alignment: .leading)
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(minWidth: 790, idealWidth: 1100, maxWidth: .infinity,
                minHeight: 480, idealHeight: 710, maxHeight: .infinity)
        .environment(\.usageFeatures, profile.features)
        .background(SettingsLineBreaks())
        .sheet(item: $demo) { presentation in
            DemoLibraryView(startTour: presentation == .tour).environment(\.locale, locale)
        }
        .onChange(of: section) { _, _ in refresh() }
        .onAppear {
            if !profile.features.integrations { mcpEnabled = false }
            if localAISettingsRequested { section = .localAI; localAISettingsRequested = false }
            refresh()
        }
        .onChange(of: localAISettingsRequested) { _, requested in
            if requested { section = .localAI; localAISettingsRequested = false }
        }
        .onChange(of: profile) { _, updated in
            if !updated.features.integrations { mcpEnabled = false }
            if !visibleSections.contains(section) { section = .features }
            do { try updated.save(); refresh() } catch { self.error = error.localizedDescription }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cooolLibraryDidRestore)) { _ in profile = BusinessProfile.load(); refresh() }
        .onChange(of: invoice) { refresh() }
        .onChange(of: german) { refresh() }
    }
    private var visibleSections: [Section] {
        Section.allCases.filter {
            ($0 != .electronic || profile.features.advancedBilling) && ($0 != .updates || AppUpdates.shared != nil)
        }
    }

    private var settingsForm: some View {
        Form {
            switch section {
            case .localAI:
                LocalAISettingsView()
            case .features:
                UsageFeaturesSettings(features: Binding(get: { profile.features }, set: { profile.usageFeatures = $0 }))
            case .general:
                Picker("App language", selection: $appLanguage) {
                    Text("System").tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "Deutsch").tag(AppLanguage.german)
                }
                Picker("Default document language", selection: $documentLanguage) {
                    Text(verbatim: "Deutsch").tag(AppLanguage.german)
                    Text(verbatim: "English").tag(AppLanguage.english)
                }
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag(AppAppearance.system)
                    Text("Light").tag(AppAppearance.light)
                    Text("Dark").tag(AppAppearance.dark)
                }
                SwiftUI.Section("Project editing") {
                    Toggle("Save project edits automatically", isOn: $projectAutosave)
                    Text("When disabled, use Save Project Edits or Command-S. Other library actions still save immediately.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                SwiftUI.Section("Getting started") {
                    Button("Explore demo library…", systemImage: "sparkles") { demo = .library }
                    Button("Start guided tour…", systemImage: "play.circle") { demo = .tour }
                    Button("Open setup…") {
                        onboardingRequested = true
                        openWindow(id: "library")
                    }
                }
            case .business:
                SwiftUI.Section("Business identity") {
                    TextField("Business name", text: $profile.name)
                    TextField("City on letters", text: $profile.city)
                    RichField("Address and contact", text: $profile.contact, height: 88)
                }
                SwiftUI.Section("Bank and tax details") {
                    RichField("Bank details", text: $profile.bank, height: 70)
                    TextField("Tax number", text: $profile.taxNumber)
                    TextField("VAT ID", text: $profile.vatID)
                    TextField("Default VAT exemption reason", text: Binding(get: { profile.defaultExemptionReason ?? "" }, set: { profile.defaultExemptionReason = $0 }), axis: .vertical)
                    Stepper("Default VAT · \(profile.vat)%", value: $profile.vat, in: 0...100)
                }
                SwiftUI.Section("Client defaults") { ClientDefaultsFields(profile: $profile) }
            case .rates:
                DayRateSettings()
            case .pricing:
                PricingCategorySettings()
            case .templates:
                Button("Choose letterhead logo…", action: chooseLogo)
                if profile.logo != nil { Button("Remove logo") { profile.logo = nil } }
                fontPicker("Proposal font", $profile.proposalFont)
                fontPicker("Invoice font", $profile.invoiceFont)
                Toggle("Detailed proposal with phase fees", isOn: $profile.detailed)
                    .help("Show a separate scope block and fee for each production phase in proposals.")
                designControls
                templateControls
            case .terms:
                termsControls
                RichField("German terms (AGB)", text: $profile.termsDE, height: 130)
                RichField("English terms", text: $profile.termsEN, height: 130)
            case .electronic:
                electronicSettings
            case .updates:
                AppUpdateSettings()
            case .library:
                Toggle("Require Touch ID or Mac password on launch", isOn: Binding(get: { requireLaunchAuthentication }, set: { enabled in
                    changingLock = true
                    Task {
                        defer { changingLock = false }
                        do {
                            try await DeviceAuthentication.confirm("Change the Coool PM launch lock.")
                            try LibraryKey.setLaunchLock(enabled)
                            requireLaunchAuthentication = enabled
                        } catch { self.error = error.localizedDescription }
                    }
                })).disabled(changingLock)
                LabeledContent("Storage") { Text(CloudLibrarySync.isConfigured ? "Private iCloud available" : "Local library") }
                Picker("Backup reminder on close", selection: $backupReminderDays) {
                    ForEach(BackupReminder.dayOptions, id: \.self) { days in
                        if days == 0 { Text("Never").tag(days) }
                        else if days == 1 { Text("After 1 day").tag(days) }
                        else { Text("After \(days) days").tag(days) }
                    }
                }
                .help("Remind me when my recovery copy is out of date and I have not backed up within this interval.")
                Button("Manage backups and sync…") {
                    libraryBackupRequested = true
                    openWindow(id: "library")
                }
                if profile.features.integrations, let executable = Bundle.main.url(forAuxiliaryExecutable: "CooolPM-MCP") {
                    SwiftUI.Section("AI connection (MCP)") {
                        Toggle("Enable local MCP connection", isOn: $mcpEnabled)
                        Text("MCP shares anonymous client and project aliases. Real names, numbers and custom phase or entry labels stay on this Mac.")
                            .font(.callout).foregroundStyle(.secondary)
                        Toggle("Allow draft edits", isOn: $includeMCPWrites)
                            .help("Includes permission to create clients and projects and edit unapproved draft calculations.")
                        Toggle("Share financial totals", isOn: $includeMCPFinancials)
                            .help("Includes permission to read project financials and business reports.")
                        Button(copiedMCPConfiguration ? "Configuration copied" : "Copy MCP configuration",
                               systemImage: copiedMCPConfiguration ? "checkmark" : "doc.on.doc") {
                            copyMCPConfiguration(executable: executable)
                        }.disabled(!mcpEnabled)
                    }
                }
                SwiftUI.Section {
                    Button("Reset options…", role: .destructive) {
                        libraryResetRequested = true
                        openWindow(id: "library")
                    }
                    .tint(.red)
                    .help("Create a recovery backup before resetting the local library or the entire app.")
                }
            }
        }.formStyle(.grouped).textFieldStyle(.roundedBorder)
    }

    private var electronic: Binding<ElectronicInvoiceDefaults> {
        Binding(get: { profile.electronicInvoice ?? ElectronicInvoiceDefaults() },
                set: { profile.electronicInvoice = $0 })
    }

    private var electronicSettings: some View {
        Group {
            SwiftUI.Section("Seller defaults") {
                Text("These fields prefill new XRechnung exports. Set buyer details and references in the client directory.")
                    .font(.callout).foregroundStyle(.secondary)
                ElectronicPartyFields(party: electronic.seller, seller: true, includeName: false)
                TextField("IBAN", text: electronic.iban)
            }
            SwiftUI.Section("KoSIT validator") {
                Text("Leave paths blank to use the standard XRechnung folder in Application Support.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("Java executable path", text: $xrechnungJavaPath)
                TextField("Validator JAR path", text: $xrechnungValidatorPath)
                TextField("Rules scenarios.xml path", text: $xrechnungRulesPath)
                Label(XRechnungValidator.installed.available ? "Validator available" : "Validator files missing",
                      systemImage: XRechnungValidator.installed.available ? "checkmark.circle" : "exclamationmark.circle")
            }
        }
    }

    private func copyMCPConfiguration(executable: URL) {
        var server: [String: Any] = ["command": executable.path]
        let arguments = [includeMCPWrites ? "--allow-write" : nil, includeMCPFinancials ? "--allow-financials" : nil].compactMap { $0 }
        if !arguments.isEmpty { server["args"] = arguments }
        let configuration = ["mcpServers": ["coool-pm": server]]
        do {
            let data = try JSONSerialization.data(withJSONObject: configuration,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            NSPasteboard.general.clearContents()
            copiedMCPConfiguration = NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var templateControls: some View {
        DisclosureGroup("Advanced Word / Pages templates") {
            Text("Choose the document and language on the right. Edit the starter in Word or Pages, keep the {{fields}}, then import the DOCX. In Pages, use File → Export To → Word.").font(.callout)
            Button(customInstalled ? "Save editable template…" : "Save starter template…") { templateAction(importing: false) }
            DisclosureGroup("Available merge fields") {
                Text("{{document_title}}  {{milestone}}  {{project}}  {{number}}  {{date}}  {{period}}  {{scope}}\n{{client}}  {{client_number}}  {{client_contact}}  {{address}}\n{{business}}  {{city}}  {{contact}}  {{bank}}  {{tax_number}}  {{vat_id}}\n{{purchase_order}}  {{invoice_positions}}\n{{net}}  {{vat_rate}}  {{vat}}  {{total}}  {{payment}}  {{terms}}  {{options}}  {{vat_exemption}}")
                    .font(.caption).textSelection(.enabled)
                Text("A paragraph or table row containing {{phase}}, {{phase_fee}}, or {{phase_items}} repeats for each phase.")
                    .font(.caption).textSelection(.enabled)
            }
            Button("Import DOCX template…") { templateAction(importing: true) }
            if customInstalled {
                Button("Use built-in layout") {
                    do { try FileManager.default.removeItem(at: template.url); refresh() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
    }

    private var documentPreview: some View {
        VStack {
            HStack {
                Picker("Preview", selection: $invoice) {
                    Text("Proposal").tag(false)
                    Text("Invoice").tag(true)
                }.labelsHidden()
                Picker("Language", selection: $german) {
                    Text("DE").tag(true)
                    Text("EN").tag(false)
                }.labelsHidden()
            }.padding(.horizontal)
            if customInstalled {
                Spacer()
                Text("Custom DOCX template").font(.headline)
                Button("Open filled sample…") { openSample() }
                Spacer()
            } else { SettingsPreview(document: preview) }
        }.padding(.leading, 10)
    }

    private var previewBilling: BillingSchedule {
        BillingSchedule(days: 14, stages: [BillingMilestone(percent: 50, name: "Project start"),
                                          BillingMilestone(percent: 50, name: "Delivery")])
    }
    private var template: WordTemplate {
        var doc = ClientDocument(german: german, invoice: invoice)
        profile.apply(to: &doc)
        doc.rateTerms = RateTerms(Estimate())
        doc.billingPlan = previewBilling
        doc.reference = "2026-01"
        doc.vat = Decimal(profile.vat)
        return WordTemplate(document: doc)
    }
    private func sample(from url: URL) throws -> Data {
        var document = ClientDocument(german: german, invoice: invoice)
        document.sender = "Example Studio"
        document.contactDetails = "studio@example.com"
        document.rateTerms = RateTerms(Estimate())
        document.billingPlan = previewBilling
        document.reference = "2026-01"
        return try WordTemplate(document: document).render(source: url, project: german ? "Beispielproduktion" : "Sample production",
                            client: Client(number: "0001", name: "Studio"),
                            fees: [PhaseFee(name: "Production", amount: 1500, items: [])])
    }
    private func templateAction(importing: Bool) {
        let type = UTType(filenameExtension: "docx")!
        do {
            if importing {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [type]
                guard panel.runModal() == .OK, let source = panel.url else { return }
                let data = try Data(contentsOf: source)
                _ = try sample(from: source)
                try FileManager.default.createDirectory(at: template.folder, withIntermediateDirectories: true)
                try data.write(to: template.url, options: .atomic)
            } else {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [type]
                panel.nameFieldStringValue = template.key + ".docx"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                let data = try customInstalled ? Data(contentsOf: template.url) : template.starter()
                try data.write(to: url, options: .atomic)
            }
            refresh()
        } catch { self.error = error.localizedDescription }
    }
    private func openSample() {
        do {
            let fm = FileManager.default
            let folder = fm.temporaryDirectory.appendingPathComponent("coool-template-sample-" + UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            do {
                let file = folder.appendingPathComponent("Sample.docx")
                try sample(from: template.url).write(to: file, options: .atomic)
                guard NSWorkspace.shared.open(file) else {
                    throw LibraryError(description: "The sample could not be opened.")
                }
                BackupQuitDelegate.templateSampleFolders.append(folder)
            } catch {
                try? fm.removeItem(at: folder)
                throw error
            }
        } catch { self.error = error.localizedDescription }
    }
    private var design: Binding<DocumentStyle> {
        Binding(get: { profile.styling ?? DocumentStyle() }, set: { profile.styling = $0 })
    }
    private func roleFont(_ title: String, _ binding: Binding<LetterFont?>) -> some View {
        Picker(title, selection: binding) {
            Text("Document font").tag(Optional<LetterFont>.none)
            ForEach(LetterFont.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
        }
    }
    private var designControls: some View {
        Group {
            DisclosureGroup("First-page header") {
                Picker("Layout", selection: design.header) {
                    ForEach(["Brand and contact", "Text only", "Hidden"], id: \.self) { Text($0) }
                }
                RichField("Custom header text", text: design.headerText)
                roleFont("Header font", design.headerFont)
            }
            DisclosureGroup("Footer") {
                Toggle("Custom footer columns", isOn: design.customFooter)
                    .help("Use your own text in the left, center and right footer columns.")
                if design.wrappedValue.customFooter {
                    RichField("Left", text: design.leftFooter)
                    RichField("Middle", text: design.middleFooter)
                    RichField("Right", text: design.rightFooter)
                }
                Toggle("Show page numbers", isOn: design.pageNumbers)
                    .help("Print the page number in the footer of each document page.")
                roleFont("Footer font", design.footerFont)
            }
            DisclosureGroup("Project phases") {
                Picker("Heading style", selection: design.phase) {
                    ForEach(["Shaded band", "Underline", "Plain"], id: \.self) { Text($0) }
                }
                Toggle("Uppercase headings", isOn: design.uppercase)
                    .help("Display proposal phase headings in uppercase.")
                Stepper("Heading size · \(design.wrappedValue.phaseSize) pt", value: design.phaseSize, in: 9...22)
                roleFont("Heading font", design.phaseFont)
            }
            Stepper("Body size · \(design.wrappedValue.bodySize) pt", value: design.bodySize, in: 9...16)
            Text("Fonts installed in Font Book are available here.").font(.caption)
        }
    }
    private var termsControls: some View {
        Group {
            Toggle("Two-column terms pages", isOn: design.twoColumns)
                .help("Lay out the terms on their own pages in two columns.")
            Stepper("Terms size · \(design.wrappedValue.termsSize) pt", value: design.termsSize, in: 8...16)
            roleFont("Terms font", design.termsFont)
            HStack {
                Button("Insert payment terms") { insertTerm("{{payment}}") }
                Button("Insert producer rates") { insertTerm("{{day_rates}}") }
            }
            Text("Fields are appended to the selected preview language and filled from each project.").font(.caption)
        }
    }
    private func insertTerm(_ token: String) {
        if german { profile.termsDE += (profile.termsDE.isEmpty ? "" : "\n") + token }
        else { profile.termsEN += (profile.termsEN.isEmpty ? "" : "\n") + token }
    }

    private func fontPicker(_ label: String, _ selection: Binding<LetterFont>) -> some View {
        Picker(label, selection: selection) { ForEach(LetterFont.allCases, id: \.self) { Text($0.rawValue) } }
    }
    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1200, kCGImageSourceCreateThumbnailWithTransform: true]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            error = "This image could not be loaded."; return
        }
        profile.logo = data
    }
    private func refresh() {
        guard section == .templates || section == .terms else { return }
        customInstalled = template.installed
        var doc = ClientDocument(german: german, invoice: invoice)
        doc.reference = "2026-01"
        doc.vat = Decimal(profile.vat)
        doc.detailed = profile.detailed
        doc.servicePeriod = "11/2026"
        profile.apply(to: &doc)
        doc.rateTerms = RateTerms(Estimate())
        doc.billingPlan = previewBilling
        let recipient = Client(number: "0001", name: doc.label("Musteragentur", "Example Agency"))
        let layout = doc.contents(project: doc.label("Beispielproduktion", "Sample production"), recipient: recipient,
                                  fees: [PhaseFee(name: "Production", amount: 1500, items: [])])
        do { preview = PDFDocument(data: try layout.pdfData()); error = "" }
        catch { self.error = error.localizedDescription }
    }
}

struct SettingsPreview: NSViewRepresentable {
    let document: PDFDocument?
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        guard view.document !== document else { return }
        let index = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
        view.document = document
        if let doc = document, doc.pageCount > 0, let page = doc.page(at: min(index, doc.pageCount - 1)) { view.go(to: page) }
    }
}
