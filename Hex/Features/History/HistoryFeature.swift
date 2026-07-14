import AVFoundation
import AppKit
import ComposableArchitecture
import Dependencies
import HexCore
import Inject
import SwiftUI

private let historyLogger = HexLog.history

// MARK: - Date Extensions

extension Date {
	func relativeFormatted() -> String {
		let calendar = Calendar.current
		let now = Date()
		
		if calendar.isDateInToday(self) {
			return "Today"
		} else if calendar.isDateInYesterday(self) {
			return "Yesterday"
		} else if let daysAgo = calendar.dateComponents([.day], from: self, to: now).day, daysAgo < 7 {
			let formatter = DateFormatter()
			formatter.dateFormat = "EEEE" // Day of week
			return formatter.string(from: self)
		} else {
			let formatter = DateFormatter()
			formatter.dateStyle = .medium
			formatter.timeStyle = .none
			return formatter.string(from: self)
		}
	}
}

// MARK: - Models

extension SharedReaderKey
	where Self == FileStorageKey<TranscriptionHistory>.Default
{
	static var transcriptionHistory: Self {
		Self[
			.fileStorage(.transcriptionHistoryURL),
			default: .init()
		]
	}
}

// MARK: - Storage Migration

extension URL {
	static var transcriptionHistoryURL: URL {
		get {
			URL.hexMigratedFileURL(named: "transcription_history.json")
		}
	}
}

class AudioPlayerController: NSObject, AVAudioPlayerDelegate {
	private var player: AVAudioPlayer?
	private let (playbackFinishedStream, playbackFinishedContinuation) = AsyncStream<Void>.makeStream()

	func play(url: URL) throws {
		let player = try AVAudioPlayer(contentsOf: url)
		player.delegate = self
		self.player = player
		player.play()
	}

	func stop() {
		player?.stop()
		player = nil
		finishPlayback()
	}

	func waitForPlaybackToFinish() async {
		for await _ in playbackFinishedStream {}
	}

	// AVAudioPlayerDelegate method
	func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
		guard self.player === player else { return }
		self.player = nil
		finishPlayback()
	}

	private func finishPlayback() {
		playbackFinishedContinuation.finish()
	}
}

// MARK: - History Feature

@Reducer
struct HistoryFeature {
	@ObservableState
	struct State: Equatable {
		@Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
		@Shared(.hexSettings) var hexSettings: HexSettings
		var playingTranscriptID: UUID?
		var playbackID: UUID?
		var audioPlayerController: AudioPlayerController?
		/// Number of dictionary entries learned from the most recent transcript edit,
		/// keyed by transcript so the row can show transient "Learned N" feedback.
		var lastLearnedCount: [UUID: Int] = [:]

		mutating func stopAudioPlayback() {
			audioPlayerController?.stop()
			audioPlayerController = nil
			playingTranscriptID = nil
			playbackID = nil
		}
	}

	enum Action {
		case playTranscript(UUID)
		case stopPlayback
		case copyToClipboard(String)
		case deleteTranscript(UUID)
		case deleteAllTranscripts
		case confirmDeleteAll
		case playbackFinished(UUID)
		case navigateToSettings
		case saveTranscriptEdit(id: UUID, newText: String)
		case clearLearnedBadge(UUID)
	}

	@Dependency(\.pasteboard) var pasteboard
	@Dependency(\.transcriptPersistence) var transcriptPersistence

	private func deleteAudioEffect(for transcripts: [Transcript]) -> Effect<Action> {
		.run { [transcriptPersistence] _ in
			for transcript in transcripts {
				try? await transcriptPersistence.deleteAudio(transcript)
			}
		}
	}

