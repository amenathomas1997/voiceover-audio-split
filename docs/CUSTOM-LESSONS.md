# Writing your own VoiceOver lessons

Trainers can write lessons for their students, for example for a website or an app the student uses at work. Each lesson is a small text file ending in `.voalesson`. It runs just like the built-in lessons: it explains, asks the student to press keys, asks questions, sets real tasks, and ends with a quick check and a session report.

## Getting started

1. Open VoiceOver Lessons and go to the **Your lessons** section.
2. Choose **Save a Sample Lesson File…** to save a sample lesson.
3. Open the file in TextEdit (choose Format, Make Plain Text if needed) and change it.
4. Choose **Import a Lesson…** and pick the file. If something is wrong, the app says exactly what and where, for example: `Step 3: unknown key name 'VO Comand H'.` Fix it and import again.

Imported lessons are kept on this Mac, in the app's own folder (Application Support, Lessons). Importing a lesson with the same title again replaces it, and students keep their progress. **Remove** takes a lesson off this Mac; keep your own copy of the file.

## The format

A lesson file is JSON, in UTF-8. It holds one lesson, between curly braces:

| Field | Required | What it is |
| --- | --- | --- |
| `format` | no | The format version. Leave it out, or use `1`. |
| `title` | yes | The lesson's name, under 120 characters. |
| `summary` | no | One sentence, read as the lesson button's hint. |
| `goals` | no | What the lesson teaches. It's read after "In this lesson:", so write it as the end of that sentence, starting in lowercase. Also shown to the trainer. |
| `recap` | no | Read at the end, after "To sum up:", when learning on your own. |
| `trainerNotes` | no | Shown in the window when learning with a trainer. |
| `steps` | yes | A list of 1 to 200 steps, between square brackets. |

Any other field is an error, so a typing mistake in a field name is caught.

### Steps

Every step has a `kind`: `explain`, `practice`, `question` or `mission`.

**explain**: something said. The student presses Return to go on.

| Field | Required | |
| --- | --- | --- |
| `text` | yes | What's said. |

**practice**: the student presses keys. Practice steps come back in the quick check at the end of the lesson, in Daily Practice and in the review.

| Field | Required | |
| --- | --- | --- |
| `task` | yes | What the keys do, said as "Try it: *task*." For example `Go to the next heading`. |
| `keys` | yes | The keys, in words, such as `VO Command H`. Also said to the student. |
| `tip` | no | Said after the task when learning on your own, and with the hint (H). |

Each practice step in a lesson needs different keys, so the quick check can tell them apart. Keys the lessons themselves use can't be practiced on their own: Return, Escape, R, B, H and S.

**question**: a question answered with the number keys.

| Field | Required | |
| --- | --- | --- |
| `prompt` | yes | The question. |
| `options` | yes | 2, 3 or 4 answers. |
| `answer` | yes | The number of the right answer, counting from 1. |
| `why` | yes | Said after the right answer, to explain it. |

**mission**: a real task, done anywhere on the Mac.

| Field | Required | |
| --- | --- | --- |
| `task` | yes | What to do. |
| `check` | yes | How the lesson knows it's done: the bundle ID of an app, such as `com.apple.Safari`, which is done when that app comes to the front; or `yourWord`, which is done when the student comes back and presses Return. With `yourWord`, say "Press Return here when you've done it." in the task. |
| `tip` | no | Said when learning on your own, and with the hint (H). |

Some bundle IDs: Safari `com.apple.Safari`, Mail `com.apple.mail`, Messages `com.apple.MobileSMS`, Calendar `com.apple.iCal`, Finder `com.apple.finder`, TextEdit `com.apple.TextEdit`, Pages `com.apple.iWork.Pages`, Zoom `us.zoom.xos`, Microsoft Teams `com.microsoft.teams2`, Microsoft Word `com.microsoft.Word`, Google Chrome `com.google.Chrome`. To find any app's bundle ID, run `osascript -e 'id of app "App Name"'` in Terminal.

### Key names

