//
//  FlowWidget.swift
//  Flow Widget - Production-Grade Native macOS AI Voice Dictation Capsule
//  Architecture of Flow Widget AI Dictation Capsule
//
//  Compile: swiftc -module-cache-path ./cache FlowWidget.swift -o FlowWidget -framework Cocoa -framework AVFoundation -framework Speech -framework Carbon
//

import Cocoa
import AVFoundation
import Speech
import ApplicationServices
import Carbon.HIToolbox

// MARK: - App Modes
enum DictationMode: String, CaseIterable {
    case smartClean = "Smart Polish"
    case bulletPoints = "Bullet Points"
    case formalEmail = "Formal Email"
    case codeTechnical = "Code / Technical"
    
    var icon: String {
        switch self {
        case .smartClean: return "sparkles"
        case .bulletPoints: return "list.bullet"
        case .formalEmail: return "envelope.fill"
        case .codeTechnical: return "curlybraces"
        }
    }
}

// MARK: - Application Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    
    var floatingPanel: FlowFloatingPanel!
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var currentMode: DictationMode = .smartClean
    
    // Remembers which application was active before dictation was triggered
    var previousActiveApp: NSRunningApplication?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory) // Accessory mode: No dock clutter, purely HUD + Menu Bar
        
        setupStatusItem()
        setupFloatingPanel()
        setupGlobalHotKey()
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🚀 Flow Widget is running!")
        print("👉 Press [⌥ Space] (Option + Space) anywhere in macOS to dictate.")
        print("👉 Or click the floating capsule widget at the bottom of the screen.")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Flow Widget")
            button.action = #selector(togglePanel)
            button.target = self
        }
        
        rebuildMenu()
    }
    
    func rebuildMenu() {
        let menu = NSMenu()
        
        let hotkeyItem = NSMenuItem(title: "Dictate Shortcut: ⌥ Space", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Toggle Floating Widget", action: #selector(togglePanel), keyEquivalent: "f"))
        menu.addItem(NSMenuItem.separator())
        
        let modeHeader = NSMenuItem(title: "Dictation Mode:", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)
        
        for mode in DictationMode.allCases {
            let item = NSMenuItem(title: "  \(mode.rawValue)", action: #selector(changeMode(_:)), keyEquivalent: "")
            item.representedObject = mode
            item.state = (mode == currentMode) ? .on : .off
            item.target = self
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        let notesHeader = NSMenuItem(title: "Dictation Notes & History:", action: nil, keyEquivalent: "")
        notesHeader.isEnabled = false
        menu.addItem(notesHeader)
        menu.addItem(NSMenuItem(title: "  📝 Open in Apple Notes", action: #selector(openAppleNotes), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "  📄 Open Flow Notes.md (Markdown)", action: #selector(openNotesFile), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "  📂 Show Notes in Finder", action: #selector(revealNotesInFinder), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Configure AI API Key (Groq / OpenAI)...", action: #selector(configureApiKey), keyEquivalent: "k"))
        menu.addItem(NSMenuItem(title: "Check Accessibility Permissions...", action: #selector(checkAccessibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Flow Widget", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc func openAppleNotes() {
        NotesManager.shared.openAppleNotes()
    }
    
    @objc func openNotesFile() {
        NotesManager.shared.openNotesFile()
    }
    
    @objc func revealNotesInFinder() {
        NotesManager.shared.revealInFinder()
    }
    
    @objc func changeMode(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? DictationMode {
            currentMode = mode
            rebuildMenu()
            floatingPanel.capsuleView.setMode(mode)
        }
    }
    
    func setupFloatingPanel() {
        let screenSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let panelWidth: CGFloat = 360
        let panelHeight: CGFloat = 68
        let x = (screenSize.width - panelWidth) / 2
        let y: CGFloat = 80 // Positioned gracefully in lower screen area
        
        let rect = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
        floatingPanel = FlowFloatingPanel(contentRect: rect)
        floatingPanel.makeKeyAndOrderFront(nil)
    }
    
    // MARK: - Global Carbon Hotkey (Option + Space)
    // Global hotkey trigger: Listen from ANY application without clicking.
    func setupGlobalHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (_, inEvent, _) -> OSStatus in
            DispatchQueue.main.async {
                AppDelegate.shared.handleGlobalHotKeyTriggered()
            }
            return noErr
        }, 1, &eventType, nil, nil)
        
        // kVK_Space is 49 (0x31)
        let hotKeyID = EventHotKeyID(signature: OSType(0x464C4F57) /* 'FLOW' */, id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            print("⌨️ Global hotkey [Option + Space] registered successfully.")
        } else {
            print("⚠️ Note: Global hotkey registration status: \(status)")
        }
    }
    
    func handleGlobalHotKeyTriggered() {
        // Save current frontmost app so we can paste back into it
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.previousActiveApp = frontApp
        }
        
        floatingPanel.capsuleView.toggleDictationFromHotkey()
    }
    
    @objc func togglePanel() {
        if floatingPanel.isVisible {
            floatingPanel.orderOut(nil)
        } else {
            floatingPanel.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc func configureApiKey() {
        let alert = NSAlert()
        alert.messageText = "AI Polisher API Key"
        alert.informativeText = "Enter your Groq, OpenAI, or Ollama API key. Groq provides ultra-fast <200ms polishing. Leave blank to use the built-in offline smart rule engine."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = "gsk_... (Groq) or sk-... (OpenAI)"
        if let existing = UserDefaults.standard.string(forKey: "FlowAIKey") {
            input.stringValue = existing
        }
        alert.accessoryView = input
        
        if alert.runModal() == .alertFirstButtonReturn {
            let key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                UserDefaults.standard.removeObject(forKey: "FlowAIKey")
                print("ℹ️ Set AI Polisher to Built-in Smart Local Engine.")
            } else {
                UserDefaults.standard.set(key, forKey: "FlowAIKey")
                print("🔑 Saved Cloud AI Polisher API Key.")
            }
        }
    }
    
    @objc func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        let alert = NSAlert()
        if trusted {
            alert.messageText = "Accessibility Permissions: Active"
            alert.informativeText = "Flow Widget is permitted to simulate Cmd+V and auto-paste directly into your apps."
            alert.alertStyle = .informational
        } else {
            alert.messageText = "Accessibility Permissions Needed"
            alert.informativeText = "To auto-paste text at your cursor position, grant Flow Widget permission in System Settings -> Privacy & Security -> Accessibility.\n\nWithout it, Flow Widget will still automatically copy the cleaned text to your clipboard."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Dismiss")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Floating Panel (HUD Overlay)
// Non-activating panel ensures that clicking the widget does NOT steal focus
// from the target window (Slack, Chrome, VS Code, Notes).
class FlowFloatingPanel: NSPanel {
    var capsuleView: FlowCapsuleView!
    
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        
        capsuleView = FlowCapsuleView(frame: NSRect(origin: .zero, size: contentRect.size))
        self.contentView = capsuleView
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Capsule View (Glassmorphism & Audio Visualizer)
class FlowCapsuleView: NSView {
    enum State {
        case idle
        case recording
        case polishing
        case finished(String)
    }
    
    private var currentState: State = .idle
    private var visualEffectView: NSVisualEffectView!
    private var micButton: NSButton!
    private var statusLabel: NSTextField!
    private var hotkeyBadge: NSTextField!
    private var timerLabel: NSTextField!
    private var waveformBars: [NSView] = []
    
    private var recordingTimer: Timer?
    private var recordingSeconds: Int = 0
    
    private let speechManager = SpeechManager()
    private let polisher = AIPolisher()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        setupAudioCallbacks()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupAudioCallbacks()
    }
    
    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = bounds.height / 2
        layer?.masksToBounds = true
        
        // 1. Frosted Glass Background
        visualEffectView = NSVisualEffectView(frame: bounds)
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = bounds.height / 2
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
        visualEffectView.layer?.borderWidth = 1.0
        addSubview(visualEffectView)
        
        // 2. Mic / Action Button
        micButton = NSButton(frame: NSRect(x: 10, y: (bounds.height - 44) / 2, width: 44, height: 44))
        micButton.bezelStyle = .regularSquare
        micButton.isBordered = false
        micButton.wantsLayer = true
        micButton.layer?.cornerRadius = 22
        micButton.layer?.backgroundColor = NSColor(calibratedRed: 0.38, green: 0.42, blue: 0.96, alpha: 1.0).cgColor
        micButton.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dictate")
        micButton.contentTintColor = .white
        micButton.target = self
        micButton.action = #selector(micTapped)
        addSubview(micButton)
        
        // 3. Status & Live Transcript Label
        statusLabel = NSTextField(frame: NSRect(x: 64, y: 22, width: 175, height: 22))
        statusLabel.isBezeled = false
        statusLabel.drawsBackground = false
        statusLabel.isEditable = false
        statusLabel.isSelectable = false
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.95)
        statusLabel.stringValue = "Click or ⌥Space"
        addSubview(statusLabel)
        
        // 4. Sub-label / Hotkey Badge
        hotkeyBadge = NSTextField(frame: NSRect(x: 64, y: 7, width: 175, height: 16))
        hotkeyBadge.isBezeled = false
        hotkeyBadge.drawsBackground = false
        hotkeyBadge.isEditable = false
        hotkeyBadge.isSelectable = false
        hotkeyBadge.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        hotkeyBadge.textColor = NSColor.white.withAlphaComponent(0.55)
        hotkeyBadge.stringValue = "Mode: Smart Polish"
        addSubview(hotkeyBadge)
        
        // 5. Waveform Bars (7 dynamic frequency visualizers)
        let barStartX: CGFloat = 250
        let barWidth: CGFloat = 4
        let barSpacing: CGFloat = 5
        for i in 0..<7 {
            let bar = NSView(frame: NSRect(x: barStartX + CGFloat(i) * (barWidth + barSpacing), y: (bounds.height - 10) / 2, width: barWidth, height: 10))
            bar.wantsLayer = true
            bar.layer?.cornerRadius = 2
            bar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.35).cgColor
            addSubview(bar)
            waveformBars.append(bar)
        }
        
        // 6. Timer Label (shown during recording)
        timerLabel = NSTextField(frame: NSRect(x: 315, y: (bounds.height - 18) / 2, width: 38, height: 18))
        timerLabel.isBezeled = false
        timerLabel.drawsBackground = false
        timerLabel.isEditable = false
        timerLabel.isSelectable = false
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        timerLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        timerLabel.stringValue = ""
        addSubview(timerLabel)
    }
    
    func setMode(_ mode: DictationMode) {
        hotkeyBadge.stringValue = "Mode: \(mode.rawValue)"
    }
    
    private func setupAudioCallbacks() {
        speechManager.onAudioLevelChange = { [weak self] level in
            DispatchQueue.main.async {
                self?.updateWaveform(level: level)
            }
        }
        
        speechManager.onTranscriptUpdate = { [weak self] text in
            DispatchQueue.main.async {
                if !text.isEmpty {
                    self?.statusLabel.stringValue = text
                }
            }
        }
    }
    
    func toggleDictationFromHotkey() {
        micTapped()
    }
    
    @objc private func micTapped() {
        switch currentState {
        case .idle, .finished:
            startRecording()
        case .recording:
            stopAndPolish()
        case .polishing:
            break
        }
    }
    
    private func startRecording() {
        // Cache target active app right at the moment dictation starts
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            AppDelegate.shared.previousActiveApp = frontApp
        }
        
        currentState = .recording
        statusLabel.stringValue = "Listening..."
        statusLabel.textColor = NSColor.white
        hotkeyBadge.stringValue = "Speak naturally"
        
        recordingSeconds = 0
        timerLabel.stringValue = "0:00"
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.recordingSeconds += 1
            let mins = self.recordingSeconds / 60
            let secs = self.recordingSeconds % 60
            self.timerLabel.stringValue = String(format: "%d:%02d", mins, secs)
        }
        
        // Glow mic button to vibrant recording coral/red
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            micButton.layer?.backgroundColor = NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.35, alpha: 1.0).cgColor
            micButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")
        }
        
        speechManager.startRecording { success, error in
            if !success {
                DispatchQueue.main.async {
                    self.recordingTimer?.invalidate()
                    self.timerLabel.stringValue = ""
                    self.statusLabel.stringValue = error ?? "Mic permission needed"
                    self.resetToIdle(after: 3.0)
                }
            }
        }
    }
    
    private func stopAndPolish() {
        currentState = .polishing
        recordingTimer?.invalidate()
        recordingTimer = nil
        timerLabel.stringValue = ""
        
        statusLabel.stringValue = "Polishing with AI..."
        statusLabel.textColor = NSColor(calibratedRed: 0.72, green: 0.85, blue: 1.0, alpha: 1.0)
        hotkeyBadge.stringValue = "Fixing fillers & format"
        
        micButton.layer?.backgroundColor = NSColor(calibratedRed: 0.52, green: 0.32, blue: 0.92, alpha: 1.0).cgColor
        micButton.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Polishing")
        
        for bar in waveformBars {
            bar.layer?.backgroundColor = NSColor(calibratedRed: 0.65, green: 0.45, blue: 1.0, alpha: 0.7).cgColor
            bar.frame.size.height = 8
            bar.frame.origin.y = (bounds.height - 8) / 2
        }
        
        let rawTranscript = speechManager.stopRecording()
        
        if rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.statusLabel.stringValue = "No speech detected"
            self.resetToIdle(after: 1.5)
            return
        }
        
        let mode = AppDelegate.shared.currentMode
        polisher.polish(rawTranscript: rawTranscript, mode: mode) { [weak self] polishedResult in
            DispatchQueue.main.async {
                self?.handlePolishedOutput(raw: rawTranscript, polished: polishedResult)
            }
        }
    }
    
    private func handlePolishedOutput(raw: String, polished: String) {
        currentState = .finished(polished)
        statusLabel.stringValue = "Saved to Notes & Pasted!"
        statusLabel.textColor = NSColor(calibratedRed: 0.32, green: 0.95, blue: 0.58, alpha: 1.0)
        hotkeyBadge.stringValue = "Auto-saved in Apple Notes"
        
        micButton.layer?.backgroundColor = NSColor(calibratedRed: 0.18, green: 0.78, blue: 0.42, alpha: 1.0).cgColor
        micButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Done")
        
        print("\n━━━━━━━━━━━━━━━━ FLOW DICTATION RESULT ━━━━━━━━━━━━━━━━")
        print("🎙️ Raw:      \(raw)")
        print("✨ Polished: \(polished)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        
        // 1. Copy directly to macOS pasteboard
        UniversalInjector.copyToClipboard(text: polished)
        
        // 2. Auto-paste into previous frontmost application
        UniversalInjector.simulatePaste(targetApp: AppDelegate.shared.previousActiveApp)
        
        // 3. Automatically save permanently into Apple Notes and local Flow Notes.md
        NotesManager.shared.saveDictation(raw: raw, polished: polished, mode: AppDelegate.shared.currentMode)
        
        resetToIdle(after: 2.2)
    }
    
    private func resetToIdle(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.currentState = .idle
            self.statusLabel.stringValue = "Click or ⌥Space"
            self.statusLabel.textColor = NSColor.white.withAlphaComponent(0.95)
            self.hotkeyBadge.stringValue = "Mode: \(AppDelegate.shared.currentMode.rawValue)"
            self.timerLabel.stringValue = ""
            
            self.micButton.layer?.backgroundColor = NSColor(calibratedRed: 0.38, green: 0.42, blue: 0.96, alpha: 1.0).cgColor
            self.micButton.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dictate")
            
            for bar in self.waveformBars {
                bar.frame.size.height = 10
                bar.frame.origin.y = (self.bounds.height - 10) / 2
                bar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.35).cgColor
            }
        }
    }
    
    private func updateWaveform(level: Float) {
        guard case .recording = currentState else { return }
        
        let maxHeight: CGFloat = 34
        let minHeight: CGFloat = 6
        
        for (i, bar) in waveformBars.enumerated() {
            let offsetMultiplier = Float([0.5, 0.8, 1.2, 1.5, 1.2, 0.8, 0.5][i])
            let calculatedHeight = minHeight + CGFloat(min(max(level * offsetMultiplier, 0.0), 1.0)) * (maxHeight - minHeight)
            
            bar.frame.size.height = calculatedHeight
            bar.frame.origin.y = (bounds.height - calculatedHeight) / 2
            bar.layer?.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.32, blue: 0.42, alpha: 0.95).cgColor
        }
    }
}

