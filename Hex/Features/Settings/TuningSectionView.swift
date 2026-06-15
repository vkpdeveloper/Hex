import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct TuningSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	@FocusState private var apiKeyFieldFocused: Bool

	private var isEnabled: Bool { store.hexSettings.tuningEnabled }

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
					"Enable Auto-edit",
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

				Label {
					HStack(spacing: 4) {
						Text("Phrase replacements live in the")
						Text("Dictionary")
							.fontWeight(.semibold)
						Text("tab.")
					}
					.font(.caption)
					.foregroundStyle(.secondary)
				} icon: {
					Image(systemName: "character.book.closed")
				}
			}
		} header: {
			Text("Auto-edit")
		} footer: {
			if isEnabled {
				Text("Auto-edit runs after transcription and adds a short network round-trip before text is inserted. If the request fails, your original transcript is used.")
					.settingsCaption()
			}
		}
		.enableInjection()
	}
}
