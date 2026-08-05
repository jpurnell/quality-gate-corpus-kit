# quality-gate-corpus-kit Master Plan

> **ACTION REQUIRED:** Replace all `[PLACEHOLDER]` sections below with your
> project's actual content. This file is the source of truth for project vision,
> architecture, and goals. Do not start implementation until it is filled in.

**Purpose:** Source of truth for project vision, architecture, and goals.

---

## Project Overview

### Mission
[1-2 sentences: what this project does and why it exists.]

### Target Users
- [Who uses this? Be specific about roles and contexts.]

### Key Differentiators
- [What makes this different from alternatives?]

---

## Architecture

### Technology Stack
- **Language:** Swift 6.0+
- **Build System:** Swift Package Manager
- **Testing:** Swift Testing framework
- **Concurrency:** Swift 6 strict concurrency throughout
- [Add frameworks: SwiftUI, SwiftData, Vapor, etc.]
- [Add dependencies: BusinessMath, etc.]

### Module Structure

```
Sources/[ProjectName]/
├── [Describe your source layout here]
└── ...
```

### Key Types

| Type | Purpose |
|------|---------|
| `[TypeName]` | [What it does] |

### Data Flow

```
[Describe the primary data pipeline from input to output]
```

---

## Core Architectural Decisions

1. [Decision 1 — what you chose and why.]
2. [Decision 2]
3. [Add more as needed]

---

## Current Status

### What's Working
- [ ] [List completed milestones]

### What's Next
- [ ] [List upcoming work items]

---

## Quality Standards

### Code Quality
- All code follows `coding_rules.md`
- TDD: failing tests before implementation
- Documentation for all public APIs
- No warnings in build output
- Quality gate: 0 errors, 0 warnings before every commit

### Documentation Quality
- DocC comments for all public functions
- Usage examples in documentation
- Articles for complex topics

---

## Collaboration Principles

### AI as Sparring Partner, Not Oracle

AI proposes; the human interrogates. High AI confidence triggers harder questions, not faster acceptance.

- **Interrogate confident outputs.** When the AI states something with certainty, ask for the counterargument before accepting.
- **Demand counterarguments.** Before locking in an approach, require an explicit case for the strongest alternative.
- **Sit with discomfort.** Resist the pull to take the first plausible answer.

This principle is operationalized in the **Adversarial Review** step of `design_proposal.md`.

---

## Roadmap

### Phase 1: [Name]
- [ ] [Milestone]

### Phase 2: [Name]
- [ ] [Milestone]

### Future
- [Ideas not yet committed to]

---

**Last Updated:** [DATE] ([brief note on what changed])
