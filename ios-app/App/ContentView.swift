import HVMeldeCore
import MessageUI
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppDataStore
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
    @State private var evidencePhoto: EvidencePhoto?
    @State private var generatedPDF: URL?
    @State private var mailDraft: MailDraft?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Meldekategorie") {
                    Picker("Kategorie", selection: $category) {
                        ForEach(ReportCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                }

                Section("Ort und Zeitpunkt") {
                    if store.state.properties.isEmpty {
                        ContentUnavailableView(
                            "Noch kein Objekt",
                            systemImage: "building.2",
                            description: Text("Lege zuerst über das Zahnrad ein Objekt an.")
                        )
                    } else {
                        Picker("Objekt", selection: $selectedPropertyID) {
                            Text("Bitte wählen").tag(UUID?.none)
                            ForEach(store.state.properties) { property in
                                Text(property.displayName).tag(Optional(property.id))
                            }
                        }
                        if let selectedProperty {
                            LabeledContent("Nutzungsverhältnis", value: selectedProperty.occupancyRole.rawValue)
                        }
                    }

                    Toggle("Betrifft eine Allgemeinfläche", isOn: $isCommonArea)
                        .disabled(selectedProperty == nil)
                    if let selectedProperty {
                        Text(reportScopeDescription(for: selectedProperty))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Garagenbereich oder Stellplatz", text: $garageLocation)
                    DatePicker("Beobachtet am", selection: $incidentAt)
                }

                Section("Fahrzeug und Vorfall") {
                    TextField("Kennzeichen", text: $licensePlate)
                        .textInputAutocapitalization(.characters)
                    TextField("Fahrzeugbeschreibung (optional)", text: $vehicleDescription)
                    TextField("Art des Verstoßes", text: $violation)
                    TextField("Sachliche Beschreibung (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Zeugen (optional)", text: $witnesses)
                }

                PhotoAnalysisSection(
                    reportID: reportID,
                    category: category,
                    evidencePhoto: $evidencePhoto,
                    licensePlate: $licensePlate,
                    vehicleDescription: $vehicleDescription,
                    notes: $notes
                )
                .id(reportID)

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
                    if selectedProperty?.reportEmail.nonEmpty == nil {
                        Text("Hinterlege beim Objekt eine Melde-E-Mail, um den Empfänger automatisch auszufüllen.")
                    } else if !MFMailComposeViewController.canSendMail() {
                        Text("Auf diesem Gerät ist kein Mailkonto für die Apple-Mail-App eingerichtet. Das PDF kann weiterhin geteilt werden.")
                    } else {
                        Text("Die App überträgt keine Daten automatisch. Der Versand erfolgt erst nach deiner Bestätigung im Mailfenster.")
                    }
                }
            }
            .navigationTitle("Neue Meldung")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        ReportedCasesView()
                    } label: {
                        Image(systemName: "tray.full")
                    }
                    .accessibilityLabel("Gemeldete Fälle")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Einstellungen")
                }
            }
            .onAppear(perform: selectFirstPropertyIfNeeded)
            .onChange(of: category) { _, newCategory in
                violation = newCategory.defaultViolation
            }
            .onChange(of: store.state.properties) { _, _ in selectFirstPropertyIfNeeded() }
            .onChange(of: selectedPropertyID) { _, _ in generatedPDF = nil }
            .onChange(of: evidencePhoto?.id) { _, _ in generatedPDF = nil }
            .sheet(item: $mailDraft) { draft in
                MailComposerView(draft: draft)
            }
            .alert("Meldung konnte nicht gespeichert werden", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? store.lastError ?? "Unbekannter Fehler")
            }
        }
    }

    private var selectedProperty: ManagedProperty? {
        guard let selectedPropertyID else { return nil }
        return store.state.properties.first { $0.id == selectedPropertyID }
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
            isCommonArea: isCommonArea
        )

        do {
            try IncidentReportValidator.validate(report)
            let temporaryPDF = try PDFReportRenderer.render(
                report,
                profile: store.state.profile,
                property: property,
                management: store.management(for: property),
                evidencePhoto: evidencePhoto
            )
            generatedPDF = try store.saveReportedCase(
                report: report,
                category: category,
                property: property,
                generatedPDFURL: temporaryPDF,
                evidenceSHA256: evidencePhoto?.sha256
            )
            errorMessage = nil
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
        evidencePhoto = nil
        generatedPDF = nil
        mailDraft = nil
        errorMessage = nil
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
        let subject = subjectPlate.isEmpty
            ? "Meldung zu \(selectedProperty?.displayName ?? "Objekt")"
            : "Meldung Kennzeichen \(subjectPlate)"
        mailDraft = MailDraft(
            recipients: [recipient],
            subject: subject,
            body: "Guten Tag,\n\nim Anhang übermittle ich die Dokumentation des Vorfalls.\n\nMit freundlichen Grüßen\n\(store.state.profile.fullName)",
            attachmentURL: pdfURL
        )
    }

    private func fieldLabel(_ field: IncidentReportField) -> String {
        switch field {
        case .propertyName: "Objekt"
        case .garageLocation: "Garagenbereich"
        case .licensePlate: "Kennzeichen"
        case .violation: "Art des Verstoßes"
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
