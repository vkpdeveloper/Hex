import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct DictionaryView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	@FocusState private var isScratchpadFocused: Bool

	private var isEnabled: Bool { store.hexSettings.tuningDictionaryEnabled }

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				VStack(alignment: .leading, spacing: 6) {
					Text("Dictionary")
						.font(.title2.bold())
					Text("Map spoken phrases to exact text. Say \u{201C}GitHub URL\u{201D} and Hex inserts https://github.com. Replacements are exact, applied as a final pass, and run on the longest matching phrase first.")
						.font(.callout)
						.foregroundStyle(.secondary)
				}

				previewBox

				entriesSection
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding()
		}
		.onDisappear {
			store.send(.setRemappingScratchpadFocused(false))
		}
		.enableInjection()
	}

	// MARK: - Preview

	private var previewBox: some View {
		GroupBox {
			HStack(spacing: 12) {
				VStack(alignment: .leading, spacing: 4) {
					Text("Scratchpad")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
					TextField("Say something…", text: $store.remappingScratchpadText)
						.textFieldStyle(.roundedBorder)
						.focused($isScratchpadFocused)
						.onChange(of: isScratchpadFocused) { _, newValue in
							store.send(.setRemappingScratchpadFocused(newValue))
						}
				}

				Image(systemName: "arrow.right")
					.foregroundStyle(.secondary)
					.padding(.top, 18)

				VStack(alignment: .leading, spacing: 4) {
					Text("Result")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
					Text(previewText.isEmpty ? "—" : previewText)
						.font(.body)
						.textSelection(.enabled)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.horizontal, 8)
						.padding(.vertical, 6)
						.background(
							RoundedRectangle(cornerRadius: 6)
								.fill(Color(nsColor: .controlBackgroundColor))
						)
				}
			}
			.padding(.vertical, 6)
		}
	}

	// MARK: - Entries

	private var entriesSection: some View {
		GroupBox {
			VStack(alignment: .leading, spacing: 10) {
				Toggle(
					"Enable Dictionary",
					isOn: Binding(
						get: { store.hexSettings.tuningDictionaryEnabled },
						set: { store.send(.setTuningDictionaryEnabled($0)) }
					)
				)
				.toggleStyle(.checkbox)

				if store.hexSettings.tuningDictionary.isEmpty {
					emptyState
				} else {
					columnHeaders

					LazyVStack(alignment: .leading, spacing: 6) {
						ForEach(store.hexSettings.tuningDictionary) { entry in
							DictionaryRow(entry: entryBinding(for: entry)) {
								store.send(.removeTuningDictionaryEntry(entry.id))
							}
							.disabled(!isEnabled)
							.opacity(isEnabled ? 1 : 0.5)
						}
					}
				}

				HStack {
					Button {
						store.send(.addTuningDictionaryEntry)
					} label: {
						Label("Add Entry", systemImage: "plus")
					}
					Spacer()
				}
			}
			.padding(.vertical, 4)
		} label: {
			VStack(alignment: .leading, spacing: 4) {
				Text("Phrases")
					.font(.headline)
				Text("Each phrase is matched whole and case-insensitively, then replaced with its exact output.")
					.settingsCaption()
			}
		}
	}

	private var emptyState: some View {
		HStack(spacing: 8) {
			Image(systemName: "character.book.closed")
				.foregroundStyle(.secondary)
			Text("No phrases yet. Add one to start replacing spoken phrases with exact text.")
				.foregroundStyle(.secondary)
				.font(.callout)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.vertical, 8)
	}

	private var columnHeaders: some View {
		HStack(spacing: 8) {
			Text("On")
				.frame(width: Layout.toggleColumnWidth, alignment: .leading)
			Text("Spoken phrase")
				.frame(maxWidth: .infinity, alignment: .leading)
			Image(systemName: "arrow.right")
				.font(.caption)
				.foregroundStyle(.secondary)
				.frame(width: Layout.arrowColumnWidth)
			Text("Replacement")
				.frame(maxWidth: .infinity, alignment: .leading)
			Spacer().frame(width: Layout.deleteColumnWidth)
		}
		.font(.caption)
		.foregroundStyle(.secondary)
		.padding(.horizontal, Layout.rowHorizontalPadding)
	}

	private func entryBinding(for entry: TuningDictionaryEntry) -> Binding<TuningDictionaryEntry> {
		Binding(
			get: {
				store.hexSettings.tuningDictionary.first { $0.id == entry.id } ?? entry
			},
			set: { store.send(.updateTuningDictionaryEntry($0)) }
		)
	}

	private var previewText: String {
		guard isEnabled else { return store.remappingScratchpadText }
		return TuningDictionaryApplier.apply(
			store.remappingScratchpadText,
			entries: store.hexSettings.tuningDictionary
		)
	}
}

private struct DictionaryRow: View {
	@Binding var entry: TuningDictionaryEntry
	var onDelete: () -> Void

	var body: some View {
		HStack(spacing: 8) {
			Toggle("", isOn: $entry.isEnabled)
				.labelsHidden()
				.toggleStyle(.checkbox)
				.frame(width: Layout.toggleColumnWidth, alignment: .leading)

			TextField("e.g. GitHub URL", text: $entry.phrase)
				.textFieldStyle(.roundedBorder)
				.frame(maxWidth: .infinity, alignment: .leading)

			Image(systemName: "arrow.right")
				.foregroundStyle(.secondary)
				.frame(width: Layout.arrowColumnWidth)

			TextField("e.g. https://github.com", text: $entry.replacement)
				.textFieldStyle(.roundedBorder)
				.frame(maxWidth: .infinity, alignment: .leading)

			Button(role: .destructive, action: onDelete) {
				Image(systemName: "trash")
			}
			.buttonStyle(.borderless)
			.frame(width: Layout.deleteColumnWidth)
		}
		.padding(.horizontal, Layout.rowHorizontalPadding)
		.padding(.vertical, Layout.rowVerticalPadding)
		.frame(maxWidth: .infinity)
		.background(
			RoundedRectangle(cornerRadius: Layout.rowCornerRadius)
				.fill(Color(nsColor: .controlBackgroundColor))
		)
	}
}

private enum Layout {
	static let toggleColumnWidth: CGFloat = 24
	static let deleteColumnWidth: CGFloat = 24
	static let arrowColumnWidth: CGFloat = 16
	static let rowHorizontalPadding: CGFloat = 10
	static let rowVerticalPadding: CGFloat = 6
	static let rowCornerRadius: CGFloat = 8
}