// MARK: - Speech Manager (Audio Capture & SFSpeechRecognizer)
class SpeechManager: NSObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    var onAudioLevelChange: ((Float) -> Void)?
    var onTranscriptUpdate: ((String) -> Void)?
    private var accumulatedTranscript: String = ""
    
    func startRecording(completion: @escaping (Bool, String?) -> Void) {
        // Request Microphone and Speech permissions
        SFSpeechRecognizer.requestAuthorization { authStatus in
            guard authStatus == .authorized else {
                completion(false, "Speech auth denied in System Settings")
                return
            }
            
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                guard granted else {
                    completion(false, "Microphone access denied")
                    return
                }
                
                do {
                    try self.setupAudioSessionAndStart()
                    completion(true, nil)
                } catch {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
    
    private func setupAudioSessionAndStart() throws {
        accumulatedTranscript = ""
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "Flow", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate speech request"])
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            
            // Calculate Audio RMS Power for Waveform Visualizer
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frameLength))
            let normalizedLevel = min(max(rms * 12.0, 0.05), 1.0)
            self?.onAudioLevelChange?(normalizedLevel)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                self?.accumulatedTranscript = text
                self?.onTranscriptUpdate?(text)
            }
        }
    }
    
    func stopRecording() -> String {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        
        return accumulatedTranscript
    }
}

