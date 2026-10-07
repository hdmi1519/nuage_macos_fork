//
//  VoiceControlService.swift
//  Nuage
//

import SwiftUI
import Combine
import Speech
import AVFoundation
import AppKit

public struct AudioInputDevice: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let isBuiltIn: Bool
    
    public init(id: String, name: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}

public enum VoiceLanguage: String, CaseIterable, Identifiable {
    case russian = "ru-RU"
    case english = "en-US"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        }
    }
}

public enum VoiceCommand: Equatable {
    case playLikes
    case playWave
    case refreshWave
    case playStream
    case shareTrack(targetName: String)
    case repost
    case unrepost
    case playReposts
    case unlike
    case like
    case volumeUp
    case volumeDown
    case mute
    case nextTrack
    case previousTrack
    case shuffle
    case repeatQueue
    case pause
    case play
    case postComment(text: String)
    case searchAndPlay(query: String)
    
    public var title: String {
        switch self {
        case .playLikes: return NSLocalizedString("voice.hud.likedTracks", comment: "")
        case .playWave: return NSLocalizedString("voice.hud.myWave", comment: "")
        case .refreshWave: return NSLocalizedString("voice.hud.waveRefreshed", comment: "")
        case .playStream: return NSLocalizedString("voice.hud.stream", comment: "")
        case .shareTrack(let name): return String(format: NSLocalizedString("voice.hud.shareFormat", comment: ""), name)
        case .postComment(let text): return String(format: NSLocalizedString("voice.hud.commentPreview", comment: ""), text)
        case .searchAndPlay(let query): return String(format: NSLocalizedString("voice.hud.search", comment: ""), query)
        case .repost: return NSLocalizedString("voice.hud.reposted", comment: "")
        case .unrepost: return NSLocalizedString("voice.hud.unreposted", comment: "")
        case .playReposts: return NSLocalizedString("voice.hud.reposts", comment: "")
        case .unlike: return NSLocalizedString("voice.hud.unliked", comment: "")
        case .like: return NSLocalizedString("voice.hud.liked", comment: "")
        case .volumeUp: return NSLocalizedString("voice.cmd.volumeUp", comment: "")
        case .volumeDown: return NSLocalizedString("voice.cmd.volumeDown", comment: "")
        case .mute: return NSLocalizedString("voice.cmd.mute", comment: "")
        case .nextTrack: return NSLocalizedString("voice.cmd.next", comment: "")
        case .previousTrack: return NSLocalizedString("voice.cmd.prev", comment: "")
        case .shuffle: return NSLocalizedString("voice.hud.shuffle", comment: "")
        case .repeatQueue: return NSLocalizedString("voice.hud.repeat", comment: "")
        case .pause: return NSLocalizedString("voice.cmd.pause", comment: "")
        case .play: return NSLocalizedString("voice.cmd.play", comment: "")
        }
    }
    
    public var icon: String {
        switch self {
        case .playLikes: return "heart.circle.fill"
        case .playWave: return "dot.radiowaves.left.and.right"
        case .refreshWave: return "arrow.clockwise"
        case .playStream: return "bolt.horizontal.fill"
        case .shareTrack: return "paperplane.fill"
        case .postComment: return "bubble.left.fill"
        case .searchAndPlay: return "magnifyingglass"
        case .repost: return "repeat"
        case .unrepost: return "arrow.triangle.2.circlepath"
        case .playReposts: return "repeat.circle.fill"
        case .unlike: return "heart.slash"
        case .like: return "heart.fill"
        case .volumeUp: return "speaker.wave.3.fill"
        case .volumeDown: return "speaker.wave.1.fill"
        case .mute: return "speaker.slash.fill"
        case .nextTrack: return "forward.fill"
        case .previousTrack: return "backward.fill"
        case .shuffle: return "shuffle"
        case .repeatQueue: return "repeat"
        case .pause: return "pause.fill"
        case .play: return "play.fill"
        }
    }
}

