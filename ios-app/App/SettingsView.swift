import HVMeldeCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppDataStore
    @AppStorage(AppLanguagePreference.storageKey) private var appLanguageRawValue = AppLanguagePreference.system.rawValue
    let showOnboarding: () -> Void

    var body: some View {
        List {
            Section("Hilfe") {
                Button(action: showOnboarding) {
                    Label("Anleitung und erste Schritte", systemImage: "questionmark.circle")
                }
            }

            Section("Sprache und Region") {
                Picker("App-Sprache", selection: appLanguageSelection) {
                    ForEach(AppLanguagePreference.allCases) { language in
                        Text(LocalizedStringKey(language.displayName)).tag(language)
                    }
                }

                Text("Ohne manuelle Auswahl übernimmt die App Sprache und Region aus den iOS-Einstellungen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("iCloud") {
                Toggle(
                    "Daten mit iCloud synchronisieren",
                    isOn: Binding(
                        get: { store.iCloudSyncEnabled },
                        set: { store.setICloudSyncEnabled($0) }
                    )
                )

                LabeledContent("Status", value: store.iCloudSyncStatus.title)
                    .font(.caption)

                if store.iCloudSyncEnabled {
                    Button {
                        Task { await store.syncWithICloud() }
                    } label: {
                        Label("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(store.iCloudSyncStatus == .syncing)
                }

                Text("Profil, Hausverwaltungen, Objekte, Falldaten, Fotos und erzeugte Dokumente werden in deinem privaten iCloud-Bereich gespeichert. Beim ersten Sync können vorhandene Fälle etwas länger dauern.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Lokale KI") {
                Toggle(
                    "Erweiterte lokale Analyse",
                    isOn: Binding(
                        get: { store.state.preferences.enhancedLocalAnalysisEnabled },
                        set: { isEnabled in
                            store.setEnhancedLocalAnalysisEnabled(isEnabled)
                        }
                    )
                )
                LabeledContent("Apple Intelligence", value: LocalIntelligenceService.availability.settingsDescription)
                    .font(.caption)
                Text("Wenn verfügbar, formuliert Apples Modell auf dem Gerät aus den Vision-Ergebnissen einen besseren Beschreibungsvorschlag. Fotos werden nicht an OpenAI oder andere externe Anbieter gesendet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Meldekategorien") {
                NavigationLink {
                    ReportCategoryManagementView()
                } label: {
                    Label("Kategorien verwalten", systemImage: "list.bullet.rectangle")
                }
                Text("Eigene Kategorien können festlegen, ob Fahrzeug- und Kennzeichenfelder benötigt werden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Meldungsdokument") {
                Picker(
                    "Technische Dokumentation",
                    selection: Binding(
                        get: { store.state.preferences.technicalAttachmentMode },
                        set: { store.setTechnicalAttachmentMode($0) }
                    )
                ) {
                    ForEach(TechnicalAttachmentMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Text("Der eigentliche Brief und die Beweisfotos bleiben übersichtlich. EXIF-Daten, Prüfsummen und Angaben zur lokalen Bilderkennung werden nur in der gewählten technischen Anlage ausgegeben.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Persönliche Daten") {
                NavigationLink {
                    ProfileEditorView(profile: store.state.profile)
                } label: {
                    Label(profileLabel, systemImage: "person.crop.circle")
                }
            }

            Section("Objekte") {
                ForEach(store.state.properties) { property in
                    NavigationLink {
                        PropertyEditorView(property: property)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(property.displayName)
                            if !property.officialName.trimmedIsEmpty {
                                Text(property.officialName)
                                    .font(.subheadline)
                            }
                            Text("\(property.propertyType.rawValue) · \(property.occupancyRole.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !property.address.formatted.isEmpty {
                                Text(property.address.formatted)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: store.deleteProperties)

                NavigationLink {
                    PropertyEditorView(property: ManagedProperty())
                } label: {
                    Label("Objekt hinzufügen", systemImage: "plus")
                }
            }

            Section("Hausverwaltungen") {
                ForEach(store.state.propertyManagements) { management in
                    NavigationLink {
                        PropertyManagementEditorView(management: management)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(management.name)
                            if !management.email.isEmpty {
                                Text(management.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: store.deletePropertyManagements)

                NavigationLink {
                    PropertyManagementEditorView(management: PropertyManagement())
                } label: {
                    Label("Hausverwaltung hinzufügen", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Einstellungen")
        .toolbar { EditButton() }
        .alert("Speichern fehlgeschlagen", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "Unbekannter Fehler")
        }
    }

    private var profileLabel: String {
        store.state.profile.fullName.isEmpty ? "Persönliche Daten eintragen" : store.state.profile.fullName
    }

    private var appLanguageSelection: Binding<AppLanguagePreference> {
        Binding(
            get: { AppLanguagePreference(rawValue: appLanguageRawValue) ?? .system },
            set: { appLanguageRawValue = $0.rawValue }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.clearError() } }
        )
    }
}

private struct ReportCategoryManagementView: View {
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        List {
            Section {
                ForEach(store.configurableReportCategories) { category in
                    NavigationLink {
                        ReportCategoryEditorView(category: category)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(category.name)
                                if category.isBuiltIn {
                                    Text("Standard")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !category.isEnabled {
                                    Text("Ausgeblendet")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(category.expectsVehicle ? "Mit Fahrzeug- und Kennzeichenfeldern" : category.defaultViolation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !category.isBuiltIn {
                            Button(role: .destructive) {
                                store.deleteReportCategory(category.id)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
                .onMove(perform: store.moveReportCategories)
            } footer: {
                Text("Standardkategorien können ausgeblendet, aber nicht gelöscht werden. Frühere Meldungen behalten ihre ursprüngliche Kategorie.")
            }
        }
        .navigationTitle("Meldekategorien")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ReportCategoryEditorView(
                        category: ReportCategory(
                            name: "",
                            sortOrder: (store.configurableReportCategories.map(\.sortOrder).max() ?? -1) + 1
                        )
                    )
                } label: {
                    Label("Kategorie hinzufügen", systemImage: "plus")
                }
            }
        }
    }
}

private struct ReportCategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    @State private var category: ReportCategory

    init(category: ReportCategory) {
        _category = State(initialValue: category)
    }

    var body: some View {
        Form {
            Section("Kategorie") {
                TextField("Name", text: $category.name)
                    .disabled(category.isBuiltIn)
                TextField("Voreingestellter Meldegrund", text: $category.defaultViolation, axis: .vertical)
                    .lineLimit(2...4)
                    .disabled(category.isBuiltIn)
                Toggle("In neuen Meldungen anzeigen", isOn: $category.isEnabled)
            }

            Section("Eingabefelder") {
                Toggle("Fahrzeugbezogene Meldung", isOn: $category.expectsVehicle)
                    .disabled(category.isBuiltIn)
                Text(category.expectsVehicle
                    ? "Kennzeichen und Fahrzeugbeschreibung werden angeboten; das Kennzeichen ist ein Pflichtfeld."
                    : "Die Meldung verwendet nur Ort, Meldegrund, Beschreibung und optionale Zeugen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(category.isBuiltIn ? "Standardkategorie" : "Eigene Kategorie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    if category.isBuiltIn {
                        store.setReportCategoryEnabled(category.isEnabled, id: category.id)
                    } else {
                        store.upsertReportCategory(category)
                    }
                    dismiss()
                }
                .disabled(category.name.trimmedIsEmpty || category.defaultViolation.trimmedIsEmpty)
            }
        }
    }
}

private struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    @State private var profile: UserProfile

    init(profile: UserProfile) {
        _profile = State(initialValue: profile)
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Vorname", text: $profile.firstName)
                    .textContentType(.givenName)
                TextField("Nachname", text: $profile.lastName)
                    .textContentType(.familyName)
            }

            AddressFields(address: $profile.address)

            Section("Kontakt") {
                TextField("Telefonnummer", text: $profile.phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                TextField("E-Mail-Adresse", text: $profile.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
            }
        }
        .navigationTitle("Persönliche Daten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    store.saveProfile(profile)
                    dismiss()
                }
                .disabled(profile.firstName.trimmedIsEmpty || profile.lastName.trimmedIsEmpty)
            }
        }
    }
}

private struct PropertyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    @State private var property: ManagedProperty

    init(property: ManagedProperty) {
        _property = State(initialValue: property)
    }

    var body: some View {
        Form {
            Section("Objekt") {
                TextField("Interner Name, z. B. Wohnung Meran", text: $property.name)
                TextField("Offizieller Objektname (optional)", text: $property.officialName)
                Picker("Objekttyp", selection: $property.propertyType) {
                    ForEach(PropertyType.allCases) { type in
                        Text(LocalizedStringKey(type.rawValue)).tag(type)
                    }
                }
                Picker("Nutzungsverhältnis", selection: $property.occupancyRole) {
                    ForEach(OccupancyRole.allCases) { role in
                        Text(LocalizedStringKey(role.rawValue)).tag(role)
                    }
                }
            }

            AddressFields(address: $property.address)

            Section("Hausverwaltung") {
                Picker("Zuständige Hausverwaltung", selection: $property.propertyManagementID) {
                    Text("Keine").tag(UUID?.none)
                    ForEach(store.state.propertyManagements) { management in
                        Text(management.name).tag(Optional(management.id))
                    }
                }

                TextField("Melde-E-Mail für dieses Objekt", text: $property.reportEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

        }
        .navigationTitle(property.name.trimmedIsEmpty ? "Neues Objekt" : property.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: property.propertyManagementID) { _, newID in
            guard property.reportEmail.trimmedIsEmpty,
                  let newID,
                  let management = store.state.propertyManagements.first(where: { $0.id == newID }) else { return }
            property.reportEmail = management.email
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    store.upsert(property)
                    dismiss()
                }
                .disabled(
                    property.name.trimmedIsEmpty
                    || property.address.street.trimmedIsEmpty
                    || property.reportEmail.trimmedIsEmpty
                )
            }
        }
    }
}

private struct PropertyManagementEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    @State private var management: PropertyManagement

    init(management: PropertyManagement) {
        _management = State(initialValue: management)
    }

    var body: some View {
        Form {
            Section("Hausverwaltung") {
                TextField("Name", text: $management.name)
            }

            AddressFields(address: $management.address)

            Section("Kontakt") {
                TextField("Telefonnummer", text: $management.phone)
                    .keyboardType(.phonePad)
                TextField("Allgemeine E-Mail-Adresse", text: $management.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Meldungsdokument") {
                Picker("Briefsprache", selection: $management.reportLanguage) {
                    ForEach(ReportLanguage.allCases) { language in
                        Text(LocalizedStringKey(language.displayName)).tag(language)
                    }
                }
                Text("Bei Deutsch + Italienisch enthält das PDF beide Briefversionen. Beweisfotos und technische Anlagen werden nur einmal angefügt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if management.reportLanguage != .german {
                    Text("Sachliche Freitextfelder werden vor der PDF-Erstellung mit Apples lokalem Sprachmodell übersetzt. Das Original bleibt bei bilingualen PDFs auf der deutschen Briefseite erhalten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(management.name.trimmedIsEmpty ? "Neue Hausverwaltung" : management.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    store.upsert(management)
                    dismiss()
                }
                .disabled(management.name.trimmedIsEmpty)
            }
        }
    }
}

private struct AddressFields: View {
    @Binding var address: PostalAddress

    var body: some View {
        Section("Anschrift") {
            TextField("Straße", text: $address.street)
                .textContentType(.streetAddressLine1)
            TextField("Hausnummer", text: $address.houseNumber)
            TextField("Top / Einheit (optional)", text: $address.unit)
            TextField("PLZ", text: $address.postalCode)
                .textContentType(.postalCode)
            TextField("Ort", text: $address.city)
                .textContentType(.addressCity)
            Picker("Land", selection: $address.country) {
                ForEach(SupportedCountry.allCases) { country in
                    Text(LocalizedStringKey(country.rawValue)).tag(country)
                }
            }
        }
    }
}

private extension String {
    var trimmedIsEmpty: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
