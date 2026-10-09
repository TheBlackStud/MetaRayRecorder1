import SwiftUI

@MainActor
struct RecorderSettings: View {
    @ObservedObject var model: RecorderModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDisconnect = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Qualité demandée", selection: $model.quality) {
                        ForEach(RecordingQuality.allCases) { value in Text(value.title).tag(value) }
                    }
                    Picker("Images par seconde", selection: $model.frameRate) {
                        ForEach([15, 24, 30], id: \.self) { Text("\($0) i/s").tag($0) }
                    }
                } header: { Text("Vidéo") } footer: {
                    Text("Le SDK peut réduire la qualité selon la connexion. Il s’agit du flux transmis à l’iPhone, pas d’une vidéo 3K native. Le fichier est encodé en MP4/H.264.")
                }
                Section {
                    Toggle("Afficher l’aperçu vidéo", isOn: $model.showPreview)
                } header: { Text("Affichage") } footer: {
                    Text("Désactivé par défaut : l’application conserve les images pour le MP4, sans afficher de vidéo en direct. L’aperçu est toujours désactivé lorsque l’iPhone est verrouillé.")
                }
                Section {
                    Toggle("Enregistrer le son Bluetooth", isOn: $model.wantsAudio)
                    if model.wantsAudio {
                        Button {
                            Task { await model.findMicrophones() }
                        } label: {
                            HStack { Text("Rechercher les micros Bluetooth"); Spacer(); if model.audioSearching { ProgressView() } }
                        }.disabled(model.audioSearching)
                        Picker("Microphone", selection: $model.audioUID) {
                            Text("Sélectionnez les Ray-Ban").tag("")
                            if !model.audioUID.isEmpty && !model.audioRoutes.contains(where: { $0.id == model.audioUID }) {
                                Text("Sélection enregistrée · à rechercher").tag(model.audioUID)
                            }
                            ForEach(model.audioRoutes) { port in Text(port.name).tag(port.id) }
                        }
                    }
                } header: { Text("Audio") } footer: {
                    Text("Choisissez le port portant le nom de vos lunettes, pas celui d’un autre casque. Le micro de l’iPhone n’est jamais utilisé à sa place. Sans micro sélectionné, désactivez le son pour filmer.")
                }
                Section("Connexion") {
                    LabeledContent("Lunettes", value: model.deviceName)
                    LabeledContent("SDK Meta", value: "DAT 1.0.0")
                    Button("Mettre à jour les lunettes") { Task { await model.firmwareUpdate() } }
                    Button("Mettre à jour l’intégration dans les lunettes") { Task { await model.glassesAppUpdate() } }
                    if model.registered {
                        Button("Déconnecter MetaRay de Meta AI", role: .destructive) { confirmDisconnect = true }
                    }
                }
                Section("Avant de filmer") {
                    Text("Dans Meta AI, activez le mode développeur et gardez les lunettes associées à cet iPhone.")
                    Text("Une fois REC lancé, verrouillez l’iPhone : la caméra et l’écriture MP4 restent actives tant qu’iOS et le SDK autorisent la session. Revenez dans l’application pour arrêter.")
                    Text("Le bouton de capture physique des Ray-Ban ne contrôle pas cet enregistrement tiers. L’API Inputs expérimentale demande une autorisation spécifique de Meta ; elle n’est pas incluse.")
                    Text("En cas de perte du flux, interruption système, surchauffe ou batterie épuisée, l’enregistrement peut s’arrêter. Ne forcez pas la fermeture de l’application.")
                    Text("Aucune durée de 3 ou 5 minutes n’est imposée par ce code. La durée réelle dépend des lunettes, de leur batterie, de la connexion, du SDK et du téléphone.")
                    Text("Respectez les personnes filmées. L’application ne masque ni ne désactive les témoins lumineux des lunettes.")
                }.font(.footnote)
                Section("Fichiers et confidentialité") {
                    Text("Les vidéos sont enregistrées localement dans Fichiers → Sur mon iPhone → MetaRay Recorder → Enregistrements. Vous pouvez les partager ou les ajouter à Photos depuis la bibliothèque.")
                    Text("L’application n’effectue aucun envoi vidéo vers un serveur. Vos réglages de sauvegarde iOS et de Photos restent applicables. L’analytique et les rapports de plantage optionnels du SDK sont désactivés. La connexion Meta reste soumise aux conditions et traitements de Meta.")
                    LabeledContent("Version", value: "1.1.0")
                }.font(.footnote)
            }
            .navigationTitle("Réglages")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
            .confirmationDialog("Déconnecter l’application ?", isPresented: $confirmDisconnect) {
                Button("Déconnecter", role: .destructive) { Task { await model.disconnect() } }
                Button("Annuler", role: .cancel) { }
            }
            .alert("MetaRay Recorder", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("Fermer", role: .cancel) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }
    }
}