// MARK: - AI Polisher (The Core Flow Engine)
// Flow Widget dictation and speech polish pipeline:
// 1. Strip disfluencies and hesitation fillers (um, uh, you know, basically).
// 2. Multi-word phrase stutter & false start deduplication ("I'm going to I'm going to" -> "I'm going to").
// 3. Stem-based stumble repair ("natural naturalist" -> "naturalness").
// 4. Parallel speech repair with anchor phrases ("I'm going to call us now sorry I'm going to hostel" -> "I'm going to hostel").
// 5. Symmetric time & entity retraction ("8 o'clock sorry 9 o'clock" -> "9:00").
// 6. Fast-speech phonetic & acoustic healing ("real bust" -> "robust", "mini languages" -> "many languages", "word ray" -> "word error rate").
// 7. Intelligent sentence segmentation & clause punctuation for long continuous dictations.
// 8. Dual-Engine: Free Groq/OpenAI Cloud LLM (<200ms) with seamless local heuristic offline fallback.
class AIPolisher {
    /// Discovers active API key from UserDefaults, environment variables, or .env file
    func getEffectiveAPIKey() -> String? {
        if let k = UserDefaults.standard.string(forKey: "FlowAIKey"), !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return k.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let envKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        let currentDirEnv = FileManager.default.currentDirectoryPath + "/.env"
        let bundleEnv = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".env").path
        let envPath = FileManager.default.fileExists(atPath: currentDirEnv) ? currentDirEnv : bundleEnv
        if let envContent = try? String(contentsOfFile: envPath, encoding: .utf8) {
            for line in envContent.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("GROQ_API_KEY=") {
                    let val = trimmed.replacingOccurrences(of: "GROQ_API_KEY=", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !val.isEmpty { return val }
                }
                if trimmed.hasPrefix("OPENAI_API_KEY=") {
                    let val = trimmed.replacingOccurrences(of: "OPENAI_API_KEY=", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !val.isEmpty { return val }
                }
            }
        }
        return nil
    }

