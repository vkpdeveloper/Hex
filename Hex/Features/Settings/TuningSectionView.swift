import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct TuningSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	@FocusState private var apiKeyFieldFocused: Bool

	private var isEnabled: Bool { store.hexSettings.tuningEnabled }
	private var isDictionaryEnabled: Bool { store.hexSettings.tuningDictionaryEnabled }

	@ViewBuilder
	private var keyTestStatusBadge: some View {
		switch store.tuningKeyTestStatus {
		case .idle:
			EmptyView()
		case .testing:
			HStack(spacing: 4) {
				ProgressView().controlSize(.small)
				Text("Testing…").foregroundStyle(.secondary)
			}
			.font(.caption)
		case .passed:
			Label("Tested", systemImage: "checkmark.circle.fill")
				.font(.caption)
				.foregroundStyle(.green)
		case .failed:
			Label("Test Failed", systemImage: "xmark.circle.fill")
				.font(.caption)
				.foregroundStyle(.red)
		}
	}

	var body: some View {
		Section {
			Label {
				Toggle(
					"Enable Tuning",
					isOn: Binding(
						get: { store.hexSettings.tuningEnabled },
						set: { store.send(.setTuningEnabled($0)) }
					)
				)
				Text("Polish each transcript with an LLM without changing your words: remove false starts and filler, resolve spoken self-corrections (\u{201C}make it black, no, white\u{201D}), and format spoken lists (\u{201C}number one, number two\u{201D}) into 1. / 2.")
			} icon: {
				Image(systemName: "wand.and.stars")
			}

			if isEnabled {
				Label {
					VStack(alignment: .leading, spacing: 6) {
						HStack {
							Text("Gemini API Key")
							Spacer()
							keyTestStatusBadge
							SecureField(
								"AIza…",
								text: Binding(
									get: { store.hexSettings.tuningGeminiAPIKey },
									set: { store.send(.setTuningGeminiAPIKey($0)) }
								)
							)
							.textFieldStyle(.roundedBorder)
							.frame(maxWidth: 240)
							.focused($apiKeyFieldFocused)
							.onSubmit {
								apiKeyFieldFocused = false
								store.send(.testTuningGeminiAPIKey)
							}
							.onExitCommand {
								apiKeyFieldFocused = false
							}
							.onKeyPress(.escape) {
								apiKeyFieldFocused = false
								return .handled
							}
						}
						HStack(spacing: 4) {
							Text("Stored locally on this Mac. Get a key at")
							Link("aistudio.google.com/apikey", destination: URL(string: "https://aistudio.google.com/apikey")!)
						}
						.font(.caption)
						.foregroundStyle(.secondary)
					}
				} icon: {
					Image(systemName: "key")
				}

				Label {
					HStack {
						Text("Model")
						Spacer()
						Text(TuningClientLive.model)
							.foregroundStyle(.secondary)
					}
				} icon: {
					Image(systemName: "cpu")
				}
			}

			dictionarySection
		} header: {
			Text("Tuning")
		} footer: {
			if isEnabled {
				Text("Tuning runs after transcription and adds a short network round-trip before text is inserted. If the request fails, your original transcript is used.")
					.settingsCaption()
			}
		}
		.enableInjection()
	}

	@ViewBuilder
	private var dictionarySection: some View {
		Label {
			VStack(alignment: .leading, spacing: 6) {
				Toggle(
					"Dictionary",
					isOn: Binding(
						get: { store.hexSettings.tuningDictionaryEnabled },
						set: { store.send(.setTuningDictionaryEnabled($0)) }
					)
				)
				Text("Replace spoken phrases with exact text. Say \u{201C}GitHub URL\u{201D} \u{2192} https://github.com. Matches are exact and applied as a final pass, so the output is guaranteed.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		} icon: {
			Image(systemName: "character.book.closed")
		}

		if isDictionaryEnabled {
			ForEach(store.hexSettings.tuningDictionary) { entry in
				HStack(spacing: 8) {
					Toggle(
						"",
						isOn: Binding(
							get: { entry.isEnabled },
							set: { var e = entry; e.isEnabled = $0; store.send(.updateTuningDictionaryEntry(e)) }
						)
					)
					.labelsHidden()

					TextField(
						"Spoken phrase",
						text: Binding(
							get: { entry.phrase },
							set: { var e = entry; e.phrase = $0; store.send(.updateTuningDictionaryEntry(e)) }
						)
					)
					.textFieldStyle(.roundedBorder)

					Image(systemName: "arrow.right")
						.foregroundStyle(.secondary)
						.font(.caption)

					TextField(
						"Replacement",
						text: Binding(
							get: { entry.replacement },
							set: { var e = entry; e.replacement = $0; store.send(.updateTuningDictionaryEntry(e)) }
						)
					)
					.textFieldStyle(.roundedBorder)

					Button(role: .destructive) {
						store.send(.removeTuningDictionaryEntry(entry.id))
					} label: {
						Image(systemName: "trash")
					}
					.buttonStyle(.borderless)
				}
			}

			Button {
				store.send(.addTuningDictionaryEntry)
			} label: {
				Label("Add Entry", systemImage: "plus")
			}
		}
	}
}
