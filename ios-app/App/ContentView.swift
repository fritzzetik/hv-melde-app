import HVMeldeCore
import MessageUI
import SwiftUI
@preconcurrency import Translation

private enum AppTab: Hashable {
    case home, report, cases, settings
}

struct ContentView: View {
    @EnvironmentObject private var store: AppDataStore
    @AppStorage("hasCompletedOnboardingV2") private var hasCompletedOnboarding = false
    @State private var selectedTab: AppTab = .home
    @State private var pendingTab: AppTab?
    @State private var showsLeaveWarning = false
    @State private var hasUnsavedDraft = false
    @State private var showsOnboarding = false

    var body: some View {
        TabView(selection: tabSelection) {
            NavigationStack {
                HomeDashboardView(
                    openReport: { selectedTab = .report },
                    openCases: { selectedTab = .cases },
                    openSettings: { selectedTab = .settings }
                )
            }
            .tabItem { Label("Start", systemImage: "house") }
            .tag(AppTab.home)

            NewReportView(hasUnsavedDraft: $hasUnsavedDraft)
                .tabItem { Label("Meldung", systemImage: "square.and.pencil") }
                .tag(AppTab.report)

            NavigationStack { ReportedCasesView() }
                .tabItem { Label("Fälle", systemImage: "tray.full") }
                .badge(
                    store.state.reportedCases.filter { $0.status == .open }.count
                        + store.state.noiseProtocols.filter { $0.status == .open }.count
                )
                .tag(AppTab.cases)

            NavigationStack {
                SettingsView(showOnboarding: { showsOnboarding = true })
            }
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .onAppear {
            hasUnsavedDraft = store.incidentDraft != nil
            if !hasCompletedOnboarding { showsOnboarding = true }
        }
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingView(
                onSkip: {
                    hasCompletedOnboarding = true
                    showsOnboarding = false
                },
                onStartSetup: {
                    hasCompletedOnboarding = true
                    showsOnboarding = false
                    selectedTab = .settings
                }
            )
        }
        .alert("Meldung verlassen?", isPresented: $showsLeaveWarning) {
            Button("Entwurf behalten und verlassen") {
                if let pendingTab { selectedTab = pendingTab }
                pendingTab = nil
            }
            Button("Weiter bearbeiten", role: .cancel) { pendingTab = nil }
        } message: {
            Text("Die begonnenen Angaben und Fotos bleiben als lokaler Entwurf gespeichert.")
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                guard selectedTab == .report, newTab != .report, hasUnsavedDraft else {
                    selectedTab = newTab
                    return
                }
                pendingTab = newTab
                showsLeaveWarning = true
            }
        )
    }
}

private struct NewReportView: View {
    @EnvironmentObject private var store: AppDataStore
    @Binding var hasUnsavedDraft: Bool
    @State private var reportID = UUID()
    @State private var reportCreatedAt = Date()
    @State private var selectedPropertyID: UUID?
    @State private var category: ReportCategory = .unauthorizedVehicle
    @State private var incidentAt = Date()
    @State private var garageLocation = ""
    @State private var isCommonArea = false
    @State private var licensePlate = ""
    @State private var vehicleDescription = ""
    @State private var violation = "Dauerparken"
    @State private var notes = ""
    @State private var witnesses = ""
    @State private var requestsManagementResponse = true
    @State private var allowsNameDisclosure = false
    @State private var evidencePhotos: [EvidencePhoto] = []
    @State private var analysisReviewTarget: ImageAnalysisReviewTarget?
    @State private var generatedPDF: URL?
    @State private var generatedTechnicalJSON: URL?
    @State private var mailDraft: MailDraft?
    @State private var errorMessage: String?
    @State private var didRestoreDraft = false
    @State private var currentStep: ReportStep = .object
    @State private var showsCancelConfirmation = false
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var isGeneratingPDF = false
    @State private var translationProgressText: String?
    @State private var translatedTextReview: PDFReportRenderer.ReportTextTranslation?
    @State private var showsTranslationReview = false
    @State private var translationFailureMessage: String?
    @State private var translationRequestID: UUID?
    @State private var activeTranslationSession: TranslationSession?

