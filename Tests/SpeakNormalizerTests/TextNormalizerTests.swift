import Testing

@testable import SpeakNormalizer

private func n(_ s: String) -> String { TextNormalizer.normalize(s) }

@Suite("Numbers")
struct NumberTests {
    @Test func cardinals() {
        #expect(NumberWords.cardinal(0) == "zero")
        #expect(NumberWords.cardinal(13) == "thirteen")
        #expect(NumberWords.cardinal(40) == "forty")
        #expect(NumberWords.cardinal(105) == "one hundred five")
        #expect(NumberWords.cardinal(1520) == "one thousand five hundred twenty")
        #expect(NumberWords.cardinal(2_000_001) == "two million one")
        #expect(NumberWords.cardinal(-7) == "minus seven")
    }

    @Test func ordinalsAndYears() {
        #expect(NumberWords.ordinal(1) == "first")
        #expect(NumberWords.ordinal(22) == "twenty second")
        #expect(NumberWords.ordinal(40) == "fortieth")
        #expect(NumberWords.year(1999) == "nineteen ninety nine")
        #expect(NumberWords.year(2005) == "two thousand five")
        #expect(NumberWords.year(2026) == "twenty twenty six")
        #expect(NumberWords.year(1900) == "nineteen hundred")
        #expect(NumberWords.year(1905) == "nineteen oh five")
    }

    @Test func money() {
        #expect(n("$1,520") == "one thousand five hundred twenty dollars.")
        #expect(n("It cost $1.") == "It cost one dollar.")
        #expect(n("$19.99 each") == "nineteen dollars and ninety nine cents each.")
        #expect(n("$0.50") == "fifty cents.")
        #expect(n("$3.2M raised") == "three point two million dollars raised.")
        #expect(n("$5k budget") == "five thousand dollars budget.")
        #expect(n("€2.50") == "two euros and fifty cents.")
        #expect(n("£1") == "one pound.")
        #expect(n("₹1,50,000") == "one hundred fifty thousand rupees.")
        #expect(n("-$20") == "minus twenty dollars.")
    }

    @Test func percentagesAndDecimals() {
        #expect(n("45% faster") == "forty five percent faster.")
        #expect(n("2.5 %") == "two point five percent.")
        #expect(n("pi is 3.14") == "pi is three point one four.")
        #expect(n("0.25") == "zero point two five.")
        #expect(n("1,000,000 rows") == "one million rows.")
    }

    @Test func units() {
        #expect(n("2.3 s") == "two point three seconds.")
        #expect(n("took 2.3s") == "took two point three seconds.")
        #expect(n("1 s") == "one second.")
        #expect(n("150 ms") == "one hundred fifty milliseconds.")
        #expect(n("16 kHz") == "sixteen kilohertz.")
        #expect(n("36 GB of memory") == "thirty six gigabytes of memory.")
        #expect(n("1 GB") == "one gigabyte.")
        #expect(n("500MB/s") == "five hundred megabytes per second.")
        #expect(n("10x faster") == "ten times faster.")
        #expect(n("1.5x") == "one point five times.")
        #expect(n("5 min") == "five minutes.")
        #expect(n("3h") == "three hours.")
        #expect(n("20°C") == "twenty degrees Celsius.")
        #expect(n("120 tok/s") == "one hundred twenty tokens per second.")
    }

    @Test func scores() {
        #expect(n("10/10") == "ten of ten.")
        #expect(n("10 of 10") == "ten of ten.")
        #expect(n("Tests: 48/50 passed.") == "Tests: forty eight of fifty passed.")
        #expect(n("open 24/7") == "open twenty four seven.")
    }

