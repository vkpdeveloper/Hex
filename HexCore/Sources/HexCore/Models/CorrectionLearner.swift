import Foundation

/// Learns dictionary entries from a user's manual edit of a transcript.
///
/// When the user edits a transcript in History, we diff the original against the
/// edited text word-by-word and turn contiguous substitutions ("hex core" ->
/// "HexCore") into ``TuningDictionaryEntry`` candidates. This mirrors how Wispr
/// Flow's personal dictionary learns from corrections: the LLM never guesses at
/// misheard words, but repeated fixes become guaranteed replacements.
public enum CorrectionLearner {
	/// Maximum words on either side of a learned substitution. Longer runs are
	/// almost always rewrites of content, not corrections of a misheard phrase.
	public static let maxPhraseWords = 3

	/// Diffs `original` against `edited` and returns dictionary entries for each
	/// contiguous word substitution, skipping:
	/// - insertions and deletions (no phrase to map from/to),
	/// - substitutions longer than ``maxPhraseWords`` on either side,
	/// - changes in case or punctuation only (the Auto-edit prompt already owns those),
	/// - pairs already covered by an entry in `existing` (case-insensitive phrase match).
	public static func learnEntries(
		original: String,
		edited: String,
		existing: [TuningDictionaryEntry]
	) -> [TuningDictionaryEntry] {
		let originalWords = tokenize(original)
		let editedWords = tokenize(edited)
		guard !originalWords.isEmpty, !editedWords.isEmpty else { return [] }

		let existingPhrases = Set(
			existing.map { $0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
		)

		var entries: [TuningDictionaryEntry] = []
		var seenPhrases = Set<String>()

		for change in substitutions(from: originalWords, to: editedWords) {
			let (phrase, replacement) = stripSharedEdgePunctuation(
				phrase: change.removed.joined(separator: " "),
				replacement: change.inserted.joined(separator: " ")
			)
			guard !phrase.isEmpty, !replacement.isEmpty else { continue }

			guard change.removed.count <= maxPhraseWords, change.inserted.count <= maxPhraseWords else { continue }
			guard !isTrivialChange(phrase: phrase, replacement: replacement) else { continue }

			let key = phrase.lowercased()
			guard !existingPhrases.contains(key), !seenPhrases.contains(key) else { continue }
			seenPhrases.insert(key)

			entries.append(.init(phrase: phrase, replacement: replacement))
		}
		return entries
	}

	// MARK: - Diffing

	struct Substitution: Equatable {
		var removed: [String]
		var inserted: [String]
	}

	/// Pairs adjacent removal/insertion runs from `CollectionDifference` into
	/// substitutions. Pure insertions or deletions are dropped — a correction of a
	/// misheard phrase always replaces words with other words.
	static func substitutions(from old: [String], to new: [String]) -> [Substitution] {
		let difference = new.difference(from: old)

		// Group contiguous removals/insertions into runs keyed by position.
		var removalRuns: [(start: Int, words: [String])] = []
		for removal in difference.removals {
			guard case let .remove(offset, element, _) = removal else { continue }
			if var last = removalRuns.last, last.start + last.words.count == offset {
				last.words.append(element)
				removalRuns[removalRuns.count - 1] = last
			} else {
				removalRuns.append((start: offset, words: [element]))
			}
		}

		var insertionRuns: [(start: Int, words: [String])] = []
		for insertion in difference.insertions {
			guard case let .insert(offset, element, _) = insertion else { continue }
			if var last = insertionRuns.last, last.start + last.words.count == offset {
				last.words.append(element)
				insertionRuns[insertionRuns.count - 1] = last
			} else {
				insertionRuns.append((start: offset, words: [element]))
			}
		}

		// A removal run at old-offset R corresponds to an insertion run at new-offset I
		// when they occupy the same position once earlier runs are accounted for:
		// I == R + (words inserted before) - (words removed before).
		var result: [Substitution] = []
		var insertedBefore = 0
		var removedBefore = 0
		var insertionIndex = 0

		for removal in removalRuns {
			// Consume insertion runs that occur strictly before this removal's position.
			while insertionIndex < insertionRuns.count,
			      insertionRuns[insertionIndex].start < removal.start + insertedBefore - removedBefore
			{
				insertedBefore += insertionRuns[insertionIndex].words.count
				insertionIndex += 1
			}

			if insertionIndex < insertionRuns.count,
			   insertionRuns[insertionIndex].start == removal.start + insertedBefore - removedBefore
			{
				result.append(.init(removed: removal.words, inserted: insertionRuns[insertionIndex].words))
				insertedBefore += insertionRuns[insertionIndex].words.count
				insertionIndex += 1
			}
			removedBefore += removal.words.count
		}
		return result
	}

	// MARK: - Filters

	/// Whitespace tokenization keeping punctuation attached to words, so "HexCore," is
	/// one token. Trivial-change detection strips it before comparing.
	static func tokenize(_ text: String) -> [String] {
		text.split(whereSeparator: \.isWhitespace).map(String.init)
	}

	/// True when the change is only capitalization and/or punctuation — those belong to
	/// the Auto-edit formatting pass, not the dictionary.
	static func isTrivialChange(phrase: String, replacement: String) -> Bool {
		normalize(phrase) == normalize(replacement)
	}

	private static func normalize(_ text: String) -> String {
		String(text.lowercased().unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) })
	}

	/// Drops punctuation that is identical at the edges of both sides ("core," ->
	/// "HexCore," learns "core" -> "HexCore") so entries match the bare phrase.
	static func stripSharedEdgePunctuation(phrase: String, replacement: String) -> (String, String) {
		var p = Substring(phrase)
		var r = Substring(replacement)
		while let pl = p.last, let rl = r.last, pl == rl, pl.isPunctuation {
			p.removeLast()
			r.removeLast()
		}
		while let pf = p.first, let rf = r.first, pf == rf, pf.isPunctuation {
			p.removeFirst()
			r.removeFirst()
		}
		return (String(p), String(r))
	}
}
