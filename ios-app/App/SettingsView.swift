import HVMeldeCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        List {
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

                Text("Profil, Hausverwaltungen, Objekte und Falldaten werden in deinem privaten iCloud-Bereich gespeichert. Fotos und PDFs bleiben in dieser Version ausschließlich auf diesem Gerät.")
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

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.clearError() } }
        )
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
                        Text(type.rawValue).tag(type)
                    }
                }
                Picker("Nutzungsverhältnis", selection: $property.occupancyRole) {
                    ForEach(OccupancyRole.allCases) { role in
                        Text(role.rawValue).tag(role)
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
                    Text(country.rawValue).tag(country)
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
