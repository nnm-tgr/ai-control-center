# AI Control Center

> **AI Development Operating System for macOS**  
> Monitor and manage all your AI agents — in one place, at a glance.

![Platform](https://img.shields.io/badge/platform-macOS-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Status](https://img.shields.io/badge/status-MVP%20complete-brightgreen)

---

## The Problem

Modern AI-assisted development means running multiple agent sessions at once.

On any given day, a developer might have:

- `Claude Code` working on a Clinic System backend
- `Claude Code` refactoring a Flutter app
- `Claude Code` writing Terraform for AWS
- `Cursor Agent` reviewing a CMS PR
- Another session generating tests

**That's 5–10 terminal windows, all running in parallel.**

And you have no idea what's happening in any of them.

```
Is Claude thinking?     → Switch to Terminal 3
Did the command fail?   → Switch to Terminal 7
Is it waiting for me?   → Switch to Terminal 1, 2, 4...
Which project is stuck? → ???
```

You end up context-switching constantly — not between *tasks*, but between *terminals*. Your cognitive overhead isn't development. It's tab management.

**This is the problem AI Control Center is built to solve.**

---

## Concept

AI Control Center is not a "Claude Code wrapper."

It is an **AI Development Operating System**.

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│   You open the dashboard.                           │
│   In 5 seconds, you know:                           │
│                                                     │
│     ● Which agents are running                      │
│     ● Which are waiting for your input              │
│     ● Which projects are in danger                  │
│     ● Which just completed                          │
│                                                     │
│   You click one. You're there.                      │
│                                                     │
└─────────────────────────────────────────────────────┘
```

A single, native macOS app that gives you a mission-control view of your entire AI development ecosystem — across every project, every agent, every session.

---

## Architecture Philosophy

### The Core Principle: File-Based Status, Not Terminal Parsing

Many "AI monitoring" tools try to scrape terminal output. This approach is fragile, tightly coupled to each agent's internal implementation, and breaks the moment the agent changes its output format.

AI Control Center takes a different approach.

**Agents write. The dashboard reads.**

```mermaid
flowchart LR
    subgraph Projects
        A[Clinic System\n.ai/agent-status.json]
        B[Flutter App\n.ai/agent-status.json]
        C[AWS Build\n.ai/agent-status.json]
    end

    subgraph AI Control Center
        W[FSEventStream]
        P[Status Parser]
        D[Dashboard UI]
    end

    A -->|writes| W
    B -->|writes| W
    C -->|writes| W
    W --> P --> D
```

Each project maintains an `.ai/` directory. The agent running in that project writes its current status to `agent-status.json`. AI Control Center watches those files using `FSEventStream` — Apple's native file system event API — and reflects changes in real time.

This means:
- **Zero coupling** to any specific AI tool's internals
- **Extensible** — any agent that can write a JSON file can integrate
- **Reliable** — file watching is a solved, stable macOS primitive
- **Fast** — FSEventStream delivers events in milliseconds

---

## Features

### Agent Dashboard

A real-time view of all active AI agents across all watched projects.

| Column | Description |
|--------|-------------|
| **Project** | Name of the project being worked on |
| **Agent** | The AI tool running (Claude Code, Cursor, etc.) |
| **Status** | Current agent state with color coding |
| **Elapsed** | Time since last state change |
| **Current Task** | What the agent is doing right now |
| **Git Branch** | Active branch for context |

#### Status Indicators

```
● Idle              Gray    — Agent is ready, nothing running
● Thinking          Blue    — LLM is generating a response
● Running Command   Yellow  — Executing shell commands
● Waiting for User  Amber   — Input or permission required
● Completed         Green   — Task finished successfully
● Error             Red     — Something went wrong
```

Designed to be scannable at a glance. No reading required.

### Notifications

Native macOS notifications triggered by meaningful state transitions. Notification level is derived from the new state:

| Trigger | Level |
|---------|-------|
| Agent error | Critical |
| Waiting for user input | High |
| Task completed | Normal |
| Other transitions | Low (silent) |

Spurious notifications are suppressed — for example, `thinking → runningCommand` (already active) does not fire.

### Agent Detail & Activity Log

Click any agent to open its detail view: a per-agent timeline showing the full history of state transitions with timestamps.

```
14:05  ●  Running Tests
14:08  ●  Waiting for User
14:12  ●  Thinking
14:20  ●  Completed
```

### Terminal Jump

Click any agent row to immediately switch focus to its terminal window — supporting Terminal.app, iTerm2, and Warp via AppleScript and URL scheme providers.

### Tool Approval

When an agent requests permission to run a tool, a native approval overlay appears in the dashboard. Approve or deny without leaving the app. Approval decisions are written back to the project's `.ai/settings.json` for the agent to pick up.

### Task Management

A built-in task tracker, scoped to individual projects or shared globally across all watched roots.

**Task properties:**

| Field | Description |
|-------|-------------|
| **Title** | What needs to be done |
| **Status** | To Do / In Progress / In Review / On Hold / Done |
| **Priority** | Low / Medium / High / Urgent |
| **Scope** | Project-specific, group, or global |
| **Progress** | 0–100% (auto-derived from subtasks) |
| **Due date** | Optional deadline |
| **Category** | Color-coded label |
| **Notes** | Multiple rich-text notes per task |
| **Subtasks** | One level of child tasks with auto-rollup progress |

**Task groups** allow tasks to be organized into named, color-coded buckets independent of any single project.

**Auto-rollup:** completing or progressing subtasks automatically updates the parent task's progress and status.

### Menu Bar

A compact menu bar item gives instant access to the dashboard and key agent states without bringing the full window to the foreground.

### Settings

- Add and remove watched root directories (sandbox-aware bookmark persistence)
- Configure excluded directory names for the scanner
- Choose terminal provider (Terminal, iTerm2, Warp, Ghostty)
- Configure tool approval behavior and timeout

---

## Architecture Overview

```mermaid
graph TB
    subgraph macOS App — AI Control Center
        direction TB
        UI[SwiftUI Views]
        AS[AppState\n@Observable @MainActor]
        TS[TaskStore\n@Observable @MainActor]
        FW[FileWatcherService\nAsyncStream push]
        PS[ProjectScannerService]
        NS[NotificationService\nUNUserNotificationCenter]
        TA[ToolApprovalService]
        SS[SettingsStore]

        UI <-->|observe| AS
        UI <-->|observe| TS
        AS --> FW
        AS --> PS
        AS --> NS
        AS --> TA
        AS --> SS
    end

    subgraph Infrastructure
        AFS[AsyncFSEventStream]
        FSW[FSEventStreamWrapper\nC-level callback]
        AFS --> FSW
        FW --> AFS
    end

    subgraph File System
        P1[project-a/.ai/agent-status.json]
        P2[project-b/.ai/agent-status.json]
    end

    FSW -->|FSEventStream| P1
    FSW -->|FSEventStream| P2
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **SwiftUI + macOS native** | Performance, Apple HIG compliance, no Electron overhead |
| **Swift `@Observable` + `@MainActor`** | Swift 6 native observation; no ObservableObject or Combine |
| **`AsyncStream` push model** | `FileWatcherService` emits `WatcherEvent` values; `AppState` consumes them in a stored `Task<Void, Never>` — no polling, no memory leaks |
| **FSEventStream** for file watching | Apple's recommended low-level API, sub-millisecond latency, battery efficient |
| **JSON status files** as the integration contract | Decoupled from any specific agent implementation |
| **No terminal scraping** | Terminal output formats are unstable and agent-specific |
| **O(1) task lookup** | `TaskStore` maintains a `[UUID: Int]` index over the tasks array; CRUD is index-based |

---

## Directory Structure

```
ai-control-center/
│
├── AIControlCenter.xcodeproj/
│
├── AIControlCenter/
│   ├── App/
│   │   ├── AIControlCenterApp.swift        # Entry point
│   │   └── AppDelegate.swift               # NSApp lifecycle
│   │
│   ├── Dashboard/
│   │   ├── DashboardView.swift             # Main project list
│   │   ├── DashboardViewModel.swift        # Filter / sort logic
│   │   ├── ProjectGroupRowView.swift       # Expandable project row
│   │   ├── AgentRowView.swift              # Single agent row
│   │   ├── StatusBadgeView.swift           # Color-coded status pill
│   │   ├── ElapsedTimeView.swift           # Live elapsed timer
│   │   ├── ApprovalOverlayView.swift       # Tool approval UI
│   │   └── BannerOverlayView.swift         # Transient notification banners
│   │
│   ├── Detail/
│   │   ├── AgentDetailView.swift           # Activity log + agent info
│   │   ├── AgentDetailViewModel.swift
│   │   └── ActivityRowView.swift           # Single timeline entry
│   │
│   ├── Tasks/
│   │   ├── TaskSectionView.swift           # Scoped task list
│   │   ├── TaskRowView.swift               # Single task row
│   │   ├── TaskDetailView.swift            # Full task detail + subtasks
│   │   ├── TaskSummaryView.swift           # Progress summary widget
│   │   ├── TaskStatusIndicatorView.swift   # Status icon
│   │   ├── AddEditTaskSheet.swift          # Create / edit sheet
│   │   └── NoteEditorView.swift            # Per-task note editor
│   │
│   ├── MenuBar/
│   │   └── MenuBarView.swift               # Menu bar popover
│   │
│   ├── Settings/
│   │   └── SettingsView.swift
│   │
│   └── Core/
│       ├── Models/
│       │   ├── Agent.swift                 # Agent domain model
│       │   ├── AgentStatus.swift           # Status enum + display
│       │   ├── AgentStatusFile.swift       # Decodable JSON contract
│       │   ├── AgentType.swift
│       │   ├── AppError.swift              # Typed error hierarchy
│       │   ├── AppNotification.swift
│       │   ├── GitStatus.swift
│       │   ├── Project.swift               # Project domain model
│       │   ├── Settings.swift
│       │   ├── SettingsStore.swift         # Bookmark-aware persistence
│       │   ├── TaskItem.swift              # Task + subtask + note models
│       │   ├── TerminalProviderType.swift
│       │   ├── ToolApprovalRequest.swift
│       │   └── WorkflowPhase.swift
│       │
│       ├── Services/
│       │   ├── FileWatcherService.swift    # FSEvent → WatcherEvent stream
│       │   ├── ProjectScannerService.swift # Discovers .ai/ dirs
│       │   ├── StatusParserService.swift   # JSON → Agent model
│       │   ├── NotificationService.swift   # UNUserNotificationCenter
│       │   ├── TaskStore.swift             # Task CRUD + O(1) index
│       │   ├── ToolApprovalService.swift
│       │   └── Terminal/
│       │       ├── TerminalService.swift
│       │       ├── TerminalProvider.swift
│       │       ├── AppleScriptTerminalProvider.swift
│       │       ├── URLSchemeTerminalProvider.swift
│       │       └── FallbackTerminalJump.swift
│       │
│       ├── Infrastructure/
│       │   ├── AsyncFSEventStream.swift    # AsyncStream<URL> adapter
│       │   └── FSEventStreamWrapper.swift  # C-level FSEventStream bridge
│       │
│       ├── State/
│       │   └── AppState.swift              # Single source of truth
│       │
│       └── Extensions/
│           ├── Color+AgentStatus.swift
│           ├── Color+TaskPriority.swift
│           └── Color+TaskStatus.swift
│
├── tests/
│   ├── test_task_store.swift               # TaskStore unit tests
│   └── test_notification_rules.swift       # NotificationRule unit tests
│
├── .ai/                                    # This project's own status
│   └── agent-status.json
│
└── README.md
```

---

## Agent Status Contract

Any agent that writes the following JSON to `.ai/agent-status.json` in its project root will appear automatically in AI Control Center.

```json
{
  "schema_version": "1.0",
  "agent": "claude-code",
  "status": "thinking",
  "task": "Refactoring AuthService to use JWT",
  "workflow_phase": "coding",
  "progress": 0.65,
  "branch": "feature/auth-jwt",
  "worktree": "/Users/me/projects/clinic",
  "started_at": "2026-07-28T09:00:00Z",
  "updated_at": "2026-07-28T09:42:17Z"
}
```

### Status Values

| Value | Meaning |
|-------|---------|
| `idle` | Agent is ready and waiting |
| `thinking` | LLM is generating a response |
| `running_command` | Shell command is executing |
| `waiting_user` | Input or approval required |
| `completed` | Task finished |
| `error` | Agent encountered an error |

This contract is intentionally minimal. Fields are optional beyond `agent` and `status`. Future versions will add fields without breaking existing integrations.

---

## Supported Agents

| Agent | Status |
|-------|--------|
| Claude Code | Supported |
| Cursor Agent | Planned |
| OpenAI Codex / GPT-4 CLI | Planned |
| Gemini CLI | Planned |
| Aider | Planned |
| Custom / Any agent | Supported via JSON contract |

---

## Development

### Requirements

- macOS 14.0 Sonoma or later
- Xcode 16+
- Swift 6.0+

### Getting Started

```bash
git clone https://github.com/yourhandle/ai-control-center.git
cd ai-control-center
open AIControlCenter.xcodeproj
```

Press `⌘R` to build and run.

### Running Tests

Standalone test scripts require no Xcode test target:

```bash
# Task store logic
swift tests/test_task_store.swift

# Notification rule logic
swift tests/test_notification_rules.swift
```

### Adding a Test Project

To see the dashboard in action during development, create a mock status file:

```bash
mkdir -p ~/projects/my-project/.ai
cat > ~/projects/my-project/.ai/agent-status.json << 'EOF'
{
  "schema_version": "1.0",
  "agent": "claude-code",
  "status": "thinking",
  "task": "Writing unit tests",
  "branch": "feature/tests",
  "started_at": "2026-07-28T09:00:00Z",
  "updated_at": "2026-07-28T09:15:00Z"
}
EOF
```

Add `~/projects/my-project` as a watched root in Settings. AI Control Center will detect the agent automatically.

---

## Roadmap

```mermaid
gantt
    title AI Control Center Roadmap
    dateFormat  YYYY-MM
    section MVP
    FSEventStream watcher + AsyncStream     :done,    2026-07, 2026-08
    Agent status JSON contract              :done,    2026-07, 2026-08
    Dashboard with real-time status         :done,    2026-07, 2026-08
    macOS notifications (smart filtering)   :done,    2026-07, 2026-08
    Agent detail & activity log             :done,    2026-07, 2026-08
    Terminal jump (Terminal/iTerm2/Warp)    :done,    2026-07, 2026-08
    Tool approval workflow                  :done,    2026-07, 2026-08
    Task management (project + global)      :done,    2026-07, 2026-08
    Menu bar view                           :done,    2026-07, 2026-08

    section v1.1 — Polish
    Error display UI                        :         2026-09, 2026-10
    Deep subtask data model (2+ levels)     :         2026-09, 2026-10
    Git status integration                  :         2026-09, 2026-10
    Worktree support                        :         2026-09, 2026-10

    section v1.2 — Workflow
    Workflow phase display                  :         2026-10, 2026-11
    Progress bar per feature                :         2026-10, 2026-11
    Timeline view (Gantt-style)             :         2026-10, 2026-11

    section v2.0 — Multi Agent
    CPU/Memory per agent                    :         2026-11, 2027-01
    Multi-agent broadcast commands          :         2026-11, 2027-01
    Cursor / OpenAI agent support           :         2026-11, 2027-01
    Claude Code hook integration            :         2026-11, 2027-01
```

### Milestone Summary

| Version | Theme | Key Deliverable |
|---------|-------|-----------------|
| **MVP** | Visibility + Task tracking | Real-time agent dashboard, terminal jump, tool approval, task management |
| **v1.1** | Polish + Context | Error UI, git branch display, worktree support |
| **v1.2** | Workflow | Phase display, feature progress bars, timeline |
| **v2.0** | Control | Multi-agent commands, resource usage, broader agent support |

---

## Contributing

Contributions are welcome, particularly:

- **Agent integrations** — If you write a hook or adapter for a new agent, please open a PR
- **Status contract feedback** — Thoughts on the `.ai/agent-status.json` schema
- **macOS UI/UX** — SwiftUI improvements, animations, accessibility

### Guidelines

1. Keep Apple framework dependencies first — third-party libraries require strong justification
2. No Electron, no web views — this is a native macOS application
3. The file-watching architecture is non-negotiable — no terminal scraping
4. Follow Apple Human Interface Guidelines
5. Every PR should include a description of the user-visible change

### Opening Issues

Bug reports, feature requests, and schema proposals are all welcome via GitHub Issues. For new agent integrations, please include:
- The agent name and version
- How it can write to a file (hooks, config, plugin, etc.)
- A sample `agent-status.json` output

---

## Vision

The way we develop software is changing faster than our tooling.

We moved from one editor to many windows. From one language to many services. From one team to many agents.

But our workflow visibility hasn't caught up. We still switch between tabs and terminals, scanning for state. We lose context. We miss errors. We wait without knowing we should act.

**AI Control Center is the mission control that AI-assisted development has been missing.**

In the near future, a developer's workflow will look like this:

1. Open AI Control Center
2. See every agent across every project — at a glance
3. Know immediately what needs attention
4. Click to jump where you're needed
5. Close the loop

Not because AI is doing everything — but because you can finally see everything AI is doing.

The goal is not to automate development. It is to give the human developer **full situational awareness** in an environment where AI agents are doing increasingly complex, parallel, long-running work.

> *Build more. Context-switch less.*

---

## License

MIT License

Copyright (c) 2026 AI Control Center Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

<div align="center">
  <sub>Built for developers who work with AI agents every day.</sub>
</div>
