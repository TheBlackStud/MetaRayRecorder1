import SwiftUI
import Combine

@MainActor
struct RecorderView: View {
    @ObservedObject var model: RecorderModel
    @State private var sheet: Panel?
    private let ticks = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private enum Panel: String, Identifiable { case settings, library; var id: String { rawValue } }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("METARAY").font(.title2.bold()).tracking(3)
                    Text("RECORDER").font(.caption2.weight(.semibold)).tracking(4).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.showPreview.toggle() } label: {
                    Image(systemName: model.showPreview ? "eye.slash" : "eye")
                        .font(.title3).padding(10)
                }
                    .accessibilityLabel(model.showPreview ? "Masquer l’aperçu" : "Afficher l’aperçu")
                    .disabled(!model.streaming && !model.isRecording)
                Button { open(.library) } label: { Image(systemName: "rectangle.stack").font(.title3).padding(10) }
                    .accessibilityLabel("Mes vidéos").disabled(model.captureBusy)
                Button { open(.settings) } label: { Image(systemName: "slider.horizontal.3").font(.title3).padding(10) }
                    .accessibilityLabel("Réglages").disabled(model.captureBusy)
            }
            HStack(spacing: 8) {
                Circle().fill(model.streaming ? Color.green : Color.secondary).frame(width: 7, height: 7)
                Text(model.deviceName).font(.caption).lineLimit(1)
                Spacer()
                Text(model.freeSpace + " libres").font(.caption2).foregroundStyle(.secondary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Color(white: 0.085))
                if model.showPreview, let image = model.preview {
                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 22))
                } else {
                    VStack(spacing: 18) {
                        Image(systemName: "eyeglasses").font(.system(size: 62, weight: .ultraLight)).foregroundStyle(.secondary)
                        Text(model.status).font(.headline).multilineTextAlignment(.center)
                        Text(model.streaming || model.isRecording
                             ? "Aperçu masqué. Les images sont transférées à l’enregistreur."
                             : "Connectez les lunettes et démarrez la vidéo.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if model.changingSession { ProgressView() }
                    }.padding(28)
                }
                if model.isRecording || model.isStartingRecording || model.isSaving {
                    VStack {
                        HStack(spacing: 8) {
                            Circle().fill(.red).frame(width: 9, height: 9)
                            Text(model.isSaving ? "SAUVEGARDE" : ClipNames.time(model.elapsed))
                                .font(.system(.body, design: .monospaced).bold())
                            if model.isSaving || model.isStartingRecording { ProgressView().scaleEffect(0.7) }
                        }.padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }.padding(16)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.08)))
            VStack(spacing: 12) {
                Text(model.status).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                controls
                Text(model.isRecording
                     ? "Vous pouvez verrouiller l’iPhone. Rouvrez cette application pour arrêter et sauvegarder."
                     : "Le téléphone doit rester à portée des lunettes. Le verrouillage est possible pendant REC.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let message = model.message {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(message).font(.caption).lineLimit(4)
                    Spacer(minLength: 0)
                    Button { model.message = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Fermer le message")
                }.foregroundStyle(.secondary).padding(10).background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 10)
        .background(Color(white: 0.035)).tint(.white)
        .onReceive(ticks) { _ in model.tick() }
        .sheet(item: $sheet) { selected in
            switch selected {
            case .settings: RecorderSettings(model: model)
            case .library: LibraryView(model: model)
            }
        }
        .alert("MetaRay Recorder", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("Fermer", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Autoriser la caméra des lunettes", isPresented: $model.askCameraPermission, titleVisibility: .visible) {
            Button("Ouvrir Meta AI pour autoriser") { Task { await model.grantCameraAndOpenSession() } }
            Button("Annuler", role: .cancel) { Task { await model.cancelPendingRecording() } }
        } message: { Text("Vous allez passer dans Meta AI pour autoriser l’accès à la caméra, puis revenir dans MetaRay Recorder.") }
    }

    @ViewBuilder private var controls: some View {
        if !model.registered {
            Button { Task { await model.connect() } } label: {
                Label("Connecter avec Meta AI", systemImage: "link")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).tint(.red)
            .disabled(model.isConnecting || model.initializationFailed)
        } else if model.isRecording {
            Button { Task { await model.stopRecording() } } label: {
                Label("Arrêter et sauvegarder", systemImage: "stop.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.borderedProminent).tint(.red)
        } else if model.isStartingRecording || model.isSaving {
            HStack(spacing: 12) {
                ProgressView()
                Text(model.status)
            }.frame(maxWidth: .infinity).padding(14)
        } else if model.pendingAutoRecord {
            Button("Annuler la préparation") {
                Task { await model.cancelPendingRecording() }
            }
            .buttonStyle(.bordered).frame(maxWidth: .infinity)
        } else if model.streaming {
            HStack(spacing: 12) {
                Button { Task { await model.stopPreview() } } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.buttonStyle(.bordered).accessibilityLabel("Fermer la caméra")
                Button { model.startRecording() } label: {
                    Label("Enregistrer", systemImage: "record.circle")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.borderedProminent).tint(.red)
                Image(systemName: model.wantsAudio ? "mic.fill" : "mic.slash")
                    .foregroundStyle(.secondary)
            }
        } else if model.changingSession || model.sessionState == .paused || model.streamState == .paused {
            Button("Fermer la session") { Task { await model.stopAll() } }
                .buttonStyle(.bordered).frame(maxWidth: .infinity)
        } else {
            Button { model.requestRecording() } label: {
                Label("Démarrer l’enregistrement", systemImage: "record.circle")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.borderedProminent).tint(.red)
                .disabled(!model.hasDevice && !model.sessionOpen)
        }
    }
    private func open(_ panel: Panel) {
        Task { await model.stopAll(); model.refreshLibrary(); sheet = panel }
    }
}
