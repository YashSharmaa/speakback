/// The instructions `speak install-skill` gives coding agents.
///
/// The rendered copies in the repository's `skills/` folder are generated from
/// these strings (`speak install-skill --print` and `--print-skill`); a unit test
/// keeps them in step.
public enum SkillTexts {

    /// Marks text this tool wrote, so `--uninstall` removes only its own work.
    public static let marker = "<!-- Installed by `speak install-skill`; `speak install-skill --uninstall` removes it. -->"

    static let triggers = """
        "speak it to me", "read that out", "read it aloud", "read this out loud", "say it out loud", \
        "tell me out loud", "I want to hear this", "can you say that", "narrate this"
        """

    /// The shared instructions, for any harness.
    static let body = """
        When the user wants to hear an answer rather than read it, say it through the local `speak` \
        command. It runs Kokoro text to speech on this Mac, fully offline.

        1. Rewrite the answer for the ear, not the screen.
           - Plain spoken prose only: no markdown, headings, bullets, tables, code, emoji or URLs. \
        Describe code or a table in a sentence instead of reading it out.
           - Short sentences, one idea each. Lead with the answer.
           - Write numbers the way people say them: "about two and a half seconds", "three out of four", \
        "version two point one". Round where precision does not matter.
           - Name a link's site ("the FluidAudio page on GitHub"), never the address.
           - Keep it to what was asked: about a minute of speech (150 words) unless they want more.
        2. Never read secrets aloud: no API keys, tokens, passwords, private keys, connection strings, \
        or personal data such as card or account numbers. Say where the secret is instead.
        3. Speak it with a quoted heredoc, so the shell expands nothing:

           ```sh
           speak <<'EOF'
           The build passed. Two tests were flaky, so I marked them to retry.
           EOF
           ```

           For a long text, write it to a temporary file and run `speak --file <path>`. \
        `speak` returns as soon as the audio starts, so it never blocks, and the file can be deleted \
        straight after.
        4. Keep the chat reply short: one line saying you are reading it aloud, plus anything written \
        they will still need, such as a command or code.
        5. When asked to stop ("stop", "quiet", "that's enough"), run `speak --stop`. A new `speak` \
        call replaces whatever is playing.
        6. Options: `--voice bf_emma` (British), `--voice indian` (Indian English), `--speed 1.3` \
        (0.8 to 1.6). `speak --voices` lists every voice.

        If `speak` is not installed, say so and point to https://github.com/YashSharmaa/speakback.
        """

    /// A Claude Code or OpenCode skill: `<skills dir>/speak/SKILL.md`.
    public static let skill = """
        ---
        name: speak
        description: Read an answer aloud on this Mac with the local `speak` command (offline Kokoro \
        text to speech). Use whenever the user wants to hear something instead of reading it, for \
        example \(triggers), or asks to stop the speech.
        ---

        # Speak it aloud

        \(marker)

        \(body)

        """

    /// The generic section for an AGENTS.md file or any other harness.
    public static let generic = """
        ## Reading answers aloud with `speak`

        Use this when the user asks to hear something, for example \(triggers).

        \(body)

        """
}
