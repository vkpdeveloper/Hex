import Foundation

/// A user-defined dictionary entry that maps a spoken phrase to an exact output.
///
/// Example: phrase `"GitHub URL"` -> replacement `"https://github.com"`. These are
/// applied deterministically (see ``TuningDictionaryApplier``) so the substitution is
/// guaranteed and never reinterpreted, and are also fed to the tuning LLM so it can
/// resolve spoken variants without fighting the deterministic pass.
public struct TuningDictionaryEntry: Codable, Equatable, Identifiable, Sendable {
	public var id: UUID
	public var isEnabled: Bool
	/// The spoken phrase to match, e.g. "GitHub URL" or "my GitHub URL".
	public var phrase: String
	/// The exact text to substitute in, e.g. "https://github.com".
	public var replacement: String

	public init(
		id: UUID = UUID(),
		isEnabled: Bool = true,
		phrase: String,
		replacement: String
	) {
		self.id = id
		self.isEnabled = isEnabled
		self.phrase = phrase
		self.replacement = replacement
	}
}

/// Deterministic phrase replacement used as the guaranteed final pass of tuning.
///
/// Matching is case-insensitive and bounded so partial words are never replaced.
/// Entries are applied longest-phrase-first so a more specific entry ("my GitHub URL")
/// wins over a shorter overlapping one ("GitHub URL").
public enum TuningDictionaryApplier {
	public static func apply(_ text: String, entries: [TuningDictionaryEntry]) -> String {
		guard !entries.isEmpty else { return text }

		// Longest phrase first so specific entries take precedence over overlapping shorter ones.
		let ordered = entries
			.filter { $0.isEnabled }
			.map { (phrase: $0.phrase.trimmingCharacters(in: .whitespacesAndNewlines), replacement: $0.replacement) }
			.filter { !$0.phrase.isEmpty }
			.sorted { $0.phrase.count > $1.phrase.count }

		var output = text
		for entry in ordered {
			let escaped = NSRegularExpression.escapedPattern(for: entry.phrase)
			// Bound the match so we don't replace inside a larger word. The phrase may
			// contain spaces, so we guard the leading/trailing characters only.
			let pattern = "(?<!\\w)\(escaped)(?!\\w)"
			let replacement = processEscapeSequences(entry.replacement)
			// Backslash is special in regex replacement templates; escape it.
			let escapedReplacement = replacement.replacingOccurrences(of: "\\", with: "\\\\")
			output = output.replacingOccurrences(
				of: pattern,
				with: escapedReplacement,
				options: [.regularExpression, .caseInsensitive]
			)
		}
		return output
	}

	/// Processes escape sequences in a replacement: `\n` -> newline, `\t` -> tab, `\\` -> backslash.
	private static func processEscapeSequences(_ string: String) -> String {
		let placeholder = "\u{0000}"
		return string
			.replacingOccurrences(of: "\\\\", with: placeholder)
			.replacingOccurrences(of: "\\n", with: "\n")
			.replacingOccurrences(of: "\\t", with: "\t")
			.replacingOccurrences(of: "\\r", with: "\r")
			.replacingOccurrences(of: placeholder, with: "\\")
	}
}
