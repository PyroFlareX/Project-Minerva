# Minerva Intent Editor — Design Sketch

**Programming without a keyboard by replacing precision input with constrained disambiguation.**

---

## The problem this resolves

Every keyboardless input channel is noisy or slow:

- Gamepad selection keyboards: precise but ~7 WPM.
- Chording: fast (26–47+ WPM) but has a training cliff.
- Voice: fast but mishears — and code is full of out-of-vocabulary identifiers (`torchform_inputd`, `BQ25798`) that general STT will mangle.
- Touch thumb-typing on a 3.5" screen: error-prone for symbols-heavy text.

The traditional fix is to make each channel more precise. That's the wrong fight. The fix is to make **precision unnecessary**: the editor never asks "what characters did you produce?" — it asks "which of these N valid things did you mean?" Choosing among N small things is exactly what gamepads, radial menus, and a second screen are good at.

## Core principle

> **All input — buttons, chords, voice, touch — produces *intents*, not characters. Intents are resolved against a small, contextually valid action space derived from the AST, the symbol table, and an LLM prior. Errors are corrected by selection, never by retyping.**

The buffer's source of truth is a tree-sitter AST, not a character stream. At any cursor position the set of valid next actions (insertable node kinds, in-scope identifiers, applicable refactors) is small — typically 5–30 options. Every noisy channel is decoded *into that set*, which is what makes mishearing survivable: the recognizer doesn't have to hear `inputd` perfectly, it has to rank it above the 12 other symbols in scope.

```
noisy signal ──► candidate lattice ──► constrain to valid action space ──► rank (LLM) ──► top-1 applied,
 (voice/chord/touch)                       (grammar + symbol table)                        alternates on lower screen
```

## The input stack (escalating cost, descending frequency)

| Layer | Channel | Used for | Error model |
|---|---|---|---|
| 1 | Sticks + d-pad, AST motions | Navigation between nodes (sibling/parent/child/next-error) | Effectively zero — discrete moves |
| 2 | Chord → radial menu | Structural edits: insert node kind, wrap, extract, rename, match-arm | Wrong pick → one-button undo, re-pick |
| 3 | Voice (constrained) | Identifiers, comments, commit messages, **edit intents in natural language** | N-best repair loop (below) |
| 4 | Dual-stick / touch split keyboard on lower screen | Novel identifiers, string literals, anything truly new | Fuzzy completion absorbs most slips |
| 5 | Chord typing (Twiddler-style) | Expert freeform path, learned over time | Same as 4, faster ceiling |

Layers 1–2 cover ~80% of edit operations and involve no text at all. Layers 3–5 only fire when a *name* or *prose* must enter the system.

## Voice mishearing: the repair loop

Mishearing stops being fatal when three things hold:

**1. Biased decoding.** whisper.cpp output is not taken as final text. The decode is re-ranked against a dynamic vocabulary: in-scope symbols, project identifiers (split on snake/camel case into pronounceable parts), language keywords, and the user's recent terms. "tortch form input dee" resolves to `torchform_inputd` because it's the nearest in-scope symbol, even though no general model would transcribe it.

**2. N-best as first-class UI.** The top hypothesis is applied optimistically; hypotheses 2–5 render as a numbered strip on the lower screen for ~3 seconds. One shoulder-chord + d-pad press swaps in an alternate. Correction cost: one button, not one retyped word.

**3. Span repair by selection, not retyping.** If the applied utterance is wrong beyond the n-best, the user d-pads to the offending *word/token* (cursor moves at token granularity, never characters), presses Repair, and gets a fresh candidate list for just that span — re-decoded from the retained audio with the rest of the utterance as context. Worst case: re-speak only the broken word.

The same loop covers chord mistypes and touch slips: every layer emits candidates, the UI is always "top-1 applied + alternates one press away."

## Prompts are structured objects, not strings

The LLM layer ("add exponential backoff retry around this call") inherits the mishearing problem — so prompts get the same treatment as code:

- A spoken prompt renders on the lower screen as **token chips**, each chip independently selectable with the d-pad.
- A misheard chip is repaired via the n-best loop above; chips referring to code entities (`this call`, `the retry count`) are *bound* to actual AST nodes, shown highlighted on the top screen — so the model receives node references, not ambiguous prose.
- Chips can be deleted, reordered, or appended to by voice or layer-4 typing. You never re-dictate a whole prompt to fix one word.
- A small "prompt palette" radial offers common intent verbs (refactor, explain, add test, fix error) so frequent prompts start from a template with only the variable parts spoken.

## LLM roles (three, all through the existing proxy)

1. **Next-edit prediction.** Given AST context, rank the valid-action menu so the likely insertion is the radial menu's resting position. Cheap, local-model friendly (Qwen tier), runs on every cursor move.
2. **STT re-ranking.** Score n-best hypotheses against code context. Local tier.
3. **Intent → diff.** Natural-language prompt + bound nodes → structured diff. Routed per the existing three-tier policy (OpenRouter → pyrospc → local), gated by the privacy classifier since prompts embed code. Diffs are **never auto-applied**: they render as hunk-by-hunk review on the top screen, accept/reject/modify per hunk with face buttons — turning generation, the riskiest channel, back into a selection task.

## Screen + daemon mapping

```
┌─ top screen (5.15" DSI) ──────────────┐
│  code buffer · AST node highlight     │
│  diff review overlay                  │
└───────────────────────────────────────┘
┌─ lower screen (3.5" touch) ───────────┐
│  contextual surface:                  │
│   · radial / action menu              │
│   · n-best candidate strip            │
│   · prompt chips                      │
│   · split keyboard (layer 4)          │
└───────────────────────────────────────┘

whisper.cpp ──► torchform-inputd ──► ShellAction JSON ──► editor core (tree-sitter AST)
                     ▲    chords/touch                        │
                     │                                        ▼
              llm proxy.sock ◄── rerank / predict / diff requests (3-tier routing)
```

New ShellAction variants needed: `AstMove{dir}`, `MenuPick{id}`, `CandidateSwap{rank}`, `SpanRepair{token_idx}`, `DiffHunk{accept|reject|edit}`, `PromptChip{op}`.

## Why this resolves the original problem

| Failure mode | Resolution |
|---|---|
| Gamepads are too slow for code | Code is mostly structure; structure is menu selection, not typing |
| Voice mishears identifiers | Decode constrained to symbol table; n-best swap; span repair |
| Can't edit a prompt without a keyboard | Prompts are chips, edited at word granularity by selection |
| LLM output is risky to trust | Diffs reviewed hunk-by-hunk with face buttons |
| Novel names still need typing | Confined to layer 4/5, amortized by fuzzy completion |

The unifying claim: **on a constrained device, disambiguation beats input precision.** Every channel is allowed to be sloppy because the space of meaningful actions is always small, visible, and one button-press away from correction.