    @Test func timesAndDates() {
        #expect(n("at 10:30") == "at ten thirty.")
        #expect(n("at 9:05 am") == "at nine oh five A M.")
        #expect(n("at 3pm") == "at three PM.")
        #expect(n("at 11 a.m.") == "at eleven A M.")
        #expect(n("at 10:00") == "at ten o'clock.")
        #expect(n("at 14:00") == "at fourteen hundred.")
        #expect(n("on 2026-11-07") == "on November seventh, twenty twenty six.")
        #expect(n("in 2024") == "in twenty twenty four.")
        #expect(n("2048 tokens") == "two thousand forty eight tokens.")
        #expect(n("on November 7th, 2026 at noon") == "on November seventh, twenty twenty six at noon.")
        #expect(n("at 10.30 a.m.") == "at ten thirty A M.")
        #expect(n("release 3.14 is out") == "release three point one four is out.")
        #expect(n("from 2020-2024") == "from twenty twenty to twenty twenty four.")
    }

    @Test func otherForms() {
        #expect(n("the 21st time") == "the twenty first time.")
        #expect(n("v1.2.3") == "version one point two point three.")
        #expect(n("version 2.0.1") == "version two point zero point one.")
        #expect(n("5-10 items") == "five to ten items.")
        #expect(n("-3 degrees") == "minus three degrees.")
        #expect(n("issue #42") == "issue number forty two.")
        #expect(n("M5 Max") == "M five Max.")
        #expect(n("~150 ms") == "about one hundred fifty milliseconds.")
        #expect(n("007") == "zero zero seven.")
    }
}

@Suite("Markdown")
struct MarkdownTests {
    @Test func headingsAndEmphasis() {
        #expect(n("# Summary") == "Summary.")
        #expect(n("## Next steps ##") == "Next steps.")
        #expect(n("This is **bold**, *italic*, __also bold__ and ~~gone~~.") == "This is bold, italic, also bold and gone.")
        #expect(n("snake_case_name stays") == "snake case name stays.")
    }

    @Test func bulletsAndNumberedLists() {
        let md = "Steps:\n- Install it\n* Run it\n+ Check it\n1. First\n2) Second\n- [x] Done task"
        #expect(TextNormalizer().units(md) == [
            "Steps:", "Install it.", "Run it.", "Check it.", "First.", "Second.", "Done task.",
        ])
    }

    @Test func codeFences() {
        let md = "Run this:\n```bash\nnpm install\nnpm test\n```\nThen relax."
        #expect(TextNormalizer().units(md) == ["Run this:", "Code block omitted.", "Then relax."])
        #expect(TextNormalizer().units("~~~\ncode\n~~~") == ["Code block omitted."])
        // An unclosed fence swallows the rest, as markdown renders it.
        #expect(TextNormalizer().units("Hi.\n```\nlet x = 1") == ["Hi.", "Code block omitted."])
    }

    @Test func inlineCodeKeepsItsText() {
        #expect(n("Call `run()` now.") == "Call run now.")
    }

    @Test func tablesReadBriefly() {
        let md = """
            | Model | Score |
            |-------|------:|
            | Kokoro | 9/10 |
            | Piper | 7/10 |
            """
        #expect(TextNormalizer().units(md) == [
            "Table with two rows. Columns: Model, Score.", "Kokoro, nine of ten.", "Piper, seven of ten.",
        ])
    }

    @Test func longTablesAreCut() {
        var md = "| A |\n|---|\n"
        for i in 1...12 { md += "| row \(i) |\n" }
        let units = TextNormalizer(options: .init(maxTableRows: 3)).units(md)
        #expect(units.first == "Table with twelve rows. Columns: A.")
        #expect(units.count == 5)
        #expect(units.last == "And nine more rows.")
    }

    @Test func quotesRulesLinksImagesHTML() {
        #expect(n("> quoted text") == "quoted text.")
        #expect(TextNormalizer().units("One.\n\n---\n\nTwo.") == ["One.", "Two."])
        #expect(n("Read [the docs](https://example.com/docs) first.") == "Read the docs first.")
        #expect(n("![diagram of flow](a.png)") == "Image: diagram of flow.")
        #expect(n("Press <kbd>Enter</kbd> now<br/>") == "Press Enter now.")
        #expect(n("Tom &amp; Jerry") == "Tom and Jerry.")
    }

    @Test func paragraphsJoinSoftWraps() {
        #expect(TextNormalizer().units("This line\nwraps here.\n\nNew para.") == ["This line wraps here.", "New para."])
    }
}

