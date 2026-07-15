import HVMeldeCore
import SwiftUI

struct ContentView: View {
    @State private var incidentAt = Date()
    @State private var propertyName = ""
    @State private var garageLocation = ""
    @State private var licensePlate = ""
    @State private var vehicleDescription = ""
    @State private var violation = "Dauerparken"
    @State private var notes = ""
    @State private var witnesses = ""
    @State private var generatedPDF: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Ort und Zeitpunkt") {
                    TextField("Objekt oder Liegenschaft", text: $propertyName)
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

                Section {
                    Button("PDF erzeugen", action: generatePDF)

                    if let generatedPDF {
                        ShareLink(item: generatedPDF) {
                            Label("PDF teilen", systemImage: "square.and.arrow.up")
                        }
                    }
                } footer: {
                    Text("Die App überträgt keine Daten automatisch. Erst das Teilen gibt das PDF an eine andere App weiter.")
                }
            }
            .navigationTitle("Neue Meldung")
            .alert("PDF konnte nicht erzeugt werden", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unbekannter Fehler")
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func generatePDF() {
        let report = IncidentReport(
            incidentAt: incidentAt,
            propertyName: propertyName,
            garageLocation: garageLocation,
            licensePlate: licensePlate,
            vehicleDescription: vehicleDescription,
            violation: violation,
            notes: notes,
            witnesses: witnesses
        )

        do {
            try IncidentReportValidator.validate(report)
            generatedPDF = try PDFReportRenderer.render(report)
            errorMessage = nil
        } catch let validationError as IncidentReportValidationError {
            let labels = validationError.missingFields.map(fieldLabel).joined(separator: ", ")
            errorMessage = "Bitte fülle folgende Pflichtfelder aus: \(labels)."
        } catch {
            errorMessage = error.localizedDescription
        }
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
}

