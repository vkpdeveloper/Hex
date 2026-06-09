import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct TuningSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	private var isEnabled: Bool { store.hexSettings.tuningEnabled }

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
				Text("Polish each transcript with an LLM: remove false starts and filler, resolve spoken self-corrections (\u{201C}make it black, no, white\u{201D}), and format spoken lists (\u{201C}number one, number two\u{201D}) into 1. / 2. — without changing what you meant.")
			} icon: {
				Image(systemName: "wand.and.stars")
			}

			if isEnabled {
				Label {
					VStack(alignment: .leading, spacing: 6) {
						HStack {
							Text("Groq API Key")
							Spacer()
							SecureField(
								"gsk_…",
								text: Binding(
									get: { store.hexSettings.tuningGroqAPIKey },
									set: { store.send(.setTuningGroqAPIKey($0)) }
								)
							)
							.textFieldStyle(.roundedBorder)
							.frame(maxWidth: 240)
						}
						HStack(spacing: 4) {
							Text("Stored locally on this Mac. Get a key at")
							Link("console.groq.com/keys", destination: URL(string: "https://console.groq.com/keys")!)
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
						Text("qwen/qwen3-32b")
							.foregroundStyle(.secondary)
					}
				} icon: {
					Image(systemName: "cpu")
				}
			}
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
}
