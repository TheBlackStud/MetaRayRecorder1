import SwiftUI
import AVKit

@MainActor
struct LibraryView: View {
    @ObservedObject var model: RecorderModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: SavedClip?
    @State private var toDelete: SavedClip?
    var body: some View {
        NavigationStack {
            Group {
                if model.clips.isEmpty {
                    ContentUnavailableView("Aucune vidéo", systemImage: "video", description: Text("Les vidéos finalisées apparaîtront ici."))
                } else {
                    List(model.clips) { clip in
                        VStack(alignment: .leading, spacing: 10) {
                            Button { selected = clip } label: {
                                HStack {
                                    Image(systemName: "play.rectangle.fill").font(.title).foregroundStyle(.red)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(clip.date.formatted(date: .abbreviated, time: .standard)).font(.headline)
                                        Text(clip.sizeText).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }.buttonStyle(.plain)
                            HStack(spacing: 24) {
                                ShareLink(item: clip.url) { Label("Partager", systemImage: "square.and.arrow.up") }
                                Button {
                                    Task { await model.exportToPhotos(clip) }
                                } label: {
                                    if model.savingPhotos == clip.id { ProgressView() }
                                    else { Label("Photos", systemImage: "square.and.arrow.down") }
                                }.disabled(model.savingPhotos != nil)
                                Spacer(minLength: 0)
                                Button(role: .destructive) { toDelete = clip } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("Supprimer la vidéo")
                            }.buttonStyle(.borderless).font(.caption)
                        }.padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Mes vidéos")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
            .sheet(item: $selected) { ClipPlayer(clip: $0) }
            .confirmationDialog("Supprimer cette vidéo de l’application ?", isPresented: Binding(
                get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
                    Button("Supprimer", role: .destructive) {
                        if let clip = toDelete { model.deleteClip(clip) }
                        toDelete = nil
                    }
                    Button("Annuler", role: .cancel) { toDelete = nil }
            } message: { Text("Une copie déjà exportée dans Photos n’est pas supprimée.") }
            .alert("MetaRay Recorder", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("Fermer", role: .cancel) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
            .safeAreaInset(edge: .bottom) {
                if let text = model.message {
                    Text(text).font(.caption).padding().frame(maxWidth: .infinity).background(.ultraThinMaterial)
                }
            }
        }.onAppear { model.refreshLibrary() }
    }
}

@MainActor
private struct ClipPlayer: View {
    let clip: SavedClip
    @State private var player: AVPlayer
    @Environment(\.dismiss) private var dismiss
    init(clip: SavedClip) {
        self.clip = clip
        _player = State(initialValue: AVPlayer(url: clip.url))
    }
    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .navigationTitle("Lecture")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { ShareLink(item: clip.url) }
                    ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } }
                }
                .onAppear { player.play() }
                .onDisappear { player.pause() }
        }
    }
}