	var body: some ReducerOf<Self> {
		Reduce { state, action in
			switch action {
			case let .playTranscript(id):
				if state.playingTranscriptID == id {
					// Stop playback if tapping the same transcript
					state.stopAudioPlayback()
					return .none
				}

				// Stop any existing playback
				state.stopAudioPlayback()

				// Find the transcript and play its audio
				guard let transcript = state.transcriptionHistory.history.first(where: { $0.id == id }) else {
					return .none
				}

				do {
					let controller = AudioPlayerController()
					try controller.play(url: transcript.audioPath)
					let playbackID = UUID()

					state.audioPlayerController = controller
					state.playingTranscriptID = id
					state.playbackID = playbackID

					return .run { send in
						await controller.waitForPlaybackToFinish()
						await send(.playbackFinished(playbackID))
					}
				} catch {
					historyLogger.error("Failed to play audio: \(error.localizedDescription)")
					return .none
				}

			case .stopPlayback:
				state.stopAudioPlayback()
				return .none

			case let .playbackFinished(playbackID):
				guard state.playbackID == playbackID else { return .none }
				state.stopAudioPlayback()
				return .none

			case let .copyToClipboard(text):
				return .run { [pasteboard] _ in
					await pasteboard.copy(text)
				}

			case let .deleteTranscript(id):
				guard let index = state.transcriptionHistory.history.firstIndex(where: { $0.id == id }) else {
					return .none
				}

				let transcript = state.transcriptionHistory.history[index]

				if state.playingTranscriptID == id {
					state.stopAudioPlayback()
				}

				_ = state.$transcriptionHistory.withLock { history in
					history.history.remove(at: index)
				}

				return deleteAudioEffect(for: [transcript])

			case .deleteAllTranscripts:
				return .send(.confirmDeleteAll)

			case .confirmDeleteAll:
				let transcripts = state.transcriptionHistory.history
				state.stopAudioPlayback()

				state.$transcriptionHistory.withLock { history in
					history.history.removeAll()
				}

				return deleteAudioEffect(for: transcripts)
				
			case .navigateToSettings:
				// This will be handled by the parent reducer
				return .none

			case let .saveTranscriptEdit(id, newText):
				guard let index = state.transcriptionHistory.history.firstIndex(where: { $0.id == id }) else {
					return .none
				}
				let original = state.transcriptionHistory.history[index].text
				let edited = newText.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !edited.isEmpty, edited != original else { return .none }

				state.$transcriptionHistory.withLock { history in
					history.history[index].text = edited
				}

				// Learn-from-corrections: word substitutions in the user's edit become
				// dictionary entries so future transcripts get them automatically.
				guard state.hexSettings.learnFromCorrectionsEnabled else { return .none }
				let learned = CorrectionLearner.learnEntries(
					original: original,
					edited: edited,
					existing: state.hexSettings.tuningDictionary
				)
				guard !learned.isEmpty else { return .none }

				state.$hexSettings.withLock { settings in
					settings.tuningDictionary.append(contentsOf: learned)
					// The dictionary only applies when enabled; learning implies intent.
					settings.tuningDictionaryEnabled = true
				}
				state.lastLearnedCount[id] = learned.count
				historyLogger.info("Learned \(learned.count) dictionary entrie(s) from transcript edit")

				return .run { send in
					try await Task.sleep(for: .seconds(3))
					await send(.clearLearnedBadge(id))
				}

			case let .clearLearnedBadge(id):
				state.lastLearnedCount[id] = nil
				return .none
			}
		}
	}
}

struct TranscriptView: View {
	let transcript: Transcript
	let isPlaying: Bool
	let learnedCount: Int?
	let onPlay: () -> Void
	let onCopy: () -> Void
	let onDelete: () -> Void
	let onSaveEdit: (String) -> Void

