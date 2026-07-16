import HVMeldeCore
import MessageUI
import SwiftUI

private enum AppTab: Hashable {
    case home, report, cases, settings
}

struct ContentView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var selectedTab: AppTab = .home
    @State private var pendingTab: AppTab?
    @State private var showsLeaveWarning = false
    @State private var hasUnsavedDraft = false

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
                .badge(store.state.reportedCases.filter { $0.status == .open }.count)
                .tag(AppTab.cases)

            NavigationStack { SettingsView() }
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .onAppear { hasUnsavedDraft = store.incidentDraft != nil }
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
    @State private var evidencePhotos: [EvidencePhoto] = []
    @State private var generatedPDF: URL?
    @State private var generatedTechnicalJSON: URL?
    @State private var mailDraft: MailDraft?
    @State private var errorMessage: String?
    @State private var didRestoreDraft = false
    @State private var currentStep: ReportStep = .object
    @State private var suppressNextCategoryReset = false
    @State private var showsCancelConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProgressView(value: Double(currentStep.rawValue + 1), total: Double(ReportStep.allCases.count))
                    Text("Schritt \(currentStep.rawValue + 1) von \(ReportStep.allCases.count): \(currentStep.title)")
                        .font(.subheadline.bold())
                }

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
                        licensePlate: $licensePlate,
                        vehicleDescription: $vehicleDescription,
                        notes: $notes
                    )
                    .id(reportID)
                case .review:
                    reviewStep
                }

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
            .onChange(of: category) { _, newCategory in
                if suppressNextCategoryReset {
                    suppressNextCategoryReset = false
                    generatedPDF = nil
                    return
                }
                violation = newCategory.defaultViolation
                generatedPDF = nil
                if !newCategory.expectsVehicle {
                    licensePlate = ""
                    vehicleDescription = ""
                }
            }
            .onChange(of: store.state.properties) { _, _ in selectFirstPropertyIfNeeded() }
            .onChange(of: selectedPropertyID) { _, _ in generatedPDF = nil }
            .onChange(of: evidencePhotos.map(\.id)) { _, _ in generatedPDF = nil }
            .onChange(of: store.state.preferences.technicalAttachmentMode) { _, _ in
                generatedPDF = nil
                generatedTechnicalJSON = nil
            }
            .onChange(of: currentDraft) { _, draft in
                guard didRestoreDraft else { return }
                store.saveDraft(draft)
                hasUnsavedDraft = draft.hasMeaningfulContent
            }
            .sheet(item: $mailDraft) { draft in
                MailComposerView(draft: draft)
            }
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
        }
    }

    private var selectedProperty: ManagedProperty? {
        guard let selectedPropertyID else { return nil }
        return store.state.properties.first { $0.id == selectedPropertyID }
    }

    @ViewBuilder
    private var objectStep: some View {
        Section("Meldekategorie") {
            Picker("Kategorie", selection: $category) {
                ForEach(ReportCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
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
                Picker("Objekt", selection: $selectedPropertyID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(store.state.properties) { property in
                        Text(property.displayName).tag(Optional(property.id))
                    }
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

    @ViewBuilder
    private var incidentStep: some View {
        Section("Ort und Zeitpunkt") {
            TextField("Bereich oder Ort im Objekt", text: $garageLocation)
            DatePicker("Beobachtet am", selection: $incidentAt)
        }
        Section(category.expectsVehicle ? "Fahrzeug und Vorfall" : "Vorfall") {
            if category.expectsVehicle {
                TextField("Kennzeichen", text: $licensePlate)
                    .textInputAutocapitalization(.characters)
                TextField("Fahrzeugbeschreibung (optional)", text: $vehicleDescription)
            }
            TextField("Meldegrund", text: $violation)
            TextField("Sachliche Beschreibung (optional)", text: $notes, axis: .vertical)
                .lineLimit(3...8)
            TextField("Zeugen (optional)", text: $witnesses)
        }
    }

    @ViewBuilder
    private var reviewStep: some View {
        Section("Zusammenfassung") {
            LabeledContent("Objekt", value: selectedProperty?.officialDisplayName ?? "Nicht gewählt")
            LabeledContent("Kategorie", value: category.rawValue)
            LabeledContent("Bereich", value: garageLocation)
            LabeledContent("Meldegrund", value: violation)
            LabeledContent("Beweisfotos", value: "\(evidencePhotos.count)")
        }
        Section {
            Button("PDF erzeugen", action: generatePDF)
                .disabled(selectedProperty == nil)
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
        switch currentStep {
        case .object:
            selectedProperty != nil
        case .incident:
            !garageLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !violation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (!category.expectsVehicle || !licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case .photos, .review:
            true
        }
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

    private func selectFirstPropertyIfNeeded() {
        if let selectedPropertyID,
           store.state.properties.contains(where: { $0.id == selectedPropertyID }) {
            return
        }
        selectedPropertyID = store.state.properties.first?.id
    }

    private func generatePDF() {
        guard let property = selectedProperty else {
            errorMessage = "Bitte lege ein Objekt an und wähle es aus."
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
            category: category
        )

        do {
            try IncidentReportValidator.validate(report)
            let temporaryPDF = try PDFReportRenderer.render(
                report,
                profile: store.state.profile,
                property: property,
                management: store.management(for: property),
                evidencePhotos: evidencePhotos,
                technicalAttachmentMode: store.state.preferences.technicalAttachmentMode
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
        } catch let validationError as IncidentReportValidationError {
            let labels = validationError.missingFields.map(fieldLabel).joined(separator: ", ")
            errorMessage = "Bitte fülle folgende Pflichtfelder aus: \(labels)."
        } catch {
            errorMessage = store.lastError ?? error.localizedDescription
        }
    }

    private func resetReport() {
        reportID = UUID()
        reportCreatedAt = Date()
        category = .unauthorizedVehicle
        incidentAt = Date()
        garageLocation = ""
        isCommonArea = false
        licensePlate = ""
        vehicleDescription = ""
        violation = ReportCategory.unauthorizedVehicle.defaultViolation
        notes = ""
        witnesses = ""
        evidencePhotos = []
        generatedPDF = nil
        generatedTechnicalJSON = nil
        mailDraft = nil
        errorMessage = nil
        store.clearDraft()
        hasUnsavedDraft = false
        currentStep = .object
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
            evidencePhotoCount: evidencePhotos.count
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
            suppressNextCategoryReset = true
            category = draft.category
            incidentAt = draft.incidentAt
            garageLocation = draft.garageLocation
            isCommonArea = draft.isCommonArea
            licensePlate = draft.licensePlate
            vehicleDescription = draft.vehicleDescription
            violation = draft.violation
            notes = draft.notes
            witnesses = draft.witnesses
            Task {
                if let restoredPhotos = try? await EvidencePhotoStore.loadAll(for: draft.reportID) {
                    await MainActor.run { evidencePhotos = restoredPhotos }
                }
            }
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
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
