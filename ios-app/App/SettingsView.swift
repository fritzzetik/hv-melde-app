import HVMeldeCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        List {
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
                            Text(property.occupancyRole.rawValue)
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
                TextField("Bezeichnung, z. B. Wohnung Wien", text: $property.name)
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
            TextField("Straße und Hausnummer", text: $address.street)
                .textContentType(.streetAddressLine1)
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