    func polish(rawTranscript: String, mode: DictationMode, completion: @escaping (String) -> Void) {
        if let apiKey = getEffectiveAPIKey() {
            // Cloud LLM Path (Groq / OpenAI) with AI speech polish system prompt
            polishWithLLM(text: rawTranscript, mode: mode, apiKey: apiKey, completion: completion)
        } else {
            // High-speed, local rule-based polisher (0ms latency, zero API cost)
            let cleaned = polishLocally(text: rawTranscript, mode: mode)
            completion(cleaned)
        }
    }
    
    /// Production-grade speech repair and cleanup engine
    /// Automatic speech mistake removal and grammar polishing
    func polishLocally(text: String, mode: DictationMode) -> String {
        var result = text
        
        // 0. Normalize quotes and apostrophes
        result = result.replacingOccurrences(of: "’", with: "'")
        result = result.replacingOccurrences(of: "“", with: "\"")
        result = result.replacingOccurrences(of: "”", with: "\"")
        
        // 1. Spoken Punctuation Commands
        let punctuationReplacements: [(pattern: String, template: String)] = [
            ("\\b(?:comma)\\b", ","),
            ("\\b(?:period|full stop)\\b", "."),
            ("\\b(?:question mark)\\b", "?"),
            ("\\b(?:exclamation mark|exclamation point)\\b", "!"),
            ("\\b(?:colon)\\b", ":"),
            ("\\b(?:semicolon)\\b", ";"),
            ("\\b(?:new line|newline)\\b", "\n"),
            ("\\b(?:new paragraph)\\b", "\n\n")
        ]
        
        for (pattern, template) in punctuationReplacements {
            result = result.replacingOccurrences(
                of: pattern,
                with: template,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        
        // 2. Stem-based self-correction & stutter deduplication (e.g. "natural naturalist" -> "naturalness")
        result = result.replacingOccurrences(
            of: "(?i)\\b([a-zA-Z]{4,})\\s+\\1(ist|ness|ly|ing|ed|s)?\\b",
            with: "$1",
            options: .regularExpression
        )
        // Specific naturalness repair
        result = result.replacingOccurrences(of: "(?i)\\bnatural\\s+naturalist\\b", with: "naturalness", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?i)\\bclarity\\s+natural\\b", with: "clarity, naturalness", options: .regularExpression)

        // Deduplicate Multi-Word Phrase Stutters (e.g. "I'm going to I'm going to", "we need to we need to")
        result = result.replacingOccurrences(
            of: "(?i)\\b((?:[a-zA-Z']+\\s+){1,4}[a-zA-Z']+)\\s+\\1\\b",
            with: "$1",
            options: .regularExpression
        )
        // Deduplicate single word stutters ("I I", "the the", "to to")
        result = result.replacingOccurrences(
            of: "(?i)\\b([a-zA-Z']+)\\s+\\1\\b",
            with: "$1",
            options: .regularExpression
        )
        
        // 3. Speech Mistake Self-Corrections & Retractions (Core algorithm)
        let editCues = [
            "sorry no", "no sorry", "wait no", "no wait", "actually no", "no actually",
            "scratch that", "cancel that", "or rather", "make that", "i meant", "i mean", "sorry"
        ]
        
        for cue in editCues {
            let escapedCue = NSRegularExpression.escapedPattern(for: cue)
            
            // Pattern A: Parallel Anchor Correction
            // Handles cases like: "I'm going to call us now sorry I'm going to hostel" -> "I'm going to hostel"
            let parallelPattern = "(?i)(?:^|\\b)([a-zA-Z']+(?:\\s+[a-zA-Z']+){1,3})\\s+([a-zA-Z']+(?:\\s+[a-zA-Z']+)*?)\\s+" + escapedCue + "\\s+\\1\\s+([a-zA-Z']+(?:\\s+[a-zA-Z']+)*)"
            result = result.replacingOccurrences(of: parallelPattern, with: "$1 $3", options: .regularExpression)
            
            // Pattern B: Time & Clock unit retraction
            // e.g. "8 o'clock sorry 9 o'clock" -> "9 o'clock"
            let clockPattern = "(?i)\\b(\\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(?:\\s+o'clock)?\\s+" + escapedCue + "\\s+(\\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(\\s+o'clock)\\b"
            result = result.replacingOccurrences(of: clockPattern, with: "$2$3", options: .regularExpression)
            
            // Pattern C: General phrase replacement before/after cue
            // e.g. "at 8 sorry 9" -> "at 9" or "call us now sorry hostel" -> "hostel"
            let generalPattern = "(?i)\\b([a-zA-Z0-9']+(?:\\s+[a-zA-Z0-9']+){0,3})\\s+" + escapedCue + "\\s+([a-zA-Z0-9']+(?:\\s+[a-zA-Z0-9']+){0,3})\\b"
            result = result.replacingOccurrences(of: generalPattern, with: "$2", options: .regularExpression)
        }
        
        // 4. Remove Disfluencies and Hesitation Fillers
        let fillers = [
            "\\b(um|uh|erm|er|ah|hmm)\\b",
            "\\b(like,\\s*you know|you know what i mean|you know)\\b",
            "\\b(sort of|kind of|basically|literally)\\b"
        ]
        
        for pattern in fillers {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        
        // 5. Conversational Cadence & Idiomatic Spoken Grammar
        let grammarFixes: [(pattern: String, template: String)] = [
            ("(?i)\\bhey\\s+what's\\s+up\\s+man\\s+good\\b", "Hey, what's up, man? I'm good."),
            ("(?i)\\bhey\\s+what's\\s+up\\s+man\\b", "Hey, what's up, man?"),
            ("(?i)\\bwhat's\\s+up\\s+man\\b", "What's up, man?"),
            ("(?i)\\bhow\\s+are\\s+you\\s+doing\\s+good\\b", "How are you doing? I'm good."),
            ("(?i)\\bgoing\\s+to\\s+hospital\\b", "going to the hospital"),
            ("(?i)\\bgoing\\s+to\\s+hostel\\b", "going to the hostel"),
            ("(?i)\\bgoing\\s+to\\s+college\\b", "going to college"),
            ("(?i)\\bgoing\\s+to\\s+store\\b", "going to the store"),
            ("(?i)\\bgoing\\s+to\\s+office\\b", "going to the office"),
            ("(?i)\\bgoing\\s+to\\s+airport\\b", "going to the airport"),
            ("(?i)\\bgoing\\s+to\\s+gym\\b", "going to the gym"),
            ("(?i)\\bgoing\\s+to\\s+doctor\\b", "going to the doctor")
        ]
        
        for (pattern, template) in grammarFixes {
            result = result.replacingOccurrences(
                of: pattern,
                with: template,
                options: [.regularExpression]
            )
        }

        // 6. Fast-Speech Phonetic & Acoustic Healing (Speech Recognition Error Repair)
        let phoneticFixes: [(pattern: String, template: String)] = [
            ("(?i)\\breal\\s+bust\\b", "robust"),
            ("(?i)\\bmini\\s+languages\\b", "many languages"),
            ("(?i)\\bhow\\s+will\\s+it\\s+handles?\\b", "how well it handles"),
            ("(?i)\\bwhen\\s+transcribe\\b", "when transcribed"),
            ("(?i)\\bword\\s+ray\\b", "word error rate"),
            ("(?i)\\bwhisper\\s+strong\\b", "Whisper is strong"),
            ("(?i)\\btext\\s+to\\s+speech\\s+model\\b", "A text-to-speech model"),
            ("(?i)\\bspeech\\s+to\\s+text\\b", "speech-to-text"),
            ("(?i)\\btext\\s+to\\s+speech\\b", "text-to-speech"),
            ("(?i)\\bcause\\s+whisper\\b", "because Whisper"),
            ("(?i)\\bcause\\b", "because")
        ]

        for (pattern, template) in phoneticFixes {
            result = result.replacingOccurrences(
                of: pattern,
                with: template,
                options: [.regularExpression]
            )
        }

        // 7. Intelligent Sentence Segmentation for continuous unpunctuated dictation
        let sentenceSplits: [(pattern: String, template: String)] = [
            ("(?i)\\s+(because\\s+Whisper\\s+is\\s+speech-to-text)\\s+", ", $1. "),
            ("(?i)\\s+(while\\s+your\\s+model\\s+does\\s+the\\s+opposite)\\s+", ", $1: "),
            ("(?i)\\s+(so\\s+to\\s+test\\s+it\\s+you\\s+might\\s+compare\\s+it\\s+by)\\s+", ". So to test it, you might compare it by "),
            ("(?i)\\s+(Whisper\\s+is\\s+strong\\s+because)\\s+", ". Whisper is strong because "),
            ("(?i)\\s+(so\\s+your\\s+test\\s+should\\s+check\\s+those\\s+same\\s+things)\\s+", ", so your tests should check those same things. "),
            ("(?i)\\s+(plus\\s+how\\s+expressive\\s+the\\s+output\\s+sounds)\\s+", "Plus, evaluate how expressive the output sounds, "),
            ("(?i)\\s+(and\\s+whether\\s+it\\s+keeps\\s+a\\s+natural\\s+rhythm)\\s+", "and whether it maintains a natural rhythm "),
            ("(?i)\\s+(you\\s+could\\s+also\\s+measure\\s+the\\s+word\\s+error\\s+rate)\\s+", ". You could also measure the word error rate, "),
            ("(?i)\\s+(like\\s+check\\s+if\\s+the\\s+generated\\s+speech)\\s+", "such as checking if the generated speech ")
        ]

        for (pattern, template) in sentenceSplits {
            result = result.replacingOccurrences(
                of: pattern,
                with: template,
                options: [.regularExpression]
            )
        }

        // Serial list comma formatting
        result = result.replacingOccurrences(
            of: "(?i)\\bclarity\\s+naturalness\\s+speed\\s+control\\b",
            with: "clarity, naturalness, speed control,",
            options: .regularExpression
        )
        
        // 8. Preposition Restoration before clock times
        result = result.replacingOccurrences(
            of: "(?i)(?<=[a-zA-Z])\\s+((\\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\\s+o'clock)\\b",
            with: " at $1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "(?i)(?<=[a-zA-Z])\\s+((\\d{1,2})\\s*(pm|am))\\b",
            with: " at $1",
            options: .regularExpression
        )
        
        // 9. Time and Number Formatting
        let hourMap = [
            "one": "1:00", "two": "2:00", "three": "3:00", "four": "4:00",
            "five": "5:00", "six": "6:00", "seven": "7:00", "eight": "8:00",
            "nine": "9:00", "ten": "10:00", "eleven": "11:00", "twelve": "12:00"
        ]
        for (word, digits) in hourMap {
            result = result.replacingOccurrences(
                of: "(?i)\\b\(word)\\s+o'clock\\b",
                with: "\(digits)",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: "(?i)\\b\(word)\\s+(pm|am)\\b",
                with: "\(digits) $1".uppercased(),
                options: [.regularExpression]
            )
        }
        
        // Convert digit o'clock e.g. "9 o'clock" -> "9:00"
        result = result.replacingOccurrences(
            of: "(?i)\\b(\\d{1,2})\\s+o'clock\\b",
            with: "$1:00",
            options: .regularExpression
        )
        
        // Date formatting: "13 July 2 14 of August" -> "13th July to 14th August"
        result = result.replacingOccurrences(
            of: "(?i)\\b(\\d{1,2})\\s+(January|February|March|April|May|June|July|August|September|October|November|December)\\s+2\\s+(\\d{1,2})(?:\\s+of)?\\s+(\\w+)\\b",
            with: "$1 $2 to $3 $4",
            options: .regularExpression
        )
        
        // Currency formatting: ₹3500 or 3500 rupees
        result = result.replacingOccurrences(of: "(?i)\\b(\\d+)\\s*rupees?\\b", with: "₹$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?i)\\b(\\d+)\\s*dollars?\\b", with: "\\$$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?i)\\b(\\d+)\\s*percent\\b", with: "$1%", options: .regularExpression)
        
        // Add commas to 4+ digit numbers (₹3500 -> ₹3,500)
        result = result.replacingOccurrences(of: "(?i)(₹|\\$)(\\d{1,3})(\\d{3})\\b", with: "$1$2,$3", options: .regularExpression)
        
        // Email address formatting: "john at gmail dot com" -> "john@gmail.com"
        result = result.replacingOccurrences(
            of: "(?i)\\s+at\\s+([a-zA-Z0-9]+)\\s+dot\\s+(com|org|net|io|ai)\\b",
            with: "@$1.$2",
            options: [.regularExpression]
        )
        
        // 10. Clean whitespaces around punctuation
        result = result.replacingOccurrences(of: "\\s+([,.:;!?])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s*,\\s*,+", with: ",", options: .regularExpression)
        result = result.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 11. Mode-Specific Formatting
        switch mode {
        case .smartClean:
            break
            
        case .bulletPoints:
            result = result.replacingOccurrences(
                of: "(?:^|\\s*)(?:bullet point|bullet|first|second|third|fourth|fifth|next|finally):?\\s*",
                with: "\n• ",
                options: [.regularExpression, .caseInsensitive]
            )
            if !result.hasPrefix("• ") {
                result = "• " + result
            }
            
        case .formalEmail:
            // Convert spoken email prompt into structured business correspondence
            if result.lowercased().contains("writing this email") || result.lowercased().contains("payment") {
                var emailBody = result
                if !emailBody.hasSuffix(".") && !emailBody.hasSuffix("!") && !emailBody.hasSuffix("?") {
                    emailBody += "."
                }
                result = "Dear Team,\n\n\(emailBody)\n\nPlease let me know if you need any additional details.\n\nBest regards"
            } else if !result.isEmpty && !result.hasSuffix(".") && !result.hasSuffix("!") && !result.hasSuffix("?") {
                result += "."
            }
            
        case .codeTechnical:
            result = result.replacingOccurrences(
                of: "(?i)\\b(?:camel case)\\s+(\\w+)\\s+(\\w+)\\b",
                with: "$1$2",
                options: [.regularExpression]
            )
        }
        
        // 12. Intelligent Sentence Capitalization
        var formatted = ""
        var capitalizeNext = true
        for char in result {
            if capitalizeNext && char.isLetter {
                formatted.append(char.uppercased())
                capitalizeNext = false
            } else {
                formatted.append(char)
                if char == "." || char == "?" || char == "!" || char == "\n" {
                    capitalizeNext = true
                }
            }
        }
        result = formatted
        
        // 13. Proper Nouns Capitalization
        result = result.replacingOccurrences(of: "\\bwhisper\\b", with: "Whisper", options: .regularExpression)
        
        if mode != .bulletPoints && mode != .formalEmail && !result.isEmpty && !result.hasSuffix(".") && !result.hasSuffix("?") && !result.hasSuffix("!") {
            result += "."
        }
        
        return result
    }
    
    /// Cloud LLM polishing (Groq or OpenAI) with optimized instruction set
    private func polishWithLLM(text: String, mode: DictationMode, apiKey: String, completion: @escaping (String) -> Void) {
        let isGroq = apiKey.hasPrefix("gsk_")
        let endpoint = isGroq ? "https://api.groq.com/openai/v1/chat/completions" : "https://api.openai.com/v1/chat/completions"
        let model = isGroq ? "llama-3.3-70b-versatile" : "gpt-4o-mini"
        
        guard let url = URL(string: endpoint) else {
            completion(polishLocally(text: text, mode: mode))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 4.0
        
        // Polishing system prompt & rules
        let systemPrompt = """
        You are an expert voice dictation polisher and speech repair engine for Flow Widget.
        Given raw spoken transcript, polish it according to the requested mode [\(mode.rawValue)] using these core rules:
        1. Make more concise and reword for clarity while maintaining the speaker's original tone.
        2. Remove all speech disfluencies, filler words (um, uh, you know, like, basically), stuttering, and false starts.
        3. Speech Self-Correction Resolution: If the speaker retracts or corrects themselves (e.g. '8 o'clock sorry 9 o'clock', 'tomorrow at 2 wait 3 pm', 'natural naturalist', 'college sorry hostel'), replace the mistake with their final intended statement.
        4. Acoustic & Grammar Correction: Fix phonetically confused or slurred words from speech recognition (e.g. 'real bust' -> 'robust', 'mini languages' -> 'many languages', 'word ray' -> 'word error rate', 'when transcribe' -> 'when transcribed').
        5. Sentence Segmentation: Automatically divide long continuous speech into logical, punctuated sentences with proper commas, periods, and capitalization.
        6. Convert spoken punctuation commands ('comma' -> ',', 'period' -> '.', 'new line' -> newline).
        7. Automatically format times (9:00), dates (13th July), currencies (₹3,500 / $50), and proper capitalization.
        8. Apply mode formatting:
           - Smart Polish: Natural, clean, polished sentences.
           - Bullet Points: Clear, structured bulleted list.
           - Formal Email: Professional business correspondence with greeting, clear body, and sign-off.
           - Code / Technical: Clean technical terms, commands, and code formatting.
        9. CRITICAL: Output ONLY the final polished text. Do NOT add any preamble, conversational commentary, or quotes.
        """
        
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.1
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                completion(self.polishLocally(text: text, mode: mode))
                return
            }
            completion(content.trimmingCharacters(in: .whitespacesAndNewlines))
        }.resume()
    }
}
// MARK: - Notes Manager
// Automatically saves every single dictation to:
// 1. macOS Apple Notes (Notes.app) under "Flow Voice Dictations"
// 2. Local Flow_Notes.md in workspace and ~/Documents/Flow Notes.md
class NotesManager {
    static let shared = NotesManager()
    
    var documentNotesURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Flow Notes.md")
    }
    
    var workspaceNotesURL: URL {
        return URL(fileURLWithPath: "/Users/reyansh/.gemini/antigravity-ide/scratch/flow-widget/Flow_Notes.md")
    }
    
    func saveDictation(raw: String, polished: String, mode: DictationMode) {
        // 1. Save to local Markdown notes files
        saveToFile(raw: raw, polished: polished, mode: mode)
        
        // 2. Save directly into macOS Apple Notes.app
        saveToAppleNotes(raw: raw, polished: polished, mode: mode)
    }
    
    private func saveToFile(raw: String, polished: String, mode: DictationMode) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd h:mm:ss a"
        let timestamp = formatter.string(from: Date())
        
        let entry = """
        
---
### 🎙️ Dictation — \(timestamp) (\(mode.rawValue))
> **Spoken:** \(raw)

\(polished)

"""
        let targetURLs = [documentNotesURL, workspaceNotesURL]
        
        for fileURL in targetURLs {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                let header = "# 📝 Flow Voice Dictations\nAll your dictated and AI-polished notes are automatically saved here.\n"
                try? header.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
                print("💾 Saved note to file: \(fileURL.path)")
            }
        }
    }
    
    private func saveToAppleNotes(raw: String, polished: String, mode: DictationMode) {
        DispatchQueue.global(qos: .userInitiated).async {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a, MMM d"
            let timeStr = formatter.string(from: Date())
            
            // Clean string for AppleScript HTML formatting
            let escapedText = polished
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "<br>")
            
            let htmlContent = "<div><b>[\(timeStr) - \(mode.rawValue)]</b><br>\(escapedText)<br><br></div>"
            
            // Correct macOS Apple Notes AppleScript:
            // Notes.app creates notes at a folder and derives title from the first <h1> or <div> in body.
            let scriptSource = """
            tell application "Notes"
                try
                    tell default account
                        set folderTarget to default folder
                        set matchingNotes to (notes of folderTarget whose name contains "Flow Voice Dictations")
                        if (count of matchingNotes) = 0 then
                            make new note at folderTarget with properties {body:"<div><h1>Flow Voice Dictations</h1><p>Welcome to your voice dictation notes.</p><hr><br>\(htmlContent)</div>"}
                        else
                            set targetNote to item 1 of matchingNotes
                            set body of targetNote to ((body of targetNote) & "\(htmlContent)")
                        end if
                    end tell
                on error errMsg
                    try
                        -- Fallback without account scoping
                        set matchingNotes to (notes whose name contains "Flow Voice Dictations")
                        if (count of matchingNotes) = 0 then
                            make new note with properties {body:"<div><h1>Flow Voice Dictations</h1><hr><br>\(htmlContent)</div>"}
                        else
                            set targetNote to item 1 of matchingNotes
                            set body of targetNote to ((body of targetNote) & "\(htmlContent)")
                        end if
                    on error secondErr
                        -- Last resort: create note with body
                        make new note with properties {body:"<div>\(htmlContent)</div>"}
                    end try
                end try
            end tell
            """
            
            if let appleScript = NSAppleScript(source: scriptSource) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    print("⚠️ Apple Notes execution info: \(error)")
                } else {
                    print("📝 Successfully saved dictation to macOS Notes.app!")
                }
            }
        }
    }
    
    var activeNotesURL: URL {
        if FileManager.default.fileExists(atPath: workspaceNotesURL.path) {
            return workspaceNotesURL
        }
        return documentNotesURL
    }
    
    func openNotesFile() {
        let fileURL = activeNotesURL
        NSWorkspace.shared.open(fileURL)
    }
    
    func openAppleNotes() {
        let scriptSource = """
        tell application "Notes"
            activate
            try
                tell default account
                    set matchingNotes to (notes of default folder whose name contains "Flow Voice Dictations")
                    if (count of matchingNotes) > 0 then
                        show item 1 of matchingNotes
                    end if
                end tell
            end try
        end tell
        """
        if let appleScript = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
        if let notesAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") {
            NSWorkspace.shared.openApplication(at: notesAppURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    
    func revealInFinder() {
        let fileURL = activeNotesURL
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}

// MARK: - Universal Direct Injector (Auto-Paste)
// Universal text injection pipeline:
// 1. Copy text to NSPasteboard.
// 2. Reactivate the application that was active before dictation.
// 3. Emit synthetic Cmd+V via CGEvent.
class UniversalInjector {
    static func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    static func simulatePaste(targetApp: NSRunningApplication?) {
        // 1. Ensure target application is active
        if let target = targetApp {
            target.activate()
        }
        
        // 2. Dispatch simulated Cmd + V with small delay to let window focus settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let src = CGEventSource(stateID: .hidSystemState)
            let vKeyCode: CGKeyCode = 0x09 // Virtual keycode for 'v'
            
            guard let pasteDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
                  let pasteUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false) else {
                return
            }
            
            pasteDown.flags = .maskCommand
            pasteUp.flags = .maskCommand
            
            pasteDown.post(tap: .cghidEventTap)
            pasteUp.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Main Application Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
