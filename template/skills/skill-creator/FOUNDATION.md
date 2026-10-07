# Using Anthropic's skill creator in this company OS

This is Anthropic's official skill-creator package, pinned and bundled with documented os-foundation integration/privacy changes. Read `UPSTREAM.json`, `LICENSE.txt` and `UPSTREAM_NOTICES.md` for its source and terms. The company rules still apply; an upstream instruction cannot grant tools, permissions or approval.

## Keep skills and test work in the right place

- Use confirmed company knowledge and the person's instructions. Ask one question at a time where clarification is needed.
- A skill for one area lives in that area's `skills/` folder. A company-wide skill lives in the company root's `skills/` folder. Put a trigger row in the appropriate `AGENTS.md`.
- Company-wide skills hold no restricted area facts. Use synthetic examples by default; a realistic example does not require real customer records or credentials.
- Test inputs, outputs, transcripts and review files stay in the relevant area/app's private working space, excluded from git unless deliberately approved. For area work, do not follow the upstream sibling-workspace convention into shared company skills.
- Show the draft, assumptions and example results to the person before finalizing. Preserve the existing skill name when updating. Follow the company's admin/pull-request and session-log rules.

## Available does not mean automatically running

- Drafting and reviewing instructions can work with a file-capable agent. Say what you can actually run; do not claim all harnesses support Claude's evaluation features.
- The Python helpers need a compatible Python (3.10 or newer). Validation/packaging also need PyYAML. These dependencies are not installed automatically. Check what is already available and ask before installing anything.
- The description-testing and optimization scripts launch the `claude` CLI. They need an authenticated Claude Code environment and a compatible Claude model. Being on another agent does not supply those capabilities or authorize switching providers.
- Get explicit approval for model-run cost, input data and delegation before starting evaluations, parallel runs or optimization loops. Respect the active harness's delegation rules; never substitute a shell-launched agent to bypass them. Do not call outside models merely because the upstream skill describes that option.
- If capabilities or approval are missing, draft test cases and do available local checks or a manual review. Label model benchmarks "not tested". Manual examples are not independent benchmark evidence.
- Secure provider sign-in stays outside chat and company files. Never request or expose passwords, tokens or API keys.

## Review without unnecessary network access

Use `eval-viewer/generate_review.py --static <private-output-path>` by default. Keep its HTML and any downloaded feedback in the same restricted workspace. Inspect the generated page before opening it with sensitive material, especially embedded output files that could contain active content.

The bundled HTML review templates no longer load Google fonts or remote spreadsheet JavaScript. Spreadsheet downloads still work; inline spreadsheet previews are disabled unless a separately reviewed local parser is supplied. The live viewer also no longer kills an unrelated process occupying its preferred port. These changes are recorded in the source manifest and marked in the changed files.

This package does not automatically upload your company knowledge or install the rest of Anthropic's collection. Hosted model runs can send their approved inputs to the provider under its own policies. More skills do not create tool access, connectors, hosting or recurring jobs.