final class VoiceControlService: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    static let shared = VoiceControlService()
    
    private let enabledKey = "enableVoiceControl"
    private let languageKey = "voiceControlLanguage"
    private let deviceKey = "voiceControlInputDeviceID"
    private let showVoiceHUDKey = "showVoiceHUD"
    private let wakeWordKey = "voiceControlWakeWord"
    private let requireWakeWordKey = "voiceControlRequireWakeWord"
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
            if isEnabled {
                startListening()
            } else {
                stopListening()
            }
        }
    }
    
    @Published var language: VoiceLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: languageKey)
            if isListening {
                recognitionTask?.cancel()
                scheduleTaskRestart()
            }
        }
    }
    
    @Published var selectedDeviceID: String {
        didSet {
            UserDefaults.standard.set(selectedDeviceID, forKey: deviceKey)
            if isEnabled && isListening {
                restartCaptureSession()
            }
        }
    }
    
    @Published var showVoiceHUD: Bool {
        didSet {
            UserDefaults.standard.set(showVoiceHUD, forKey: showVoiceHUDKey)
        }
    }
    
    @Published var wakeWord: String {
        didSet {
            UserDefaults.standard.set(wakeWord, forKey: wakeWordKey)
            if isListening {
                recognitionTask?.cancel()
                scheduleTaskRestart()
            }
        }
    }
    
    @Published var requireWakeWord: Bool {
        didSet {
            UserDefaults.standard.set(requireWakeWord, forKey: requireWakeWordKey)
        }
    }
    
    @Published var availableDevices: [AudioInputDevice] = []
    
    @Published var isListening: Bool = false
    @Published var isAuthorized: Bool = false
    @Published var authorizationMessage: String? = nil
    
    // HUD state
    @Published var currentHUDText: String? = nil
    @Published var currentHUDIcon: String = "mic.fill"
    @Published var isShowingHUD: Bool = false
    
    // Audio Capture Session (strictly input-only, eliminates AudioUnit conflicts with AVPlayer)
    private var captureSession: AVCaptureSession?
    private var captureOutput: AVCaptureAudioDataOutput?
    private let captureQueue = DispatchQueue(label: "nuage.voicecontrol.captureQueue")
    
    // Speech Recognition
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private var lastCommandTimestamp: Date = .distantPast
    private var lastExecutedCommand: VoiceCommand? = nil
    private var hudDismissWorkItem: DispatchWorkItem? = nil
    private var isRestarting: Bool = false
    private var wakeWordArmedUntil: Date = .distantPast
    
    override private init() {
        let savedEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        let savedLangRaw = UserDefaults.standard.string(forKey: languageKey) ?? VoiceLanguage.russian.rawValue
        let savedDevice = UserDefaults.standard.string(forKey: deviceKey) ?? "default"
        let savedHUD = UserDefaults.standard.object(forKey: showVoiceHUDKey) as? Bool ?? true
        let savedWakeWord = UserDefaults.standard.string(forKey: wakeWordKey) ?? "Sound"
        let savedRequireWakeWord = UserDefaults.standard.object(forKey: requireWakeWordKey) as? Bool ?? true
        
        self.isEnabled = savedEnabled
        self.language = VoiceLanguage(rawValue: savedLangRaw) ?? .russian
        self.selectedDeviceID = savedDevice
        self.showVoiceHUD = savedHUD
        self.wakeWord = savedWakeWord
        self.requireWakeWord = savedRequireWakeWord
        
        super.init()
        
        loadAvailableDevices()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDevicesChanged),
            name: AVCaptureDevice.wasConnectedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDevicesChanged),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil
        )
        
        if savedEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startListening()
            }
        }
    }
    
    @objc private func handleDevicesChanged() {
        loadAvailableDevices()
    }
    
    func loadAvailableDevices() {
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            types = [.microphone, .external]
        } else {
            types = [.builtInMicrophone, .externalUnknown]
        }
        
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .audio,
            position: .unspecified
        )
        
        let devices = session.devices.map { device in
            AudioInputDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isBuiltIn: device.uniqueID.contains("BuiltIn")
            )
        }
        
        DispatchQueue.main.async {
            self.availableDevices = devices
        }
    }
    
    private func resolveAudioDevice() -> AVCaptureDevice? {
        if selectedDeviceID != "default", !selectedDeviceID.isEmpty {
            if let dev = AVCaptureDevice(uniqueID: selectedDeviceID) {
                return dev
            }
        }
        return AVCaptureDevice.default(for: .audio)
    }
    
    // MARK: - Permissions & Start/Stop
    
    func toggle() {
        isEnabled.toggle()
    }
    
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async {
                            self?.isAuthorized = granted
                            if !granted {
                                self?.authorizationMessage = "Доступ к микрофону заблокирован в Настройках Mac."
                            }
                            completion(granted)
                        }
                    }
                case .denied, .restricted:
                    self?.isAuthorized = false
                    self?.authorizationMessage = "Распознавание речи отключено в Настройках Mac."
                    completion(false)
                case .notDetermined:
                    self?.isAuthorized = false
                    completion(false)
                @unknown default:
                    completion(false)
                }
            }
        }
    }
    
    func startListening() {
        guard isEnabled else { return }
        guard !isListening else { return }
        
        requestPermissions { [weak self] granted in
            guard let self = self, granted else { return }
            self.beginCaptureSession()
        }
    }
    
    func stopListening() {
        isListening = false
        isRestarting = false
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        let sessionToStop = self.captureSession
        self.captureSession = nil
        self.captureOutput = nil
        
        captureQueue.async {
            if sessionToStop?.isRunning == true {
                sessionToStop?.stopRunning()
            }
        }
    }
    
    private func beginCaptureSession() {
        // Teardown any running recognition
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        let previousSession = self.captureSession
        self.captureSession = nil
        self.captureOutput = nil
        
        captureQueue.async {
            if previousSession?.isRunning == true {
                previousSession?.stopRunning()
            }
        }
        
        guard let audioDevice = resolveAudioDevice(),
              let input = try? AVCaptureDeviceInput(device: audioDevice) else {
            print("VoiceControl: Could not resolve or initialize audio input device")
            DispatchQueue.main.async {
                self.isListening = false
            }
            return
        }
        
        let session = AVCaptureSession()
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            print("VoiceControl: Cannot add input to capture session")
            return
        }
        
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            print("VoiceControl: Cannot add output to capture session")
            return
        }
        
        self.captureSession = session
        self.captureOutput = output
        
        startNewRecognitionTask()
        
        captureQueue.async { [weak self] in
            session.startRunning()
            DispatchQueue.main.async {
                self?.isListening = true
            }
        }
    }
    
    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isListening else { return }
        recognitionRequest?.appendAudioSampleBuffer(sampleBuffer)
    }
    
    private func startNewRecognitionTask() {
        recognitionTask = nil
        recognitionRequest = nil
        lastProcessedIndex = 0
        cancelPendingParametric()
        
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        var contextual = ["SoundCloud", "лайк", "дизлайк", "репост", "коммент", "комент", "волна", "лента", "Kai Angel", "Gladiator"]
        if let saved = UserDefaults.standard.dictionary(forKey: "user_voice_aliases_map") as? [String: String] {
            contextual.append(contentsOf: saved.values)
        }
        contextual.append(contentsOf: activeWakeWordVariants())
        request.contextualStrings = contextual
        self.recognitionRequest = request
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                self.processTranscription(transcription, isFinal: result.isFinal)
            }
            
            if error != nil || (result?.isFinal == true) {
                if self.isEnabled && self.isListening && !self.isRestarting {
                    self.scheduleTaskRestart()
                }
            }
        }
    }
    
    private func scheduleTaskRestart() {
        guard isEnabled, isListening, !isRestarting else { return }
        isRestarting = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self, self.isEnabled, self.isListening else {
                self?.isRestarting = false
                return
            }
            self.isRestarting = false
            self.startNewRecognitionTask()
        }
    }
    
    private func restartCaptureSession() {
        guard isEnabled, isListening else { return }
        stopListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self, self.isEnabled else { return }
            self.startListening()
        }
    }
    
    // MARK: - Command Processing
    
    private var lastProcessedIndex: Int = 0
    private var pendingParametricTimer: Timer?
    private var pendingParametricCommand: VoiceCommand?
    private var pendingParametricTextCount: Int = 0
    
    private let shareKeywords = [
        "отправь трек другу", "скинь трек другу", "отправь другу", "скинь другу",
        "поделись треком с", "поделись с", "отправь трек", "скинь трек",
        "перекинь трек", "кинь трек", "отправь", "скинь", "поделись", "перекинь", "кинь",
        "send track to friend", "send to friend", "send track to", "share track with", "send to", "share with", "share to"
    ]
    
    private let commentKeywords = [
        "напиши комментарий", "написать комментарий", "оставь комментарий", "оставить комментарий",
        "напиши коммент", "написать коммент", "оставь коммент", "оставить коммент",
        "добавь комментарий", "добавить комментарий", "добавь коммент", "добавить коммент",
        "комментарий", "коммент", "комент", "коментируй", "закомментируй",
        "post comment", "write comment", "add comment", "leave comment", "comment"
    ]
    
    private let searchKeywords = [
        "найди трек", "найди песню", "найди музыку", "найти трек", "найти песню",
        "вруби трек", "вруби песню", "поставь трек", "поставь песню", "включи трек", "включи песню",
        "поиск трека", "поиск песни", "поиск", "найди", "найти",
        "search for track", "find track", "search for", "search", "find"
    ]
    
    private func cancelPendingParametric() {
        pendingParametricTimer?.invalidate()
        pendingParametricTimer = nil
        pendingParametricCommand = nil
        pendingParametricTextCount = 0
    }
    
    private func commitPendingParametricCommand() {
        pendingParametricTimer?.invalidate()
        pendingParametricTimer = nil
        
        guard let command = pendingParametricCommand else { return }
        pendingParametricCommand = nil
        
        lastProcessedIndex = pendingParametricTextCount
        execute(command)
    }
    
    private func handleParametricInput(
        command: VoiceCommand?,
        livePreview: String,
        icon: String,
        textCount: Int,
        isFinal: Bool
    ) {
        triggerHUD(livePreview, icon: icon)
        pendingParametricCommand = command
        pendingParametricTextCount = textCount
        
        if isFinal, command != nil {
            commitPendingParametricCommand()
            return
        }
        
        pendingParametricTimer?.invalidate()
        let timer = Timer(timeInterval: 0.75, repeats: false) { [weak self] _ in
            self?.commitPendingParametricCommand()
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingParametricTimer = timer
    }
    
    private func findKeyword(in text: String, from keywords: [String]) -> (keyword: String, payload: String)? {
        let sorted = keywords.sorted { $0.count > $1.count }
        
        for kw in sorted {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(of: kw, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
                // Check character before keyword
                let isWordStart: Bool
                if range.lowerBound == text.startIndex {
                    isWordStart = true
                } else {
                    let prevChar = text[text.index(before: range.lowerBound)]
                    isWordStart = prevChar.isWhitespace || prevChar.isPunctuation
                }
                
                // Check character after keyword
                let isWordEnd: Bool
                if range.upperBound == text.endIndex {
                    isWordEnd = true
                } else {
                    let nextChar = text[range.upperBound]
                    isWordEnd = nextChar.isWhitespace || nextChar.isPunctuation
                }
                
                if isWordStart && isWordEnd {
                    let payload = String(text[range.upperBound...])
                        .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
                    return (kw, payload)
                }
                
                if range.upperBound >= text.endIndex {
                    break
                }
                searchStart = range.upperBound
            }
        }
        return nil
    }
    
    // MARK: - Wake Word Detection
    
    public func activeWakeWordVariants() -> [String] {
        let name = wakeWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let effectiveName = name.isEmpty ? "sound" : name
        var variants = Set<String>()
        variants.insert(effectiveName)
        
        if effectiveName == "sound" || effectiveName == "саунд" {
            variants.formUnion([
                "sound", "sounde", "sounds", "saund",
                "саунд", "саунде", "саунда", "саунду", "саундэ", "саундер", "соунд", "соунде", "санд"
            ])
        } else if effectiveName == "soundcloud" || effectiveName == "саундклауд" {
            variants.formUnion(["soundcloud", "саундклауд", "саундклауде"])
        } else {
            // Support standard Russian grammatical inflection endings for custom names
            if effectiveName.count >= 3 {
                variants.insert(effectiveName + "а")
                variants.insert(effectiveName + "е")
                variants.insert(effectiveName + "у")
                variants.insert(effectiveName + "я")
                if effectiveName.hasSuffix("а") || effectiveName.hasSuffix("я") {
                    let base = String(effectiveName.dropLast())
                    variants.insert(base)
                    variants.insert(base + "е")
                    variants.insert(base + "у")
                }
            }
        }
        return Array(variants).sorted { $0.count > $1.count }
    }
    
    private func findWakeWord(in text: String) -> (matchedWord: String, payload: String)? {
        let variants = activeWakeWordVariants()
        
        for variant in variants {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(of: variant, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
                // Word boundary check before
                let isWordStart: Bool
                if range.lowerBound == text.startIndex {
                    isWordStart = true
                } else {
                    let prevChar = text[text.index(before: range.lowerBound)]
                    isWordStart = prevChar.isWhitespace || prevChar.isPunctuation
                }
                
                // Word boundary check after
                let isWordEnd: Bool
                if range.upperBound == text.endIndex {
                    isWordEnd = true
                } else {
                    let nextChar = text[range.upperBound]
                    isWordEnd = nextChar.isWhitespace || nextChar.isPunctuation
                }
                
                if isWordStart && isWordEnd {
                    let matchedWord = String(text[range])
                    let payload = String(text[range.upperBound...])
                        .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
                    return (matchedWord, payload)
                }
                
                if range.upperBound >= text.endIndex {
                    break
                }
                searchStart = range.upperBound
            }
        }
        return nil
    }
    
    private func processTranscription(_ fullText: String, isFinal: Bool = false) {
        let text = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        if lastProcessedIndex < 0 || lastProcessedIndex > text.count {
            lastProcessedIndex = 0
        }
        
        let unprocessedCount = max(0, text.count - lastProcessedIndex)
        let unprocessed = String(text.suffix(unprocessedCount)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unprocessed.isEmpty else { return }
        let lower = unprocessed.lowercased()
        
        // 0. Check for explicit cancel if user says "отмена" while dictating
        if pendingParametricCommand != nil || pendingParametricTimer != nil {
            if lower.contains("отмена") || lower.contains("отменить") || lower.contains("cancel") {
                cancelPendingParametric()
                lastProcessedIndex = text.count
                wakeWordArmedUntil = .distantPast
                triggerHUD(NSLocalizedString("voice.hud.cancelled", comment: ""), icon: "xmark.circle")
                return
            }
        }
        
        // Determine the text to parse:
        // If requireWakeWord is true and we are not already dictating a parametric payload:
        let commandText: String
        if requireWakeWord && pendingParametricCommand == nil {
            let isArmed = wakeWordArmedUntil > Date()
            if let wake = findWakeWord(in: unprocessed) {
                // Wake word detected! Arm for 4 seconds in case of multi-turn speech
                wakeWordArmedUntil = Date().addingTimeInterval(4.0)
                
                if wake.payload.isEmpty {
                    // User only spoke the wake word so far (e.g. "Sound" / "Саунд")
                    triggerHUD(String(format: NSLocalizedString("voice.hud.listening", comment: ""), wakeWord), icon: "mic.fill")
                    if isFinal {
                        lastProcessedIndex = text.count
                    }
                    return
                } else {
                    commandText = wake.payload
                }
            } else if isArmed {
                // Assistant was armed recently (within 4s), treat unprocessed text as the command
                commandText = unprocessed
            } else {
                // Wake word not found and not armed -> ignore background speech completely
                return
            }
        } else {
            commandText = unprocessed
        }
        
        // 1. Check for parametric commands (Comment, Search, Share) FIRST.
        // This guarantees that any words inside the payload (e.g. "комент он репит", "найди non stop", "комент классная пауза", "лайкни")
        // are treated as text payload and NEVER trigger playback actions!
        
        // 1.1 Comment
        if let match = findKeyword(in: commandText, from: commentKeywords) {
            let commentText = match.payload
            handleParametricInput(
                command: commentText.isEmpty ? nil : .postComment(text: commentText),
                livePreview: commentText.isEmpty ? NSLocalizedString("voice.hud.commentPlaceholder", comment: "") : String(format: NSLocalizedString("voice.hud.commentPreview", comment: ""), commentText),
                icon: "bubble.left.fill",
                textCount: text.count,
                isFinal: isFinal
            )
            return
        }
        
        // 1.2 Search & Play
        if let match = findKeyword(in: commandText, from: searchKeywords) {
            let query = match.payload
            let qLower = query.lowercased()
            if !qLower.hasPrefix("волн") && !qLower.hasPrefix("лент") && !qLower.hasPrefix("лайк") && !qLower.hasPrefix("репост") {
                handleParametricInput(
                    command: query.isEmpty ? nil : .searchAndPlay(query: query),
                    livePreview: query.isEmpty ? NSLocalizedString("voice.hud.searchPlaceholder", comment: "") : String(format: NSLocalizedString("voice.hud.search", comment: ""), query),
                    icon: "magnifyingglass",
                    textCount: text.count,
                    isFinal: isFinal
                )
                return
            }
        }
        
        // 1.3 Share
        if let match = findKeyword(in: commandText, from: shareKeywords) {
            var target = match.payload
            if target.lowercased().hasPrefix("другу ") {
                target = String(target.dropFirst(6)).trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            } else if target.lowercased().hasPrefix("friend ") {
                target = String(target.dropFirst(7)).trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            }
            handleParametricInput(
                command: target.isEmpty ? nil : .shareTrack(targetName: target),
                livePreview: target.isEmpty ? NSLocalizedString("voice.hud.sharePlaceholder", comment: "") : String(format: NSLocalizedString("voice.hud.sharePreview", comment: ""), target),
                icon: "paperplane.fill",
                textCount: text.count,
                isFinal: isFinal
            )
            return
        }
        
        // 2. If we are currently dictating a parametric command and no new command was started,
        // do not let atomic commands interrupt dictation (e.g. user said "он репит" after a pause).
        if pendingParametricCommand != nil {
            if isFinal {
                commitPendingParametricCommand()
            }
            return
        }
        
        // 3. Check for immediate atomic commands ONLY when not dictating a comment/search/share
        if let atomicCmd = parseAtomicCommand(from: commandText) {
            cancelPendingParametric()
            wakeWordArmedUntil = .distantPast
            lastProcessedIndex = text.count
            execute(atomicCmd)
            return
        }
        
        // If final and we have a pending command with payload, commit it
        if isFinal {
            commitPendingParametricCommand()
        }
    }
    
    private func parseAtomicCommand(from text: String) -> VoiceCommand? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }
        
        // 1. Refresh Wave
        if containsAny(lower, [
            "обнови волну", "обновить волну", "перезапусти волну", "перемешай волну",
            "обнови поток", "обновить поток", "новый поток", "следующая волна",
            "refresh wave", "new wave", "reload wave"
        ]) {
            return .refreshWave
        }
        
        // 2. Play Wave (High priority before generic 'play')
        if containsAny(lower, [
            "моя волна", "мою волну", "вруби волну", "запусти волну", "включи волну",
            "включи мою волну", "вруби мою волну", "запусти мою волну", "поставь волну",
            "поставь мою волну", "волну", "волна", "радио", "включи радио",
            "my wave", "start wave", "wave", "play wave"
        ]) {
            return .playWave
        }
        
        // 3. Play Stream (Лента подписок)
        if containsAny(lower, [
            "включи ленту", "вруби ленту", "поставь ленту", "запусти ленту", "играй ленту",
            "моя лента", "лента", "поток", "включи поток", "вруби поток",
            "play stream", "stream", "play feed", "feed"
        ]) {
            return .playStream
        }
        
        // 4. Play Reposts
        if containsAny(lower, [
            "включи репосты", "вруби репосты", "поставь репосты", "запусти репосты",
            "мои репосты", "плейлист репосты", "слушать репосты", "треки из репостов",
            "play reposts", "play my reposts"
        ]) {
            return .playReposts
        }
        
        // 5. Play Likes (High priority before generic 'play' or 'like')
        if containsAny(lower, [
            "включи лайки", "вруби лайки", "включи любимое", "плей лайки",
            "мои лайки", "треки с лайками", "поставь лайки", "запусти лайки",
            "играй лайки", "слушать лайки", "плейлист лайки", "включи треки с лайками",
            "понравившиеся", "любимые треки", "включи понравившиеся", "включи понравилось",
            "любимые", "любимое", "включи любимые",
            "play likes", "play favorites", "liked tracks", "play my likes", "likes", "favorites"
        ]) {
            return .playLikes
        }
        
        // 6. Unrepost (Checked strictly before Repost)
        if containsAny(lower, [
            "убери репост", "убрать репост", "отмени репост", "отменить репост",
            "сними репост", "снять репост", "удали репост", "удалить репост",
            "удали из репостов", "убери из репостов", "дизрепост",
            "unrepost", "remove repost", "cancel repost", "delete repost"
        ]) {
            return .unrepost
        }
        
        // 7. Repost
        let isUnrepostIntent = containsAny(lower, ["убери", "сними", "удали", "отмени", "диз", "не ", "без "])
        let isPlayRepostsIntent = containsAny(lower, ["включи", "вруби", "запусти", "поставь", "слушать", "мои репосты", "плейлист"])
        if !isUnrepostIntent && !isPlayRepostsIntent && containsAny(lower, [
            "репост", "репостни", "сделай репост", "сделать репост", "поставь репост",
            "добавь в репосты", "поделись", "поделиться",
            "repost", "share track", "share this"
        ]) {
            return .repost
        }
        
        // 8. Unlike (Checked strictly before Like)
        if containsAny(lower, [
            "дизлайк", "дизлайкни", "дизлайкнуть",
            "убери лайк", "убрать лайк", "сними лайк", "снять лайк",
            "не нравится", "мне не нравится", "больше не нравится",
            "удали из любимых", "убери из любимых", "удали из избранного", "убери из избранного",
            "палец вниз",
            "unlike", "dislike", "remove like", "don't like", "thumbs down"
        ]) {
            return .unlike
        }
        
        // 9. Like
        let isUnlikeIntent = containsAny(lower, ["диз", "не ", "убери", "сними", "удали", "отмени", "без "])
        let isRepostMention = lower.contains("репост")
        let isPlaylistMention = lower.contains("плейлист") || lower.contains("альбом") || lower.contains("волн") || lower.contains("радио")
        let isPlayLikesMention = containsAny(lower, ["включи", "вруби", "запусти", "поставь", "плей", "играй", "слушать", "мои лайки", "любимые"])
        
        if !isUnlikeIntent && !isRepostMention && !isPlaylistMention && !isPlayLikesMention && containsAny(lower, [
            "лайк", "лайкни", "лайкнуть", "поставь лайк", "добавь лайк",
            "нравится", "мне нравится", "очень нравится",
            "в избранное", "добавь в избранное", "в любимое", "в любимые", "добавь в любимые",
            "сердечко", "поставь сердечко", "палец вверх",
            "like", "like this", "like track", "favorite", "love this", "thumbs up"
        ]) {
            return .like
        }
        
        // 10. Volume Up
        if containsAny(lower, [
            "громче", "прибавь", "плюс звук", "добавь звук", "погромче",
            "volume up", "louder", "turn up"
        ]) {
            return .volumeUp
        }
        
        // 11. Volume Down
        if containsAny(lower, [
            "тише", "убавь", "минус звук", "сделай тише", "потише",
            "volume down", "quieter", "lower", "turn down"
        ]) {
            return .volumeDown
        }
        
        // 12. Mute
        if containsAny(lower, [
            "без звука", "заглуши", "мут", "mute", "unmute"
        ]) {
            return .mute
        }
        
        // 13. Next track
        if containsAny(lower, [
            "следующий", "дальше", "след", "скип", "вперед", "вперёд",
            "некст", "след трек", "следующий трек", "next", "skip", "forward", "next track"
        ]) {
            return .nextTrack
        }
        
        // 14. Previous track
        if containsAny(lower, [
            "предыдущий", "назад", "прошлый", "прошлый трек", "предыдущий трек",
            "prev", "previous", "back"
        ]) {
            return .previousTrack
        }
        
        // 15. Shuffle
        if containsAny(lower, [
            "микс", "миксуй", "замиксуй", "сделай микс", "перемешай", "перемешка", "перемешать", "сделай перемешку", "шафл", "шаффл", "случайно", "рандом", "shuffle", "random", "mix"
        ]) {
            return .shuffle
        }
        
        // 16. Repeat
        if containsAny(lower, [
            "повтор", "повтори", "повторяй", "зацикли", "на повтор", "по кругу", "репит", "repeat", "loop"
        ]) {
            return .repeatQueue
        }
        
        // 17. Pause / Stop
        if containsAny(lower, [
            "пауза", "стоп", "останови", "погоди", "pause", "stop", "halt"
        ]) {
            return .pause
        }
        
        // 18. Play / Resume
        if containsAny(lower, [
            "играть", "включи", "продолжить", "старт", "плей", "play", "resume", "start"
        ]) {
            return .play
        }
        
        return nil
    }
    
    private func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        for phrase in phrases {
            if text.contains(phrase) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Execute Command
    
    private func execute(_ command: VoiceCommand) {
        let now = Date()
        // Prevent rapid duplicate triggers for the same command within 1.8s
        if command == lastExecutedCommand && now.timeIntervalSince(lastCommandTimestamp) < 1.8 {
            return
        }
        // General cooldown between different commands
        guard now.timeIntervalSince(lastCommandTimestamp) > 0.6 else { return }
        lastCommandTimestamp = now
        lastExecutedCommand = command
        
        // Show visual feedback HUD for static commands
        if command != .repeatQueue && command != .shuffle {
            triggerHUD(command.title, icon: command.icon)
        }
        
        // Play subtle system sound feedback
        NSSound(named: "Tink")?.play()
        
        let player = StreamPlayer.shared
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch command {
            case .nextTrack:
                player?.advanceForward()
            case .previousTrack:
                player?.advanceBackward()
            case .pause:
                if player?.isPlaying == true {
                    player?.togglePlayback()
                }
            case .play:
                if player?.isPlaying == false {
                    player?.togglePlayback()
                }
            case .volumeUp:
                if let p = player {
                    p.volume = min(1.0, p.volume + 0.12)
                }
            case .volumeDown:
                if let p = player {
                    p.volume = max(0.0, p.volume - 0.12)
                }
            case .mute:
                if let p = player {
                    p.volume = (p.volume > 0 ? 0 : 0.8)
                }
            case .like:
                NotificationCenter.default.post(name: .voiceControlLikeTrack, object: nil)
            case .unlike:
                NotificationCenter.default.post(name: .voiceControlUnlikeTrack, object: nil)
            case .playWave:
                NotificationCenter.default.post(name: .voiceControlPlayWave, object: nil)
            case .refreshWave:
                NotificationCenter.default.post(name: .voiceControlRefreshWave, object: nil)
            case .playStream:
                NotificationCenter.default.post(name: .voiceControlPlayStream, object: nil)
            case .shareTrack(let targetName):
                NotificationCenter.default.post(name: .voiceControlShareTrack, object: targetName)
            case .postComment(let text):
                NotificationCenter.default.post(name: .voiceControlPostComment, object: text)
            case .searchAndPlay(let query):
                NotificationCenter.default.post(name: .voiceControlSearchAndPlay, object: query)
            case .playLikes:
                NotificationCenter.default.post(name: .voiceControlPlayLikes, object: nil)
            case .repost:
                NotificationCenter.default.post(name: .voiceControlRepostTrack, object: nil)
            case .unrepost:
                NotificationCenter.default.post(name: .voiceControlUnrepostTrack, object: nil)
            case .playReposts:
                NotificationCenter.default.post(name: .voiceControlPlayReposts, object: nil)
            case .shuffle:
                if let p = player {
                    p.shuffleQueue.toggle()
                    let on = p.shuffleQueue
                    self.triggerHUD(on ? NSLocalizedString("voice.hud.shuffleOn", comment: "") : NSLocalizedString("voice.hud.shuffleOff", comment: ""), icon: "shuffle")
                }
            case .repeatQueue:
                if let p = player {
                    p.toggleRepeatMode()
                    switch p.repeatMode {
                    case .all:
                        self.triggerHUD(NSLocalizedString("voice.hud.repeatAll", comment: ""), icon: "repeat")
                    case .one:
                        self.triggerHUD(NSLocalizedString("voice.hud.repeatOne", comment: ""), icon: "repeat.1")
                    case .off:
                        self.triggerHUD(NSLocalizedString("voice.hud.repeatOff", comment: ""), icon: "repeat")
                    }
                }
            }
        }
    }
    
    // MARK: - HUD
    
    public func triggerCustomHUD(_ text: String, icon: String) {
        triggerHUD(text, icon: icon)
    }
    
    private func triggerHUD(_ text: String, icon: String) {
        guard showVoiceHUD else { return }
        DispatchQueue.main.async {
            self.currentHUDText = text
            self.currentHUDIcon = icon
            withAnimation(.easeInOut(duration: 0.18)) {
                self.isShowingHUD = true
            }
            
            self.hudDismissWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                withAnimation(.easeInOut(duration: 0.25)) {
                    self?.isShowingHUD = false
                }
            }
            self.hudDismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
        }
    }
}