    var body: some View {
        reportDialogs
            .translationTask(translationConfiguration) { session in
                await translateAndGeneratePDF(using: session)
            }
    }

    private var reportDialogs: some View {
        reportSheets
            .alert("Meldung konnte nicht gespeichert werden", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? store.lastError ?? "Unbekannter Fehler")
            }
            .confirmationDialog(
                "Meldung abbrechen?",
                isPresented: $showsCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Entwurf und Fotos löschen", role: .destructive) {
                    cancelDraft()
                }
                Button("Weiter bearbeiten", role: .cancel) {}
            } message: {
                Text("Alle noch nicht als Fall gespeicherten Angaben und Beweisfotos dieser Meldung werden entfernt.")
            }
            .confirmationDialog(
                "Lokale Übersetzung nicht verfügbar",
                isPresented: translationFailureIsPresented,
                titleVisibility: .visible
            ) {
                Button("PDF stattdessen auf Deutsch erstellen") {
                    generateGermanFallbackPDF()
                }
                Button("Übersetzung erneut versuchen") {
                    translationFailureMessage = nil
                    startPDFGeneration()
                }
                Button("Abbrechen", role: .cancel) {
                    cancelTranslation()
                }
            } message: {
                Text(translationFailureMessage ?? "Das benötigte Sprachmodell ist auf diesem Gerät nicht verfügbar.")
            }
    }

    private var reportSheets: some View {
        reportNavigation
            .sheet(item: $mailDraft) { draft in
                MailComposerView(draft: draft)
            }
            .sheet(item: $analysisReviewTarget) { target in
                ImageAnalysisReviewView(
                    analysis: target.analysis,
                    currentLicensePlate: licensePlate,
                    currentVehicleDescription: vehicleDescription
                ) { confirmedPlate, confirmedVehicle, confirmedSummary in
                    applyAnalysisConfirmation(
                        target.analysis,
                        photoID: target.photoID,
                        plate: confirmedPlate,
                        vehicle: confirmedVehicle,
                        summary: confirmedSummary
                    )
                }
            }
            .sheet(isPresented: $showsTranslationReview, onDismiss: {
                if translatedTextReview != nil { cancelTranslation() }
                translatedTextReview = nil
            }) {
                if let translatedTextReview {
                    TranslationReviewView(
                        originalText: reportTextForTranslation,
                        initialTranslation: translatedTextReview
                    ) { confirmedTranslation in
                        self.translatedTextReview = nil
                        showsTranslationReview = false
                        generatePDF(translatedText: confirmedTranslation)
                    }
                }
            }
    }

    private var reportNavigation: some View {
        NavigationStack {
            reportForm
            .navigationTitle("Neue Meldung")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if hasUnsavedDraft {
                        Button("Abbrechen", role: .destructive) {
                            showsCancelConfirmation = true
                        }
                    }
                }
            }
            .onAppear(perform: restoreDraftIfNeeded)
            .onChange(of: store.state.properties) { _, _ in selectFirstPropertyIfNeeded() }
            .onChange(of: selectedPropertyID) { _, _ in generatedPDF = nil }
            .onChange(of: evidencePhotos.map(\.id)) { previousIDs, _ in
                generatedPDF = nil
                guard previousIDs.isEmpty,
                      let capturedAt = evidencePhotos.first?.imageTimestamp.capturedAt else { return }
                incidentAt = capturedAt
            }
            .onChange(of: store.state.preferences.technicalAttachmentMode) { _, _ in
                generatedPDF = nil
                generatedTechnicalJSON = nil
            }
            .onChange(of: currentDraft) { _, draft in
                guard didRestoreDraft else { return }
                store.saveDraft(draft)
                hasUnsavedDraft = draft.hasMeaningfulContent
            }
        }
    }

    private var reportForm: some View {
        Form {
            Section {
                ProgressView(
                    value: Double(currentStep.rawValue + 1),
                    total: Double(ReportStep.allCases.count)
                )
                Text("Schritt \(currentStep.rawValue + 1) von \(ReportStep.allCases.count): \(currentStep.title)")
                    .font(.subheadline.bold())
            }
            currentStepContent
            stepNavigationSection
        }
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch currentStep {
        case .object:
            objectStep
        case .incident:
            incidentStep
        case .photos:
            PhotoAnalysisSection(
                reportID: reportID,
                category: category,
                evidencePhotos: $evidencePhotos,
                reviewTarget: $analysisReviewTarget
            )
            .id(reportID)
        case .review:
            reviewStep
        }
    }

    private var selectedProperty: ManagedProperty? {
        guard let selectedPropertyID else { return nil }
        return store.state.properties.first { $0.id == selectedPropertyID }
    }

    private var selectableCategories: [ReportCategory] {
        var categories = store.activeReportCategories
        if !categories.contains(where: { $0.id == category.id }) {
            categories.append(category)
        }
        return categories
    }

    @ViewBuilder
    private var stepNavigationSection: some View {
        Section {
            HStack {
                if currentStep != .object {
                    Button("Zurück") { moveStep(by: -1) }
                }
                Spacer()
                if currentStep != .review {
                    Button("Weiter") { moveStep(by: 1) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canContinue)
                }
            }
        }
    }

    @ViewBuilder
    private var objectStep: some View {
        Section("Meldekategorie") {
            Picker(selection: selectedCategoryID) {
                ForEach(selectableCategories) { category in
                    Text(category.rawValue).tag(category.id)
                }
            } label: {
                requiredFieldLabel("Kategorie")
            }
            if category.id == ReportCategory.noise.id {
                NavigationLink {
                    NoiseProtocolsView()
                } label: {
                    Label("Stattdessen fortlaufendes Lärmprotokoll führen", systemImage: "waveform.badge.plus")
                }
                Text("Für wiederkehrende Ruhestörungen über mehrere Tage oder Monate ist das Lärmprotokoll vorgesehen. Eine einmalige Meldung kannst du hier weiterhin erstellen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section("Objekt") {
            if store.state.properties.isEmpty {
                ContentUnavailableView(
                    "Noch kein Objekt",
                    systemImage: "building.2",
                    description: Text("Lege zuerst in den Einstellungen ein Objekt an.")
                )
            } else {
                Picker(selection: $selectedPropertyID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(store.state.properties) { property in
                        Text(property.displayName).tag(Optional(property.id))
                    }
                } label: {
                    requiredFieldLabel("Objekt")
                }
                if selectedProperty == nil {
                    requiredFieldMessage("Bitte ein Objekt auswählen.")
                }
                if let selectedProperty {
                    LabeledContent("Objekttyp", value: selectedProperty.propertyType.rawValue)
                    if !selectedProperty.officialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        LabeledContent("Offizielle Bezeichnung", value: selectedProperty.officialName)
                    }
                    Toggle("Betrifft eine Allgemeinfläche", isOn: $isCommonArea)
                    Text(reportScopeDescription(for: selectedProperty))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var selectedCategoryID: Binding<String> {
        Binding(
            get: { category.id },
            set: { id in
                guard let selected = selectableCategories.first(where: { $0.id == id }) else { return }
                selectCategory(selected)
            }
        )
    }

    @ViewBuilder
    private var incidentStep: some View {
        Section("Ort und Zeitpunkt") {
            requiredTextField("Bereich oder Ort im Objekt", text: $garageLocation)
            DatePicker("Beobachtet am", selection: $incidentAt)
        }
        Section {
            if category.expectsVehicle {
                requiredTextField("Kennzeichen", text: $licensePlate)
                    .textInputAutocapitalization(.characters)
                TextField("Fahrzeugbeschreibung (optional)", text: $vehicleDescription)
            }
            requiredTextField("Meldegrund", text: $violation)
            TextField("Sachliche Beschreibung (optional)", text: $notes, axis: .vertical)
                .lineLimit(3...8)
            TextField("Zeugen (optional)", text: $witnesses)
        } header: {
            Text(category.expectsVehicle ? "Fahrzeug und Vorfall" : "Vorfall")
        } footer: {
            Text("Mit * gekennzeichnete Felder sind Pflichtfelder.")
        }
        Section("Rückmeldung und Vertraulichkeit") {
            Toggle("Rückmeldung der Hausverwaltung erwünscht", isOn: $requestsManagementResponse)
            Toggle("Mein Name darf dem Verursacher mitgeteilt werden", isOn: $allowsNameDisclosure)
            Text("Die Auswahl wird deutlich im Schreiben an die Hausverwaltung angeführt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var reviewStep: some View {
        if !missingRequiredFields.isEmpty {
            Section("Fehlende Pflichtfelder") {
                ForEach(missingRequiredFields, id: \.rawValue) { field in
                    Label(fieldLabel(field), systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        Section("Zusammenfassung") {
            LabeledContent("Objekt", value: selectedProperty?.officialDisplayName ?? "Nicht gewählt")
            LabeledContent("Kategorie", value: category.rawValue)
            LabeledContent("Bereich", value: garageLocation)
            LabeledContent("Meldegrund", value: violation)
            LabeledContent("Beweisfotos", value: "\(evidencePhotos.count)")
            LabeledContent("Rückmeldung erwünscht", value: requestsManagementResponse ? "Ja" : "Nein")
            LabeledContent("Namensweitergabe erlaubt", value: allowsNameDisclosure ? "Ja" : "Nein")
        }
        Section {
            Button(action: startPDFGeneration) {
                if isGeneratingPDF {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            ProgressView()
                            Text("PDF wird erstellt …")
                        }
                        if let translationProgressText {
                            Text(translationProgressText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("PDF erzeugen")
                }
            }
                .disabled(!missingRequiredFields.isEmpty || isGeneratingPDF)
            if isGeneratingPDF {
                Button("PDF stattdessen auf Deutsch erstellen") {
                    generateGermanFallbackPDF()
                }
                Button("Übersetzung abbrechen", role: .cancel) {
                    cancelTranslation()
                }
            }
            if let generatedPDF {
                Label("Fall wurde lokal gespeichert", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let recipient = selectedProperty?.reportEmail.nonEmpty {
                    Button {
                        prepareMail(pdfURL: generatedPDF, recipient: recipient)
                    } label: {
                        Label("PDF per E-Mail senden", systemImage: "envelope")
                    }
                    .disabled(!MFMailComposeViewController.canSendMail())
                }
                ShareLink(item: generatedPDF) {
                    Label("PDF anderweitig teilen", systemImage: "square.and.arrow.up")
                }
                Button("Neue Meldung beginnen", action: resetReport)
            }
        } footer: {
            Text("Die App überträgt keine Daten automatisch. Der Versand erfolgt erst nach deiner Bestätigung im Mailfenster.")
        }
    }

    private var canContinue: Bool {
        missingRequiredFields(for: currentStep).isEmpty
    }

    private func moveStep(by offset: Int) {
        let rawValue = min(max(currentStep.rawValue + offset, 0), ReportStep.allCases.count - 1)
        if let step = ReportStep(rawValue: rawValue) { currentStep = step }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil || store.lastError != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                    store.clearError()
                }
            }
        )
    }

    private var translationFailureIsPresented: Binding<Bool> {
        Binding(
            get: { translationFailureMessage != nil },
            set: {
                if !$0 { translationFailureMessage = nil }
            }
        )
    }

    private func selectFirstPropertyIfNeeded() {
        if let selectedPropertyID,
           store.state.properties.contains(where: { $0.id == selectedPropertyID }) {
            return
        }
        selectedPropertyID = store.state.properties.first?.id
    }

    private func selectCategory(_ selected: ReportCategory) {
        category = selected
        violation = selected.defaultViolation
        generatedPDF = nil
        if !selected.expectsVehicle {
            licensePlate = ""
            vehicleDescription = ""
        }
    }

    private var missingRequiredFields: [IncidentReportField] {
        var fields: [IncidentReportField] = []
        if selectedProperty == nil {
            fields.append(.propertyName)
        }
        if garageLocation.trimmedIsEmpty {
            fields.append(.garageLocation)
        }
        if category.expectsVehicle && licensePlate.trimmedIsEmpty {
            fields.append(.licensePlate)
        }
        if violation.trimmedIsEmpty {
            fields.append(.violation)
        }
        return fields
    }

    private func missingRequiredFields(for step: ReportStep) -> [IncidentReportField] {
        switch step {
        case .object:
            missingRequiredFields.filter { $0 == .propertyName }
        case .incident:
            missingRequiredFields.filter { $0 != .propertyName }
        case .photos, .review:
            []
        }
    }

    @ViewBuilder
    private func requiredTextField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            requiredFieldLabel(title)
            TextField(title, text: text)
            if text.wrappedValue.trimmedIsEmpty {
                requiredFieldMessage("Bitte ausfüllen.")
            }
        }
    }

    private func requiredFieldLabel(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 2) {
            Text(title)
            Text("*")
                .foregroundStyle(.red)
                .accessibilityLabel("Pflichtfeld")
        }
    }

    private func requiredFieldMessage(_ message: LocalizedStringKey) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.red)
    }

    private func startPDFGeneration() {
        guard let property = selectedProperty else {
            errorMessage = "Bitte lege ein Objekt an und wähle es aus."
            return
        }
        let language = store.management(for: property)?.reportLanguage ?? .german
        guard let targetCode = language.targetLanguageCode else {
            generatePDF(translatedText: nil)
            return
        }

        cancelTranslation()
        let requestID = UUID()
        translationRequestID = requestID
        isGeneratingPDF = true
        translationProgressText = "Verfügbarkeit der lokalen Übersetzung wird geprüft …"
        errorMessage = nil
        translationFailureMessage = nil
        translatedTextReview = nil

        Task { @MainActor in
            let source = Locale.Language(identifier: "de")
            let target = Locale.Language(identifier: targetCode)
            let status = await LanguageAvailability().status(from: source, to: target)
            guard translationRequestID == requestID else { return }

            switch status {
            case .installed:
                translationProgressText = "Freitexte werden lokal übersetzt …"
            case .supported:
                translationProgressText = "Sprachmodell wird vorbereitet oder geladen …"
            case .unsupported:
                failTranslation("Die gewählte Sprachkombination wird auf diesem Gerät nicht unterstützt.")
                return
            @unknown default:
                failTranslation("Die Verfügbarkeit der lokalen Übersetzung konnte nicht bestimmt werden.")
                return
            }

            let configuration = TranslationSession.Configuration(source: source, target: target)
            if translationConfiguration == configuration {
                translationConfiguration?.invalidate()
            } else {
                translationConfiguration = configuration
            }
        }
    }

    private func translateAndGeneratePDF(using session: TranslationSession) async {
        guard let requestID = translationRequestID else { return }
        activeTranslationSession = session
        do {
            try await session.prepareTranslation()
            guard translationRequestID == requestID else { return }
            translationProgressText = "Freitexte werden lokal übersetzt …"
            let translatedText = try await translateReportText(using: session)
            guard translationRequestID == requestID else { return }
            translationProgressText = nil
            activeTranslationSession = nil
            translatedTextReview = translatedText
            showsTranslationReview = true
        } catch {
            guard translationRequestID == requestID else { return }
            failTranslation("Die lokale Übersetzung konnte nicht erstellt werden: \(error.localizedDescription)")
        }
    }

    private func failTranslation(_ message: String) {
        activeTranslationSession?.cancel()
        activeTranslationSession = nil
        translationRequestID = nil
        translationConfiguration = nil
        translationProgressText = nil
        isGeneratingPDF = false
        translationFailureMessage = message
    }

    private func cancelTranslation() {
        activeTranslationSession?.cancel()
        activeTranslationSession = nil
        translationRequestID = nil
        translationConfiguration = nil
        translationProgressText = nil
        translationFailureMessage = nil
        isGeneratingPDF = false
    }

    private func generateGermanFallbackPDF() {
        cancelTranslation()
        generatePDF(translatedText: nil, reportLanguageOverride: .german)
    }

    private func translateReportText(using session: TranslationSession) async throws -> PDFReportRenderer.ReportTextTranslation {
        return PDFReportRenderer.ReportTextTranslation(
            location: try await translate(garageLocation, using: session),
            violation: try await translate(violation, using: session),
            notes: try await translate(notes, using: session),
            vehicleDescription: try await translate(vehicleDescription, using: session),
            witnesses: try await translate(witnesses, using: session)
        )
    }

    private var reportTextForTranslation: PDFReportRenderer.ReportTextTranslation {
        PDFReportRenderer.ReportTextTranslation(
            location: garageLocation,
            violation: violation,
            notes: notes,
            vehicleDescription: vehicleDescription,
            witnesses: witnesses
        )
    }

    private func translate(_ text: String, using session: TranslationSession) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        return try await session.translate(text).targetText
    }

    private func generatePDF(
        translatedText: PDFReportRenderer.ReportTextTranslation?,
        reportLanguageOverride: ReportLanguage? = nil
    ) {
        activeTranslationSession?.cancel()
        activeTranslationSession = nil
        translationRequestID = nil
        translationConfiguration = nil
        translationProgressText = nil

        guard let property = selectedProperty else {
            errorMessage = "Bitte lege ein Objekt an und wähle es aus."
            isGeneratingPDF = false
            return
        }

        let report = IncidentReport(
            id: reportID,
            createdAt: reportCreatedAt,
            incidentAt: incidentAt,
            propertyName: property.displayName,
            garageLocation: garageLocation,
            licensePlate: licensePlate,
            vehicleDescription: vehicleDescription,
            violation: violation,
            notes: notes,
            witnesses: witnesses,
            isCommonArea: isCommonArea,
            category: category,
            requestsManagementResponse: requestsManagementResponse,
            allowsNameDisclosure: allowsNameDisclosure
        )

        do {
            try IncidentReportValidator.validate(report)
            var reportManagement = store.management(for: property)
            if let reportLanguageOverride {
                reportManagement?.reportLanguage = reportLanguageOverride
            }
            let temporaryPDF = try PDFReportRenderer.render(
                report,
                profile: store.state.profile,
                property: property,
                management: reportManagement,
                evidencePhotos: evidencePhotos,
                technicalAttachmentMode: store.state.preferences.technicalAttachmentMode,
                translatedText: translatedText
            )
            let temporaryJSON = store.state.preferences.technicalAttachmentMode == .json
                ? try TechnicalReportExporter.exportJSON(
                    report: report,
                    profile: store.state.profile,
                    property: property,
                    management: store.management(for: property),
                    evidencePhotos: evidencePhotos
                )
                : nil
            generatedPDF = try store.saveReportedCase(
                report: report,
                category: category,
                property: property,
                generatedPDFURL: temporaryPDF,
                generatedTechnicalJSONURL: temporaryJSON,
                evidenceSHA256: evidencePhotos.isEmpty
                    ? nil
                    : evidencePhotos.map(\.sha256).joined(separator: ", "),
                evidencePhotos: evidencePhotos
            )
            if temporaryJSON != nil,
               let storedCase = store.state.reportedCases.first(where: { $0.id == report.id }) {
                generatedTechnicalJSON = store.technicalJSONURL(for: storedCase)
            } else {
                generatedTechnicalJSON = nil
            }
            errorMessage = nil
            store.clearDraft()
            hasUnsavedDraft = false
            isGeneratingPDF = false
            translationProgressText = nil
        } catch let validationError as IncidentReportValidationError {
            let labels = validationError.missingFields.map(fieldLabel).joined(separator: ", ")
            errorMessage = "Bitte fülle folgende Pflichtfelder aus: \(labels)."
            isGeneratingPDF = false
        } catch {
            errorMessage = store.lastError ?? error.localizedDescription
            isGeneratingPDF = false
        }
    }

    private func resetReport() {
        reportID = UUID()
        reportCreatedAt = Date()
        category = store.activeReportCategories.first ?? .unauthorizedVehicle
        incidentAt = Date()
        garageLocation = ""
        isCommonArea = false
        licensePlate = ""
        vehicleDescription = ""
        violation = category.defaultViolation
        notes = ""
        witnesses = ""
        requestsManagementResponse = true
        allowsNameDisclosure = false
        evidencePhotos = []
        analysisReviewTarget = nil
        generatedPDF = nil
        generatedTechnicalJSON = nil
        mailDraft = nil
        errorMessage = nil
        translationProgressText = nil
        cancelTranslation()
        store.clearDraft()
        hasUnsavedDraft = false
        currentStep = .object
    }

    private func applyAnalysisConfirmation(
        _ result: LocalImageAnalysis,
        photoID: UUID,
        plate: String,
        vehicle: String,
        summary: String
    ) {
        if !plate.isEmpty { licensePlate = plate }
        if !vehicle.isEmpty { vehicleDescription = vehicle }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes = summary
        }

        guard let index = evidencePhotos.firstIndex(where: { $0.id == photoID }) else { return }
        var photo = evidencePhotos[index]
        photo.confirmedAnalysis = ConfirmedImageAnalysis(
            category: result.category,
            vehicleDetected: result.vehicle.detected,
            vehicleConfidence: result.vehicle.confidence,
            suggestedVehicleType: result.category.expectsVehicle ? result.vehicleType?.name : nil,
            suggestedVehicleTypeConfidence: result.category.expectsVehicle ? result.vehicleType?.confidence : nil,
            suggestedVehicleColor: result.category.expectsVehicle ? result.vehicleColor?.name : nil,
            suggestedVehicleColorConfidence: result.category.expectsVehicle ? result.vehicleColor?.confidence : nil,
            suggestedSceneObjects: result.relevantObjects.map {
                ImageAnalysisObjectRecord(name: $0.name, confidence: $0.confidence)
            },
            confirmedLicensePlate: plate,
            confirmedVehicleDescription: vehicle,
            confirmedSceneSummary: summary,
            analyzedAt: Date(),
            analyzerDescription: result.localIntelligenceOutcome == .applied
                ? "Apple Vision mit lokaler Apple-Intelligence-Formulierung; heuristische Farbauswertung"
                : "Apple Vision: Bildklassifizierung, Texterkennung und Salienz; lokale heuristische Farbauswertung"
        )
        evidencePhotos[index] = photo
        Task {
            do {
                try await EvidencePhotoStore.updateMetadata(for: photo)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func cancelDraft() {
        let cancelledReportID = reportID
        Task {
            do {
                try await EvidencePhotoStore.deleteAll(for: cancelledReportID)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
                return
            }
            await MainActor.run {
                resetReport()
                currentStep = .object
            }
        }
    }

    private var currentDraft: IncidentDraft {
        IncidentDraft(
            reportID: reportID,
            reportCreatedAt: reportCreatedAt,
            selectedPropertyID: selectedPropertyID,
            category: category,
            incidentAt: incidentAt,
            garageLocation: garageLocation,
            isCommonArea: isCommonArea,
            licensePlate: licensePlate,
            vehicleDescription: vehicleDescription,
            violation: violation,
            notes: notes,
            witnesses: witnesses,
            evidencePhotoCount: evidencePhotos.count,
            requestsManagementResponse: requestsManagementResponse,
            allowsNameDisclosure: allowsNameDisclosure
        )
    }

    private func restoreDraftIfNeeded() {
        guard !didRestoreDraft else {
            selectFirstPropertyIfNeeded()
            return
        }
        if let draft = store.incidentDraft {
            reportID = draft.reportID
            reportCreatedAt = draft.reportCreatedAt
            selectedPropertyID = draft.selectedPropertyID
            category = draft.category
            incidentAt = draft.incidentAt
            garageLocation = draft.garageLocation
            isCommonArea = draft.isCommonArea
            licensePlate = draft.licensePlate
            vehicleDescription = draft.vehicleDescription
            violation = draft.violation
            notes = draft.notes
            witnesses = draft.witnesses
            requestsManagementResponse = draft.wantsManagementResponse
            allowsNameDisclosure = draft.permitsNameDisclosure
            Task {
                if let restoredPhotos = try? await EvidencePhotoStore.loadAll(for: draft.reportID) {
                    await MainActor.run { evidencePhotos = restoredPhotos }
                }
            }
        } else if let preferredCategory = store.activeReportCategories.first {
            category = preferredCategory
            violation = preferredCategory.defaultViolation
        }
        selectFirstPropertyIfNeeded()
        didRestoreDraft = true
        hasUnsavedDraft = currentDraft.hasMeaningfulContent
    }

    private func reportScopeDescription(for property: ManagedProperty) -> String {
        if isCommonArea {
            return "Bezug der Meldung: Allgemeinfläche des ausgewählten Objekts."
        }
        switch property.occupancyRole {
        case .tenant:
            return "Bezug der Meldung: mein gemietetes Objekt."
        case .owner:
            return "Bezug der Meldung: mein Eigentumsobjekt."
        }
    }

    private func prepareMail(pdfURL: URL, recipient: String) {
        let subjectPlate = licensePlate.trimmingCharacters(in: .whitespacesAndNewlines)
        let objectName = selectedProperty?.officialDisplayName ?? "Objekt"
        var subjectDetails = [garageLocation.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
        if !subjectPlate.isEmpty {
            subjectDetails.append("Kennzeichen \(subjectPlate)")
        }
        if subjectDetails.isEmpty {
            let summary = notes
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if !summary.isEmpty {
                subjectDetails.append(String(summary.prefix(60)))
            }
        }
        let details = subjectDetails.isEmpty ? "Details siehe PDF" : subjectDetails.joined(separator: ", ")
        let subject = "\(objectName) - \(violation) - \(details)"
        mailDraft = MailDraft(
            recipients: [recipient],
            subject: subject,
            body: "Guten Tag,\n\nim Anhang übermittle ich die Dokumentation des Vorfalls.\n\nMit freundlichen Grüßen\n\(store.state.profile.fullName)",
            attachmentURL: pdfURL,
            additionalAttachmentURLs: generatedTechnicalJSON.map { [$0] } ?? []
        )
    }

    private func fieldLabel(_ field: IncidentReportField) -> String {
        switch field {
        case .propertyName: "Objekt"
        case .garageLocation: "Bereich oder Ort im Objekt"
        case .licensePlate: "Kennzeichen"
        case .violation: "Meldegrund"
        }
    }
}

private struct TranslationReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let originalText: PDFReportRenderer.ReportTextTranslation
    @State private var translation: PDFReportRenderer.ReportTextTranslation
    let onConfirm: (PDFReportRenderer.ReportTextTranslation) -> Void

    init(
        originalText: PDFReportRenderer.ReportTextTranslation,
        initialTranslation: PDFReportRenderer.ReportTextTranslation,
        onConfirm: @escaping (PDFReportRenderer.ReportTextTranslation) -> Void
    ) {
        self.originalText = originalText
        _translation = State(initialValue: initialTranslation)
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Originaltext (Deutsch)") {
                    originalTextRow("Bereich oder Ort im Objekt", value: originalText.location)
                    originalTextRow("Meldegrund", value: originalText.violation)
                    if !originalText.notes.trimmedIsEmpty {
                        originalTextRow("Sachliche Beschreibung", value: originalText.notes)
                    }
                    if !originalText.vehicleDescription.trimmedIsEmpty {
                        originalTextRow("Fahrzeugbeschreibung", value: originalText.vehicleDescription)
                    }
                    if !originalText.witnesses.trimmedIsEmpty {
                        originalTextRow("Zeugen", value: originalText.witnesses)
                    }
                }
                Section {
                    TextField("Bereich oder Ort im Objekt", text: $translation.location)
                    TextField("Meldegrund", text: $translation.violation)
                    TextField("Sachliche Beschreibung", text: $translation.notes, axis: .vertical)
                        .lineLimit(3...8)
                    if !translation.vehicleDescription.isEmpty {
                        TextField("Fahrzeugbeschreibung", text: $translation.vehicleDescription)
                    }
                    if !translation.witnesses.isEmpty {
                        TextField("Zeugen", text: $translation.witnesses)
                    }
                } header: {
                    Text("Übersetzung bearbeiten")
                } footer: {
                    Text("Du kannst die lokale Übersetzung vor der PDF-Erstellung korrigieren. Die Zielsprachenseite bleibt als KI-übersetzt gekennzeichnet; verbindlich ist die deutsche Originalfassung.")
                }
            }
            .navigationTitle("Übersetzung prüfen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("PDF erstellen") { onConfirm(translation) }
                }
            }
        }
    }

    private func originalTextRow(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

private enum ReportStep: Int, CaseIterable {
    case object, photos, incident, review

    var title: String {
        switch self {
        case .object: "Objekt und Kategorie"
        case .incident: "Vorfall"
        case .photos: "Fotos und Analyse"
        case .review: "Prüfen und versenden"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppDataStore())
}

private extension String {
    var trimmedIsEmpty: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