@Suite("Links, emoji, acronyms, paths")
struct TokenTests {
    @Test func urls() {
        #expect(n("See https://github.com/apple/swift/pull/123.") == "See a link to github dot com.")
        #expect(n("Go to www.example.co.uk/page now") == "Go to a link to example dot co dot UK now.")
        #expect(n("(https://docs.python.org/3/)") == "(a link to docs dot python dot org).")
        #expect(n("visit example.com/docs") == "visit a link to example dot com.")
        #expect(n("<https://openai.com>") == "a link to openai dot com.")
        #expect(n("mail dev.team@example.com") == "mail dev dot team at example dot com.")
    }

    @Test func emojiDropped() {
        #expect(n("Shipped 🎉🚀 today 👍🏽!") == "Shipped today!")
        #expect(n("✅ Tests pass") == "Tests pass.")
        #expect(n("Flag 🇮🇳 here") == "Flag here.")
        #expect(n("Family 👨‍👩‍👧 photo") == "Family photo.")
        #expect(n("Keycap 1️⃣ gone") == "Keycap gone.")
        #expect(n("Done ✔️") == "Done.")
        // Ordinary text symbols survive.
        #expect(n("Café © 2026") == "Café © twenty twenty six.")
    }

    @Test func acronyms() {
        #expect(n("The API and CLI") == "The API and CLI.")
        #expect(n("Open a PR so CI runs") == "Open a PR so CI runs.")
        #expect(n("Paste the URL") == "Paste the URL.")
        #expect(n("Parse JSON with SQL on iOS") == "Parse Jason with S Q L on I O S.")
        #expect(n("macOS and README") == "mac O S and read me.")
        #expect(n("the OS update") == "the O S update.")
        #expect(n("Merge the PRs") == "Merge the PR's.")
        #expect(n("e.g. this, i.e. that, etc.") == "for example, this, that is, that, et cetera.")
        #expect(n("CI/CD pipeline") == "C I C D pipeline.")
        #expect(n("A -> B") == "A to B.")
        #expect(n("R&D") == "R and D.")
    }

    @Test func developerLexicon() {
        #expect(n("pnpm and npm") == "P N P M and N P M.")
        #expect(n("TypeScript on Postgres") == "Type Script on Post gress.")
        #expect(n("PostgreSQL or SQLite or MySQL") == "Post gress Q L or S Q Lite or my S Q L.")
        #expect(n("OAuth with a JWT") == "oh auth with a J W T.")
        #expect(n("The API, CLI, PR and URL") == "The API, CLI, PR and URL.")
        #expect(n("CI/CD runs") == "C I C D runs.")
        #expect(n("YAML or TOML") == "yammel or tommel.")
        #expect(n("stdin, stdout and stderr") == "standard in, standard out and standard error.")
        #expect(n("open localhost") == "open local host.")
        #expect(n("uv and ffmpeg and PyTorch") == "U V and F F M peg and Pie Torch.")
        #expect(n("a regex") == "a rej ex.")
        #expect(n("index.ts and app.py") == "index dot T S and app dot pie.")
        #expect(n("query.sql") == "query dot S Q L.")
    }

    @Test func identifiersSplit() {
        #expect(n("call fetchUserData now") == "call fetch User Data now.")
        #expect(n("set max_retry_count.") == "set max retry count.")
        #expect(n("my iPhone and eBay") == "my eye phone and eBay.")
        #expect(n("TypeScript stays") == "Type Script stays.")
    }

