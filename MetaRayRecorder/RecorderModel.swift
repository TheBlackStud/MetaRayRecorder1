import SwiftUI
import UIKit
import Combine
import QuartzCore
@preconcurrency import MWDATCore
@preconcurrency import MWDATCamera

@MainActor
final class RecorderModel: ObservableObject {
    @Published var registration: RegistrationState = .unavailable
    @Published var sessionState: DeviceSessionState = .idle
    @Published var streamState: StreamState = .stopped
    @Published var deviceName = "Aucune lunette détectée"
    @Published var hasDevice = false
    @Published var preview: UIImage?
    @Published var quality: RecordingQuality = .balanced {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "quality") }
    }
    @Published var frameRate = 24 {
        didSet { UserDefaults.standard.set(frameRate, forKey: "frameRate") }
    }
    @Published var showPreview = false {
        didSet {
            UserDefaults.standard.set(showPreview, forKey: "showPreview")
            refreshPreviewMode()
        }
    }
    @Published var pendingAutoRecord = false
    @Published var wantsAudio = false {
        didSet { UserDefaults.standard.set(wantsAudio, forKey: "wantsAudio") }
    }
    @Published var audioRoutes: [MicrophoneRoute] = []
    @Published var audioUID = "" {
        didSet { UserDefaults.standard.set(audioUID, forKey: "audioUID") }
    }
    @Published var audioSearching = false
    @Published var isRecording = false
    @Published var isStartingRecording = false
    @Published var isSaving = false
    @Published var isConnecting = false
    @Published var recordingStart: Date?
    @Published var elapsed: TimeInterval = 0
    @Published var freeSpace = "—"
    @Published var message: String?
    @Published var errorMessage: String?
    @Published var askCameraPermission = false
    @Published var clips: [SavedClip] = []
    @Published var savingPhotos: String?
    @Published var initializationFailed = false

    private var wearables: (any WearablesInterface)?
    private var selector: AutoDeviceSelector?
    private var session: DeviceSession?
    private var camera: MWDATCamera.Camera?
    private let sessionTokens = ListenerTokenBag()
    private let streamTokens = ListenerTokenBag()
    private let movieWriter = MovieWriter()
    private let previewPump = PreviewPump()
    private let streamClock = StreamActivityClock()
    private var appIsForeground = true
    private var frameGate: StreamFrameGate?
    private let microphone = BluetoothMicrophone()
    private var monitors: [Task<Void, Never>] = []
    private var startRecordingTask: Task<Void, Never>?
    private var finishRecordingTask: Task<Void, Never>?
    private var recordingWatchdog: Task<Void, Never>?
    private var saveLease: UIBackgroundTaskIdentifier = .invalid
    private var sessionID = UUID()
    private var streamID = UUID()
    private var streamHasAdvanced = false
    private var armedTime: Double = 0
    private var shuttingDown = false

    var registered: Bool { registration == .registered }
    var sessionOpen: Bool { sessionState == .started }
    var streaming: Bool { streamState == .streaming }
    var captureBusy: Bool { isRecording || isStartingRecording || isSaving }
    var changingSession: Bool {
        isConnecting || sessionState == .starting || sessionState == .stopping ||
            streamState == .starting || streamState == .waitingForDevice || streamState == .stopping
    }
    var status: String {
        if initializationFailed { return "Configuration SDK indisponible" }
        if isSaving { return "Sauvegarde en cours…" }
        if isStartingRecording { return "Préparation de l’enregistrement…" }
        if isRecording { return "Enregistrement en cours · écran verrouillable" }
        if pendingAutoRecord { return "Connexion et préparation de la caméra…" }
        if !registered { return "Connexion Meta AI requise" }
        switch streamState {
        case .streaming: return showPreview ? "Caméra active · aperçu en direct" : "Caméra active · aperçu masqué"
        case .starting, .waitingForDevice: return "Ouverture de la caméra…"
        case .paused: return "Flux suspendu par les lunettes"
        case .stopping: return "Fermeture de la caméra…"
        case .stopped:
            switch sessionState {
            case .started: return "Session ouverte · caméra à démarrer"
            case .starting: return "Connexion aux lunettes…"
            case .paused: return "Session suspendue"
            case .stopping: return "Fermeture de la session…"
            case .idle, .stopped: return hasDevice ? "Lunettes disponibles" : "Mettez les lunettes"
            }
        }
    }

    init() {
        quality = RecordingQuality(rawValue: UserDefaults.standard.string(forKey: "quality") ?? "") ?? .balanced
        let savedFPS = UserDefaults.standard.integer(forKey: "frameRate")
        frameRate = [15, 24, 30].contains(savedFPS) ? savedFPS : 24
        wantsAudio = UserDefaults.standard.bool(forKey: "wantsAudio")
        showPreview = UserDefaults.standard.object(forKey: "showPreview") as? Bool ?? false
        audioUID = UserDefaults.standard.string(forKey: "audioUID") ?? ""
        refreshPreviewMode()
        do {
            try Wearables.configure()
            let api = Wearables.shared
            wearables = api
            let selection = AutoDeviceSelector(wearables: api)
            selector = selection
            registration = api.registrationState
            monitors.append(Task { [weak self] in
                for await value in api.registrationStateStream() {
                    guard let self, !Task.isCancelled else { break }
                    self.registration = value
                    if value != .registered, self.session != nil { await self.stopAll() }
                }
            })
            monitors.append(Task { [weak self] in
                for await deviceID in selection.activeDeviceStream() {
                    guard let self, !Task.isCancelled else { break }
                    self.hasDevice = deviceID != nil
                    self.deviceName = deviceID.flatMap { api.deviceForIdentifier($0)?.nameOrId() }
                        ?? "Mettez vos lunettes et ouvrez leurs branches"
                }
            })
        } catch {
            initializationFailed = true
            errorMessage = "Initialisation du SDK Meta : \(error.localizedDescription)"
        }
        refreshLibrary()
        tick()
        monitors.append(Task { [weak self] in
            let recovered = await ClipLibrary.recoverReadableFiles()
            if recovered > 0 {
                self?.message = "\(recovered) vidéo(s) récupérée(s) après une interruption."
                self?.refreshLibrary()
            }
        })
    }

    func connect() async {
        guard let api = wearables, !isConnecting, !registered else { return }
        isConnecting = true
        defer { isConnecting = false }
        do { try await api.startRegistration() }
        catch { report(error) }
    }

    func handleURL(_ url: URL) async {
        guard url.scheme?.lowercased() == "metarayrecorder",
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .contains(where: { $0.name == "metaWearablesAction" }) == true,
              let api = wearables else { return }
        do { _ = try await api.handleUrl(url) }
        catch { report(error) }
    }

    func openSession() async {
        guard let api = wearables, registered, session == nil, !isConnecting else { return }
        do {
            if try await api.checkPermissionStatus(.camera) != .granted {
                askCameraPermission = true
                return
            }
            createSession()
        } catch {
            pendingAutoRecord = false
            report(error)
        }
    }

    func grantCameraAndOpenSession() async {
        askCameraPermission = false
        guard let api = wearables, !isConnecting else { return }
        isConnecting = true
        do {
            let result = try await api.requestPermission(.camera)
            isConnecting = false
            guard result == .granted else {
                pendingAutoRecord = false
                errorMessage = "L’accès à la caméra des lunettes a été refusé. Autorisez MetaRay Recorder dans Meta AI."; return
            }
            createSession()
        } catch {
            isConnecting = false
            pendingAutoRecord = false
            report(error)
        }
    }

    private func createSession() {
        guard session == nil, let api = wearables, let selector else { return }
        let id = UUID()
        sessionID = id
        do {
            let fresh = try api.createSession(deviceSelector: selector)
            session = fresh
            fresh.statePublisher.listen { [weak self] state in
                Task { @MainActor in
                    guard let self, self.sessionID == id else { return }
                    self.sessionState = state
                    if state == .started, self.pendingAutoRecord, self.camera == nil {
                        self.startPreview()
                    }
                    if state == .stopped {
                        self.pendingAutoRecord = false
                        await self.stopRecording()
                        self.releaseStream()
                        self.sessionTokens.clear()
                        self.session = nil
                    }
                }
            }.store(in: sessionTokens)
            fresh.errorPublisher.listen { [weak self] error in
                Task { @MainActor in
                    guard let self, self.sessionID == id, !self.shuttingDown else { return }
                    self.report(error)
                    await self.stopAll()
                }
            }.store(in: sessionTokens)
            sessionState = .starting
            try fresh.start()
        } catch {
            sessionTokens.clear(); session = nil; sessionState = .idle
            pendingAutoRecord = false
            report(error)
        }
    }

    /// Un seul bouton après l’association initiale : ouvre la session, démarre
    /// le flux brut et déclenche l’enregistrement à la première disponibilité.
    /// L’aperçu UIImage est facultatif et n’entre jamais dans cette chaîne.
    func requestRecording() {
        guard registered, hasDevice, !captureBusy, !shuttingDown else { return }
        if streaming {
            startRecording()
            return
        }
        guard !pendingAutoRecord else { return }
        pendingAutoRecord = true
        message = nil
        if sessionOpen {
            startPreview()
        } else if session == nil {
            Task { await openSession() }
        }
        // Dans les autres états, attendre .started sans forcer une session pausée.
    }

    func cancelPendingRecording() async {
        pendingAutoRecord = false
        await stopAll()
    }

    private func refreshPreviewMode() {
        previewPump.setEnabled(showPreview && appIsForeground)
        if !showPreview || !appIsForeground { preview = nil }
    }

    func startPreview() {
        guard sessionOpen, camera == nil, let session else { return }
        let resolution: StreamingResolution
        switch quality { case .economy: resolution = .low; case .balanced: resolution = .medium; case .high: resolution = .high }
        do {
            let configuration = StreamConfiguration(videoCodec: .raw, resolution: resolution, frameRate: UInt(frameRate))
            guard let freshCamera = try session.addCamera(config: configuration) else {
                throw RecorderFailure.message("La caméra n’a pas pu être ajoutée à la session.")
            }
            camera = freshCamera
            let id = UUID()
            streamID = id
            streamHasAdvanced = false
            let stream = freshCamera.stream
            let writer = movieWriter
            let pump = previewPump
            let gate = StreamFrameGate()
            let clock = streamClock
            clock.reset()
            frameGate = gate
            stream.statePublisher.listen { [weak self] state in
                Task { @MainActor in
                    guard let self, self.streamID == id else { return }
                    // Some state publishers replay the initial stopped value when subscribed.
                    // Do not tear down a just-created camera before its first start transition.
                    if state == .stopped && !self.streamHasAdvanced { return }
                    if state != .stopped { self.streamHasAdvanced = true }
                    self.streamState = state
                    if state == .streaming, self.pendingAutoRecord {
                        self.pendingAutoRecord = false
                        self.startRecording()
                    }
                    if state == .stopped {
                        self.pendingAutoRecord = false
                        await self.stopRecording()
                        self.releaseStream()
                    } else if state == .paused, self.captureBusy {
                        self.message = "Flux suspendu : la vidéo est arrêtée pour éviter un enregistrement figé."
                        await self.stopRecording()
                    }
                }
            }.store(in: streamTokens)
            stream.videoFramePublisher.listen { [weak self] frame in
                gate.withActiveStream {
                    // Le flux alimente directement l’encodeur, même téléphone verrouillé.
                    // L’aperçu peut être entièrement désactivé sans couper l’enregistrement.
                    let time = CACurrentMediaTime()
                    clock.mark(time: time)
                    writer.appendVideo(frame.sampleBuffer, hostTime: time)
                    pump.receive(frame) { [weak self] image in
                        guard let self, self.streamID == id, self.camera != nil,
                              self.showPreview, self.appIsForeground else { return }
                        self.preview = image
                    }
                }
            }.store(in: streamTokens)
            stream.errorPublisher.listen { [weak self] error in
                Task { @MainActor in
                    guard let self, self.streamID == id, !self.shuttingDown else { return }
                    self.report(error)
                    await self.stopAll()
                }
            }.store(in: streamTokens)
            streamClock.reset()
            refreshPreviewMode()
            streamState = .starting
            freshCamera.stream.start()
        } catch {
            pendingAutoRecord = false
            releaseStream()
            report(error)
        }
    }

    func stopPreview() async {
        await stopRecording()
        releaseStream()
    }

    private func releaseStream() {
        frameGate?.close()
        frameGate = nil
        streamClock.reset()
        streamID = UUID() // Reject callbacks queued by the previous stream.
        streamHasAdvanced = false
        streamTokens.clear()
        let old = camera
        camera = nil
        old?.stop()
        streamState = .stopped
        preview = nil
    }

    func stopAll() async {
        guard !shuttingDown else {
            if let task = finishRecordingTask { await task.value }
            return
        }
        shuttingDown = true
        pendingAutoRecord = false
        await stopRecording()
        releaseStream()
        sessionID = UUID()
        sessionTokens.clear()
        let old = session
        session = nil
        old?.stop()
        sessionState = .idle
        shuttingDown = false
    }

    func findMicrophones() async {
        guard !captureBusy, !audioSearching else { return }
        audioSearching = true
        defer { audioSearching = false }
        do {
            audioRoutes = try await microphone.routes()
            if !audioRoutes.contains(where: { $0.id == audioUID }) {
                audioUID = "" // The user must explicitly identify the glasses microphone.
            }
            if audioRoutes.isEmpty {
                message = "Aucun micro Bluetooth détecté. Connectez les Ray-Ban à l’iPhone, puis relancez la recherche. L’enregistrement sans son reste disponible."
            }
        } catch { report(error) }
    }

    func startRecording() {
        guard streaming, !captureBusy, !shuttingDown else { return }
        if let free = ClipLibrary.availableBytes(), free < 500_000_000 {
            errorMessage = "Libérez au moins 500 Mo avant de filmer."; return
        }
        if wantsAudio && audioUID.isEmpty {
            errorMessage = "Ouvrez les réglages, recherchez les micros Bluetooth puis sélectionnez vos Ray-Ban. Sinon, désactivez le son."; return
        }
        isStartingRecording = true
        message = nil
        recordingStart = nil
        elapsed = 0
        let writer = movieWriter
        startRecordingTask = Task { [weak self] in
            guard let self else { return }
            var prepared = false
            do {
                if self.wantsAudio {
                    try await self.microphone.start(uid: self.audioUID, onBuffer: { buffer, time in
                        writer.appendAudio(buffer, hostTime: time)
                    }, onInterrupted: { [weak self] reason in
                        guard let self else { return }
                        self.message = reason
                        Task { await self.stopRecording() }
                    })
                }
                try Task.checkCancellation()
                guard self.streaming else { throw CancellationError() }
                let url = try ClipLibrary.pendingURL()
                try await writer.prepare(url: url, quality: self.quality, fps: self.frameRate, audio: self.wantsAudio,
                    onFirstFrame: { [weak self] in
                        Task { @MainActor in self?.recordingStart = Date() }
                    }, onFailure: { [weak self] reason in
                        Task { @MainActor in
                            guard let self else { return }
                            self.errorMessage = reason
                            await self.stopRecording()
                        }
                    })
                prepared = true
                try Task.checkCancellation()
                guard self.streaming else { throw CancellationError() }
                self.armedTime = CACurrentMediaTime()
                self.isRecording = true
                self.startWatchdog()
            } catch {
                self.microphone.stop()
                if prepared, let url = try? await writer.finish() {
                    do { _ = try ClipLibrary.commit(url); self.refreshLibrary() }
                    catch { self.report(error) }
                }
                if !(error is CancellationError) { self.report(error) }
            }
            self.isStartingRecording = false
            self.startRecordingTask = nil
        }
    }

    func stopRecording() async {
        if let task = startRecordingTask { task.cancel(); await task.value }
        if let task = finishRecordingTask { await task.value; return }
        guard isRecording else { return }
        isRecording = false
        recordingWatchdog?.cancel()
        recordingWatchdog = nil
        isSaving = true
        beginSaveLease()
        microphone.stop()
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let stopReason = self.message
                let pending = try await self.movieWriter.finish()
                let saved = try ClipLibrary.commit(pending)
                self.message = (stopReason.map { $0 + "\n" } ?? "") + "Vidéo enregistrée : \(saved.lastPathComponent)"
                self.refreshLibrary()
            } catch { self.report(error) }
            self.isSaving = false
            self.endSaveLease()
            self.recordingStart = nil
            self.finishRecordingTask = nil
        }
        finishRecordingTask = task
        await task.value
    }

    /// Temps supplémentaire iOS UNIQUEMENT pour finaliser un MP4 quand le flux
    /// s'interrompt à l'arrière-plan. Il ne prolonge pas la capture elle-même.
    private func beginSaveLease() {
        guard saveLease == .invalid else { return }
        saveLease = UIApplication.shared.beginBackgroundTask(withName: "Sauvegarder MetaRay Recorder") { [weak self] in
            Task { @MainActor in self?.endSaveLease() }
        }
    }

    private func endSaveLease() {
        guard saveLease != .invalid else { return }
        UIApplication.shared.endBackgroundTask(saveLease)
        saveLease = .invalid
    }

    func tick() {
        elapsed = recordingStart.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        if let free = ClipLibrary.availableBytes() {
            freeSpace = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
        }
        checkRecordingHealth()
    }

    /// Surveillance indépendante du timer SwiftUI, qui ne fonctionne pas toujours
    /// écran verrouillé. Quand le SDK réveille notre processus pour les images,
    /// cette tâche peut également surveiller le stockage et les interruptions.
    private func startWatchdog() {
        recordingWatchdog?.cancel()
        recordingWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) }
                catch { return }
                guard let self, self.isRecording else { return }
                self.checkRecordingHealth()
            }
        }
    }

    private func checkRecordingHealth() {
        guard isRecording, !shuttingDown else { return }
        if let free = ClipLibrary.availableBytes(), free < 200_000_000 {
            message = "Espace presque plein : arrêt et sauvegarde de la vidéo."
            Task { await stopAll() }
        } else if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            message = "L’iPhone chauffe : arrêt et sauvegarde de la vidéo."
            Task { await stopAll() }
        } else if CACurrentMediaTime() - max(armedTime, streamClock.lastFrameTime() ?? armedTime) > 8 {
            message = "Flux interrompu pendant plus de 8 secondes : sauvegarde de la vidéo."
            Task { await stopAll() }
        }
    }

    // Ne pas fermer la caméra ni l’encodeur lorsque l’iPhone est verrouillé.
    // Seul le décodage UIImage, destiné à l’interface, est suspendu.
    func enteredBackground() {
        appIsForeground = false
        refreshPreviewMode()
    }

    func enteredForeground() {
        appIsForeground = true
        refreshPreviewMode()
        // Le flux a continué d’actualiser streamClock, indépendamment de l’écran.
    }

    func refreshLibrary() {
        do { clips = try ClipLibrary.list() }
        catch { report(error) }
    }
    func deleteClip(_ clip: SavedClip) {
        do { try ClipLibrary.delete(clip); refreshLibrary() }
        catch { report(error) }
    }
    func exportToPhotos(_ clip: SavedClip) async {
        guard savingPhotos == nil else { return }
        savingPhotos = clip.id
        defer { savingPhotos = nil }
        do { try await ClipLibrary.saveToPhotos(clip.url); message = "Vidéo ajoutée à Photos." }
        catch { report(error) }
    }
    func firmwareUpdate() async {
        guard let api = wearables else { return }
        await stopAll()
        do { try await api.openFirmwareUpdate() }
        catch { report(error) }
    }
    func glassesAppUpdate() async {
        guard let api = wearables else { return }
        await stopAll()
        do { try await api.openDATGlassesAppUpdate() }
        catch { report(error) }
    }
    func disconnect() async {
        guard let api = wearables else { return }
        await stopAll()
        do { try await api.startUnregistration() }
        catch { report(error) }
    }
    private func report(_ error: Error) { errorMessage = error.localizedDescription }
}