Write the keys held first, then one key, separated by spaces (or `+`). Capitals don't matter.

- **Held keys:** `VO` (Control and Option, or Caps Lock if it's set as the VO key; `Control Option` means the same), `Command` (or `Cmd`), `Shift`, `Option` (or `Opt`, `Alt`), `Control` (or `Ctrl`).
- **Letters and digits:** `A` to `Z`, `0` to `9`. Letters are matched by the letter typed, so they work on any keyboard layout.
- **Arrows:** `Left Arrow`, `Right Arrow`, `Up Arrow`, `Down Arrow` (or just `Left`, `Right`, `Up`, `Down`).
- **Other keys:** `Space`, `Return` (or `Enter`), `Tab`, `Escape` (or `Esc`), `Delete` (or `Backspace`), `Forward Delete`, `Home`, `End`, `Page Up`, `Page Down`, `F1` to `F12`.
- **Punctuation:** `Equals` (or `Plus`), `Minus`, `Left Bracket`, `Right Bracket`, `Semicolon`, `Apostrophe`, `Comma`, `Period`, `Slash`, `Backslash`, `Grave Accent`.

Examples: `VO Shift Down Arrow`, `VO Command H`, `Option Command V`, `Control Tab`, `Command Shift A`, `VO F8`.

Leave out Fn: on a laptop, VO F8 is pressed with Fn, but the keys are still written `VO F8`, and the lessons remind laptop users about Fn.

## A full example

```json
{
  "format": 1,
  "title": "Our library's website",
  "summary": "Finding opening hours and searching the catalogue.",
  "goals": "going to the library's website, jumping to its headings, and searching the catalogue.",
  "recap": "Command L goes to the address field. VO Command H jumps by heading, and VO U opens the rotor.",
  "trainerNotes": "Open the library's site in Safari before starting. Let the learner find the opening hours on their own.",
  "steps": [
    { "kind": "explain", "text": "In this lesson you'll use the library's website. Open Safari with Spotlight: Command Space, type Safari, and press Return." },
    { "kind": "mission", "task": "Open Safari, for real.", "check": "com.apple.Safari", "tip": "Come back to the lessons with Command Tab when you hear Done." },
    { "kind": "practice", "task": "Go to the address field", "keys": "Command L" },
    { "kind": "practice", "task": "Go to the next heading", "keys": "VO Command H", "tip": "Headings are like the titles of a newspaper's articles." },
    { "kind": "practice", "task": "Open the rotor", "keys": "VO U" },
    { "kind": "question", "prompt": "Where are the opening hours usually found?", "options": ["Under a heading such as Visit or Hours", "In the address field", "In the Dock"], "answer": 1, "why": "Most websites put opening hours under their own heading, so VO Command H finds them quickly." },
    { "kind": "mission", "task": "Now for real: find the library's opening hours, and press Return here when you've heard them.", "check": "yourWord" }
  ]
}
```

## Tips for writing lessons

- Keep sentences short and plain, one idea at a time, like the built-in lessons.
- Start with an `explain` step that says what the lesson is about.
- Explain keys before a practice step asks for them.
- Practice keys aren't carried out by VoiceOver during an imported lesson; the app catches them. Use a mission to have the student do it for real.
- Shortcuts in other apps change between versions. Check them in the app's menus (VO M) before teaching them.

## What the app checks

Importing stops at the first problem and says where it is, for example:

- `Step 3: unknown key name 'VO Comand H'.`
- `Step 2: unknown field 'tsk'. A practice step can have: keys, task, tip.`
- `Step 5: 'answer' must be the number of the right option, from 1 to 3.`
- `Step 4: the keys 'VO H' are already practiced in step 2.`
- `Step 1: 'check' must be yourWord, or the bundle ID of the app that should be in front, such as com.apple.Safari.`
- `Unknown field 'author'. A lesson can have: format, title, summary, goals, recap, trainerNotes and steps.`
- `This file isn't a lesson file: its text isn't valid JSON.` (followed by where the JSON went wrong)