    @Test func fileNamesAndPaths() {
        #expect(n("package.json") == "package dot json.")
        #expect(n("Edit package.json now.") == "Edit package dot json now.")
        #expect(n("Open Sources/App/main.swift") == "Open Sources slash App slash main dot swift.")
        #expect(n("in ~/Library/Logs") == "in home slash Library slash Logs.")
        #expect(n("run ./build.sh") == "run dot slash build dot SH.")
        #expect(n("cat .env") == "cat dot env.")
        #expect(n("/usr/local/bin") == "slash usr slash local slash bin.")
        #expect(n("see README.md") == "see read me dot MD.")
        #expect(n("my_script.py") == "my script dot pie.")
        #expect(n("Use Node.js") == "Use Node dot JS.")
        #expect(n("(config.yaml)") == "(config dot yammel).")
    }

    @Test func notMistakenForPaths() {
        #expect(n("and/or") == "and or.")
        #expect(n("client/server") == "client slash server.")
        #expect(n("the U.S. team") == "the U.S. team.")
        #expect(n("End.Next") == "End.Next.")
    }
}

@Suite("Chunking")
struct ChunkTests {
    @Test func sentences() {
        let s = SpeechChunker.sentences("Hello there. Dr. Smith said hi! Is it 5? Yes.\nNew line")
        #expect(s == ["Hello there.", "Dr. Smith said hi!", "Is it 5?", "Yes.", "New line"])
    }

    @Test func firstChunkAloneThenPacked() {
        let text = "One. Two is here. Three is here. Four is here."
        let chunks = SpeechChunker(firstMaxChars: 50, maxChars: 40).chunks(text)
        #expect(chunks == ["One.", "Two is here. Three is here.", "Four is here."])
    }

    @Test func longSentenceSplitsAtClauses() {
        let long = "This sentence is long, it has several clauses, and it keeps going for a while until it ends."
        let chunks = SpeechChunker(firstMaxChars: 40, maxChars: 40).chunks(long)
        #expect(chunks.allSatisfy { $0.count <= 40 })
        #expect(chunks.joined(separator: " ") == long)
        #expect(chunks.first?.hasSuffix(",") == true)
    }

    @Test func firstSentenceCutsAtCommaPast35() {
        let text = "The deployment finished without errors today, and every check passed. Next one."
        let chunks = SpeechChunker(firstMaxChars: 68, maxChars: 220).chunks(text)
        #expect(chunks.first == "The deployment finished without errors today,")
        #expect(chunks.dropFirst().first == "and every check passed. Next one.")
        // A comma before 35 characters does not cut.
        let early = SpeechChunker(firstMaxChars: 68, maxChars: 220).chunks("Yes, the deployment finished well.")
        #expect(early == ["Yes, the deployment finished well."])
        // Later sentences are not cut at commas.
        let later = SpeechChunker(firstMaxChars: 68, maxChars: 220).chunks("Done. The deployment finished without errors today, and so on.")
        #expect(later == ["Done.", "The deployment finished without errors today, and so on."])
    }

    @Test func kokoroLimitsScaleWithSpeed() {
        #expect(SpeechChunker.forKokoro(speed: 1.0, fastPathOnly: true).maxChars == 68)
        #expect(SpeechChunker.forKokoro(speed: 1.6, fastPathOnly: true).maxChars == 109)
        #expect(SpeechChunker.forKokoro(speed: 1.0).firstMaxChars == 68)
        #expect(SpeechChunker.forKokoro(speed: 1.0).maxChars == 220)
        let text = "We moved the logs to the new bucket last night and the job finished well before the morning check ran"
        let chunks = SpeechChunker.forKokoro(speed: 1.0, fastPathOnly: true).chunks(text)
        #expect(chunks.allSatisfy { $0.count <= 68 })
        // No punctuation to use, so it breaks before a conjunction.
        #expect(chunks.count == 2)
        #expect(chunks[1].hasPrefix("and ") || chunks[1].hasPrefix("the job"))
    }

    @Test func nothingLost() {
        let text = TextNormalizer.normalize(String(repeating: "Some words here, and more words there. ", count: 40))
        let chunks = SpeechChunker().chunks(text)
        #expect(chunks.joined(separator: " ") == text.replacingOccurrences(of: "\n", with: " "))
        #expect(chunks.allSatisfy { $0.count <= 220 })
    }
}
