---
block: front-ends
doc: DECISIONS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Decisions

## Delegate by subprocess, not by calling internals

`scripts/PROJECTOR.sh` sources the two libraries for reading state, then runs `scripts/MAKE_BACKUP.sh` and `scripts/UNLOCK.sh` as separate bash processes for everything that writes. [verified]

The reason is in the script's own header: the backup path took several rounds to get right, block streaming, resume, stall detection and size assertions, and a second copy of that behind a nicer screen would be a second place for it to be quietly wrong. [verified]

### Rejected alternative: reimplement the flows inside the front end

A front end that called the step functions directly would gain a tidier progress display and lose the single implementation. The cost lands on the other blocks, since the failure would be a divergence between what the menu does and what the documented script does. [inferred]

## eval indirection instead of a nameref

`scripts/TOOLS.sh::section_items()` expands an array whose name is in a variable using eval, and the two callers that walk the menu arrays go through it. [verified]

It is chosen against its own author's preference: the comment in the file calls eval indirection uglier and keeps it because it works everywhere. [verified]

### Rejected alternative: local -n

Namerefs need bash 4.3 and macOS ships 3.2, so the nameref version died on the first menu draw for every Mac user while a Homebrew bash showed nothing wrong. See [INVARIANTS](INVARIANTS.md) for the floor this set and the test that holds it. [verified]

## Progress from the growing file, not from the child's output

`scripts/PROJECTOR.sh::run_backup()` computes percentage, rate and estimate from the size of the image on disk, sampled every two seconds. [verified]

The file is the thing being produced, so its size cannot disagree with reality the way a log line can. [verified]

### Rejected alternative: parse the progress output

The log is still read, for the block counters, the stall count and the visible tail, and that narrow use has already cost one defect: a fallback added to a counter that already printed zero produced a two line value and broke the arithmetic downstream. [verified]