	@State private var isEditing = false
	@State private var editedText = ""
	@FocusState private var editorFocused: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			if isEditing {
				TextEditor(text: $editedText)
					.font(.body)
					.scrollContentBackground(.hidden)
					.frame(minHeight: 60)
					.padding(8)
					.focused($editorFocused)
					.onKeyPress(.escape) {
						cancelEditing()
						return .handled
					}
				HStack(spacing: 8) {
					Spacer()
					Button("Cancel") { cancelEditing() }
						.buttonStyle(.plain)
						.foregroundStyle(.secondary)
					Button("Save") { commitEditing() }
						.buttonStyle(.borderedProminent)
						.controlSize(.small)
						.disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}
				.padding(.horizontal, 12)
				.padding(.bottom, 8)
			} else {
				Text(transcript.text)
					.font(.body)
					.lineLimit(nil)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.trailing, 40) // Space for buttons
					.padding(12)
			}

			Divider()

			HStack {
				HStack(spacing: 6) {
					// App icon and name
					if let bundleID = transcript.sourceAppBundleID,
					   let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
						Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
							.resizable()
							.frame(width: 14, height: 14)
						if let appName = transcript.sourceAppName {
							Text(appName)
						}
						Text("•")
					}
					
					Image(systemName: "clock")
					Text(transcript.timestamp.relativeFormatted())
					Text("•")
					Text(transcript.timestamp.formatted(date: .omitted, time: .shortened))
					Text("•")
					Text(String(format: "%.1fs", transcript.duration))
				}
				.font(.subheadline)
				.foregroundStyle(.secondary)

				Spacer()

				HStack(spacing: 10) {
					if let learnedCount {
						Label("Learned \(learnedCount)", systemImage: "character.book.closed.fill")
							.font(.caption)
							.foregroundStyle(.green)
							.help("Added \(learnedCount) correction(s) to the Dictionary")
							.transition(.opacity)
					}

					Button {
						startEditing()
					} label: {
						Image(systemName: "pencil")
					}
					.buttonStyle(.plain)
					.foregroundStyle(isEditing ? .blue : .secondary)
					.help("Edit transcript (corrections teach the Dictionary)")

					Button {
						onCopy()
						showCopyAnimation()
					} label: {
						HStack(spacing: 4) {
							Image(systemName: showCopied ? "checkmark" : "doc.on.doc.fill")
							if showCopied {
								Text("Copied").font(.caption)
							}
						}
					}
					.buttonStyle(.plain)
					.foregroundStyle(showCopied ? .green : .secondary)
					.help("Copy to clipboard")

					Button(action: onPlay) {
						Image(systemName: isPlaying ? "stop.fill" : "play.fill")
					}
					.buttonStyle(.plain)
					.foregroundStyle(isPlaying ? .blue : .secondary)
					.help(isPlaying ? "Stop playback" : "Play audio")

					Button(action: onDelete) {
						Image(systemName: "trash.fill")
					}
					.buttonStyle(.plain)
					.foregroundStyle(.secondary)
					.help("Delete transcript")
				}
				.font(.subheadline)
			}
			.frame(height: 20)
			.padding(.horizontal, 12)
			.padding(.vertical, 6)
		}
		.background(
			RoundedRectangle(cornerRadius: 8)
				.fill(Color(.windowBackgroundColor).opacity(0.5))
				.overlay(
					RoundedRectangle(cornerRadius: 8)
						.strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
				)
		)
		.onDisappear {
			// Clean up any running task when view disappears
			copyTask?.cancel()
		}
	}

	@State private var showCopied = false
	@State private var copyTask: Task<Void, Error>?

	private func startEditing() {
		editedText = transcript.text
		isEditing = true
		editorFocused = true
	}

	private func cancelEditing() {
		isEditing = false
		editedText = ""
	}

	private func commitEditing() {
		let text = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
		isEditing = false
		editedText = ""
		guard !text.isEmpty, text != transcript.text else { return }
		onSaveEdit(text)
	}

	private func showCopyAnimation() {
		copyTask?.cancel()

		copyTask = Task {
			withAnimation {
				showCopied = true
			}

			try await Task.sleep(for: .seconds(1.5))

			withAnimation {
				showCopied = false
			}
		}
	}
}

#Preview {
	TranscriptView(
		transcript: Transcript(timestamp: Date(), text: "Hello, world!", audioPath: URL(fileURLWithPath: "/Users/langton/Downloads/test.m4a"), duration: 1.0),
		isPlaying: false,
		learnedCount: nil,
		onPlay: {},
		onCopy: {},
		onDelete: {},
		onSaveEdit: { _ in }
	)
}

struct HistoryView: View {
	@ObserveInjection var inject
	let store: StoreOf<HistoryFeature>
	@State private var showingDeleteConfirmation = false
	@Shared(.hexSettings) var hexSettings: HexSettings

	var body: some View {
      Group {
        if !hexSettings.saveTranscriptionHistory {
          ContentUnavailableView {
            Label("History Disabled", systemImage: "clock.arrow.circlepath")
          } description: {
            Text("Transcription history is currently disabled.")
          } actions: {
            Button("Enable in Settings") {
              store.send(.navigateToSettings)
            }
          }
        } else if store.transcriptionHistory.history.isEmpty {
          ContentUnavailableView {
            Label("No Transcriptions", systemImage: "text.bubble")
          } description: {
            Text("Your transcription history will appear here.")
          }
        } else {
          ScrollView {
            LazyVStack(spacing: 12) {
              ForEach(store.transcriptionHistory.history) { transcript in
                TranscriptView(
                  transcript: transcript,
                  isPlaying: store.playingTranscriptID == transcript.id,
                  learnedCount: store.lastLearnedCount[transcript.id],
                  onPlay: { store.send(.playTranscript(transcript.id)) },
                  onCopy: { store.send(.copyToClipboard(transcript.text)) },
                  onDelete: { store.send(.deleteTranscript(transcript.id)) },
                  onSaveEdit: { store.send(.saveTranscriptEdit(id: transcript.id, newText: $0)) }
                )
              }
            }
            .padding()
          }
          .toolbar {
            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
              Label("Delete All", systemImage: "trash")
            }
          }
          .alert("Delete All Transcripts", isPresented: $showingDeleteConfirmation) {
            Button("Delete All", role: .destructive) {
              store.send(.confirmDeleteAll)
            }
            Button("Cancel", role: .cancel) {}
          } message: {
            Text("Are you sure you want to delete all transcripts? This action cannot be undone.")
          }
        }
      }.enableInjection()
	}
}
