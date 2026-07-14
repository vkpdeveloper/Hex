import Testing
@testable import HexCore

struct CorrectionLearnerTests {
	@Test
	func learnsSingleWordSubstitution() {
		let entries = CorrectionLearner.learnEntries(
			original: "open the hex core file",
			edited: "open the HexCore file",
			existing: []
		)
		#expect(entries.count == 1)
		#expect(entries[0].phrase == "hex core")
		#expect(entries[0].replacement == "HexCore")
	}

	@Test
	func learnsMultipleSubstitutions() {
		let entries = CorrectionLearner.learnEntries(
			original: "ping via bhav about the grock key",
			edited: "ping Vaibhav about the Groq key",
			existing: []
		)
		#expect(entries.count == 2)
		#expect(entries[0].phrase == "via bhav")
		#expect(entries[0].replacement == "Vaibhav")
		#expect(entries[1].phrase == "grock")
		#expect(entries[1].replacement == "Groq")
	}

	@Test
	func ignoresPureInsertionsAndDeletions() {
		let inserted = CorrectionLearner.learnEntries(
			original: "send the report",
			edited: "send the quarterly report today",
			existing: []
		)
		#expect(inserted.isEmpty)

		let deleted = CorrectionLearner.learnEntries(
			original: "send the quarterly report today",
			edited: "send the report",
			existing: []
		)
		#expect(deleted.isEmpty)
	}

	@Test
	func ignoresCaseOnlyAndPunctuationOnlyChanges() {
		let entries = CorrectionLearner.learnEntries(
			original: "meet at github tomorrow",
			edited: "meet at GitHub, tomorrow",
			existing: []
		)
		#expect(entries.isEmpty)
	}

	@Test
	func ignoresLongRewrites() {
		let entries = CorrectionLearner.learnEntries(
			original: "we should probably think about maybe doing this later",
			edited: "we could revisit the entire approach in the next planning cycle",
			existing: []
		)
		#expect(entries.isEmpty)
	}

	@Test
	func skipsPhrasesAlreadyInDictionary() {
		let entries = CorrectionLearner.learnEntries(
			original: "check the grock console",
			edited: "check the Groq console",
			existing: [.init(phrase: "Grock", replacement: "Groq")]
		)
		#expect(entries.isEmpty)
	}

	@Test
	func dedupesRepeatedCorrectionWithinOneEdit() {
		let entries = CorrectionLearner.learnEntries(
			original: "grock is fast and grock is cheap",
			edited: "Groq is fast and Groq is cheap",
			existing: []
		)
		#expect(entries.count == 1)
		#expect(entries[0].phrase == "grock")
		#expect(entries[0].replacement == "Groq")
	}

	@Test
	func stripsSharedTrailingPunctuation() {
		let entries = CorrectionLearner.learnEntries(
			original: "we use hex core, every day",
			edited: "we use HexCore, every day",
			existing: []
		)
		#expect(entries.count == 1)
		#expect(entries[0].phrase == "hex core")
		#expect(entries[0].replacement == "HexCore")
	}

	@Test
	func learnedEntryRoundTripsThroughApplier() {
		let entries = CorrectionLearner.learnEntries(
			original: "the para keet model",
			edited: "the Parakeet model",
			existing: []
		)
		#expect(entries.count == 1)
		let applied = TuningDictionaryApplier.apply("download the para keet model now", entries: entries)
		#expect(applied == "download the Parakeet model now")
	}

	@Test
	func unchangedTextLearnsNothing() {
		let entries = CorrectionLearner.learnEntries(
			original: "nothing changed here",
			edited: "nothing changed here",
			existing: []
		)
		#expect(entries.isEmpty)
	}
}
