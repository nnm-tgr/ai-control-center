# UI Spec

AI Control Center の画面仕様書。

Apple Human Interface Guidelines に準拠。  
Swift 6 + SwiftUI。最小ターゲット: macOS 14 Sonoma。

---

## 画面一覧

| 画面 | 種別 | MVP | 説明 |
|------|------|-----|------|
| Dashboard | Main Window | ✅ | 全エージェント一覧 |
| Agent Detail | Sheet / Split View | ✅ | 単一エージェントの詳細と Activity |
| Settings | Settings Window | ✅ | アプリ設定（ルートパス、通知など） |
| MenuBar | NSStatusItem | ✅ | メニューバーのクイックビュー |
| Notification Center | System | ✅ | macOS 通知（UI コードなし） |
| Timeline | Tab / View | v1.2 | 時系列の Activity ビュー |
| Workflow | Tab / View | v1.2 | フェーズ別進捗 |
| Git Detail | Sheet | v1.1 | Git ステータス詳細 |

---

## 1. Dashboard

### 目的

すべての AI エージェントを一画面に表示し、5秒以内に全状況を把握させる。

### ウィンドウ仕様

| 項目 | 値 |
|------|-----|
| 最小サイズ | 800 × 500 pt |
| デフォルトサイズ | 1100 × 680 pt |
| リサイズ | 可能 |
| スタイル | `.titlebarAppearsTransparent` |
| ツールバー | 表示 |

### レイアウト

```
┌──────────────────────────────────────────────────────────────┐
│ [AI Control Center]          [Filter ▼] [Sort ▼] [+] [⚙]   │  ← Toolbar
│                 [🔍 Search projects and tasks...          ]  │  ← Search Bar
├──────────────────────────────────────────────────────────────┤
│ PROJECT          AGENT         STATUS        ELAPSED  BRANCH │  ← Header
├──────────────────────────────────────────────────────────────┤
│ ● Clinic System  Claude Code  ● Waiting   3m 22s  feat/auth │
│ ● Flutter App    Claude Code  ● Thinking  0m 45s  main      │
│ ● AWS Build      Claude Code  ● Running   1m 12s  infra/vpc │
│ ○ CMS            Claude Code  ○ Idle      —       main      │
│ ● AI Framework   Cursor       ● Error     8m 03s  dev       │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│                    ← Current Task →                          │
│    "Waiting for permission: write to package.json"          │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

検索バーはツールバー直下に常時表示する（`⌘F` フォーカス前はプレースホルダーのみ表示）。  
検索中は Filter / Sort メニューとの AND 条件で絞り込む。

### 表示カラム

| カラム | 幅 | 内容 |
|--------|-----|------|
| Status Dot | 12pt | カラードット（色は AgentStatus に対応） |
| Project | 180pt | プロジェクト名 |
| Agent | 120pt | エージェント種別（アイコン + テキスト） |
| Status | 100pt | ステータスバッジ |
| Elapsed | 80pt | 最後の状態変化からの経過時間 |
| Branch | 120pt | Git ブランチ名（`#monospace`） |
| Current Task | 残り全幅 | `task` フィールドの値。省略時は em-dash |

### ステータスカラー

| ステータス | カラー | SwiftUI Color |
|-----------|--------|--------------|
| `idle` | グレー | `.secondary` |
| `thinking` | ブルー | `.blue` |
| `running_command` | イエロー | `.yellow` |
| `waiting_user` | オレンジ | `.orange` |
| `completed` | グリーン | `.green` |
| `error` | レッド | `.red` |

### インタラクション

| 操作 | 動作 |
|------|------|
| 行シングルクリック | Agent Detail を右ペインまたは Sheet で開く |
| 行ダブルクリック | ターミナルへジャンプ |
| 右クリック | コンテキストメニュー表示 |
| `⌘R` | 手動リフレッシュ（全プロジェクト再スキャン） |
| `⌘,` | Settings を開く |
| `⌘F` | 検索バーにフォーカス（インクリメンタルサーチ開始） |
| `Escape` | 検索バーをクリアしてフォーカスを解除 |
| `↑↓` | 行選択移動 |
| `Enter` | 選択行の Detail を開く |
| `Space` | ターミナルジャンプ（Quick Look 的に） |

### 右クリックメニュー

```
Jump to Terminal          ⌘↵
Show Detail               ⌘D
─────────────────
Copy Project Path
Copy Status JSON
─────────────────
Open in Finder
Open .ai/ Folder
─────────────────
Remove from Dashboard
```

### フィルター

```
[All ▼]  →  All / Needs Attention / Active / Idle / Completed / Error
```

### ソート

```
[Sort ▼]  →  Status Priority / Project Name / Last Updated / Elapsed Time
```

### 検索（インクリメンタルサーチ）

#### 対象フィールド

| フィールド | 優先度 | 例 |
|-----------|--------|-----|
| プロジェクト名 (`Project.name`) | 高 | `"Clinic System"` |
| 現在のタスク (`Agent.currentTask`) | 高 | `"Refactoring AuthService"` |
| ブランチ名 (`Agent.branch`) | 中 | `"feature/auth-jwt"` |
| エージェント種別 (`AgentType.displayName`) | 低 | `"Claude Code"` |

#### 検索仕様

- **インクリメンタル**: 1文字入力するたびにリストが即座に絞り込まれる（デバウンスなし）
- **大文字小文字非区別**: `"clinic"` で `"Clinic System"` にマッチ
- **部分一致**: 先頭一致ではなく任意位置のマッチ
- **AND 条件**: フィルター（Status 絞り込み）とソートは検索と同時に適用される
- **ハイライト**: マッチした文字列部分を `.yellow` でハイライト表示（`AttributedString` を使用）

#### 検索バーの状態

| 状態 | 表示 |
|------|------|
| 未フォーカス・空 | プレースホルダー `"Search projects and tasks..."` をグレーで表示 |
| フォーカス中・空 | カーソルのみ。リストは絞り込まれない |
| 入力中 | マッチする行のみ表示。マッチ文字をハイライト |
| 0件マッチ | `"No results for 'xxx'"` を中央に表示（空状態とは別の表示） |

#### 0件マッチの空状態

```
┌────────────────────────────────────┐
│                                    │
│    No results for "auth"           │
│                                    │
│    Try clearing the search or      │
│    changing the filter.            │
│                                    │
│    [Clear Search]                  │
│                                    │
└────────────────────────────────────┘
```

#### DashboardViewModel への追加

```
// 追加プロパティ
var searchText: String = ""
var isSearchFocused: Bool = false

// 既存の filteredProjects を拡張
var displayedProjects: [Project] {
    let afterFilter = filteredProjects   // 既存のフィルター適用済み
    guard !searchText.isEmpty else { return afterFilter }
    return afterFilter.filter { project in
        let query = searchText.lowercased()
        return project.name.lowercased().contains(query)
            || project.primaryAgent?.currentTask?.lowercased().contains(query) == true
            || project.primaryAgent?.branch?.lowercased().contains(query) == true
            || project.primaryAgent?.agentType.displayName.lowercased().contains(query) == true
    }
}
```

### 空状態（プロジェクトがゼロ）

```
┌────────────────────────────────────┐
│                                    │
│         🤖                         │
│                                    │
│    No Projects Found               │
│                                    │
│    Add a root directory in         │
│    Settings to get started.        │
│                                    │
│         [Open Settings]            │
│                                    │
└────────────────────────────────────┘
```

### ローディング状態

初回スキャン中は、各行に Skeleton View（グレーの矩形アニメーション）を表示。  
個別プロジェクトのリフレッシュ中は、対象行の Status カラムに小さな `ProgressView` を表示。

---

## 2. Agent Detail

### 目的

選択したエージェントの Activity 履歴と詳細情報を表示する。

### 表示方法

**Design Decision #4**: MVP では Inspector パネル（右側スプリット）として実装する。  
Sheet も検討したが、Dashboard を見ながら Detail を参照できる方が UX として優れているため。  
将来的に両方をサポートするオプションをユーザーに提供。

### レイアウト

```
┌─────────────────────────────────────────────────┐
│ ◀ Back                          [Jump Terminal] │  ← Toolbar
├─────────────────────────────────────────────────┤
│  🤖 Claude Code          ● Thinking             │
│  Clinic System · feature/auth-jwt               │
│  Started 09:00 · Running for 42m 17s            │
├─────────────────────────────────────────────────┤
│  Current Task                                   │
│  "Refactoring AuthService to use JWT"           │
│                                                 │
│  Workflow:  [Spec]─[Plan]─[►Coding]─[Review]   │
│  Progress:  ████████░░  65%                     │
├─────────────────────────────────────────────────┤
│  Activity                                       │
│                                                 │
│  09:00  ● Thinking    Started task              │
│  09:12  ● Running     swift build               │
│  09:13  ● Thinking    Analyzing errors          │
│  09:35  ● Running     swift build               │
│  09:36  ● Thinking    ← current                │
│                                                 │
└─────────────────────────────────────────────────┘
```

### Activity タイムライン

- 新しい順（上が最新）または古い順（上が最古）をユーザーが選択可能
- ステータスのカラードットを左に表示
- 時刻は `HH:mm` 形式（今日）、昨日以前は `MM/dd HH:mm`
- `duration` がある場合は `(3m 12s)` を右端に表示
- 最大 200 件表示（スクロール可能）

### インタラクション

| 操作 | 動作 |
|------|------|
| `Jump to Terminal` ボタン | ターミナルにフォーカス移動 |
| Activity 行クリック | （v1.2）その時点の詳細ログ表示 |
| `⌘C` on Activity | タイムラインをテキストとしてコピー |

### 空状態（Activity なし）

```
Activity is empty.
Waiting for the agent to update.
```

---

## 3. Settings

### 目的

ウォッチするルートディレクトリ、通知設定、ターミナル設定を管理する。

### ウィンドウ仕様

| 項目 | 値 |
|------|-----|
| サイズ | 560 × 480 pt（固定） |
| スタイル | `.titled` + タブバー |
| 開き方 | `⌘,` または Toolbar ボタン |

### タブ構成

```
[General]  [Notifications]  [Terminal]  [Advanced]
```

#### General タブ

```
Watched Directories
┌─────────────────────────────────────────┐
│ /Users/me/dev/personal                 │
│ /Users/me/dev/work                     │
└─────────────────────────────────────────┘
[+ Add Directory]  [- Remove]

Scan Depth:   [3] (stepper, 1–10)

Excluded Directories:
.git, node_modules, .build, DerivedData
[Edit...]

□ Show in Menu Bar
□ Launch at Login
```

#### Notifications タブ

```
□ Enable Notifications

Notify when:
  ✓ Waiting for User Input    (always if enabled)
  ✓ Error Occurred            (always if enabled)
  ✓ Task Completed            
  □ Phase Changed             
  □ Status Changed (all)      

Minimum Level:  [Normal ▼]  (Low / Normal / High / Critical)

□ Do Not Disturb Mode
  Mute all notifications
```

#### Terminal タブ

```
Default Terminal:
  ( ) Terminal.app
  ( ) iTerm2           ⚠ Not installed
  (●) Ghostty          ✓ Available
  ( ) Warp             ✓ Available

[Test Jump]
```

#### Advanced タブ

```
Activity Retention:  [200] entries per agent

□ Enable Git Integration
  Git Poll Interval:  [30] seconds

□ Show elapsed time in menu bar icon
□ Debug mode (verbose logging)

[Reset All Settings]  [Export Settings]
```

### インタラクション

| 操作 | 動作 |
|------|------|
| `+ Add Directory` | `NSOpenPanel`（`.canChooseFiles = false`）でフォルダ選択 |
| `- Remove` | 選択行を削除（確認ダイアログなし、Undo 対応） |
| `Test Jump` | 現在選択中のターミナルを起動してテスト |
| `Reset All Settings` | 確認ダイアログを出してから `UserDefaults` をリセット |

---

## 4. MenuBar

### 目的

常駐するメニューバーアイコンから、ウィンドウを開かずにクイックステータスを確認する。

### アイコン

- SF Symbol: `cpu.fill` または カスタムアイコン
- 状態に応じてバッジを付与:
  - 注意が必要なエージェントがいる場合: 赤いドット
  - アクティブなエージェントがいる場合: 青いドット
  - すべて Idle / Completed: バッジなし

### メニュー展開時

```
AI Control Center
─────────────────────────────
● Clinic System    Waiting  3m
● Flutter App      Thinking 45s
● AWS Build        Running  1m
○ CMS              Idle     —
● AI Framework     Error    8m
─────────────────────────────
  2 need attention
─────────────────────────────
Open Dashboard            ⌘⇧A
─────────────────────────────
Preferences...            ⌘,
Quit AI Control Center    ⌘Q
```

### インタラクション

| 操作 | 動作 |
|------|------|
| プロジェクト行クリック | Dashboard を開き、対象エージェントを選択状態にする |
| `Open Dashboard` | Dashboard ウィンドウを前面に |
| メニューバーアイコン右クリック | 同メニュー |

**Design Decision #5**: MenuBar の行数は最大 10 件に制限する。  
それ以上ある場合は「他 N 件」リンクで Dashboard へ誘導。スクロール可能メニューは HIG 非推奨のため。

---

## 5. 将来画面

### Timeline View（v1.2）

全エージェントの活動を時系列で表示する Gantt チャート的なビュー。

```
          09:00   09:30   10:00   10:30   11:00
Clinic    ██████thinking████ ██running█ ██waiting
Flutter   ████thinking██████████████████████████
AWS       ██████████████running██████ completed
CMS       idle
```

### Workflow View（v1.2）

フェーズごとの進捗サマリ。

```
Project: Clinic System

[ Spec ✓ ] → [ Plan ✓ ] → [ Coding ▶ 65% ] → [ Review ] → [ Test ]
```

### Git Detail Sheet（v1.1）

```
Branch: feature/auth-jwt
↑ 3 commits ahead of origin
↓ 0 commits behind

Changed files: 7
  M  AuthService.swift
  M  AuthViewModel.swift
  A  JWTService.swift
  ...

[Open in GitHub]  [Show in Sourcetree]
```

---

## カラー・タイポグラフィ方針

### カラー

- システムカラーのみ使用（`.blue`, `.red`, `.green` など）
- カスタムカラーは使わない → ダークモード対応が自動化される
- アクセントカラーはシステム設定に従う

### タイポグラフィ

| 用途 | Font | Size |
|------|------|------|
| プロジェクト名 | `.body` | 13pt |
| ステータス | `.callout` | 12pt |
| ブランチ名 | `.monospacedSystemFont(ofSize:)` | 11pt |
| 経過時間 | `.caption` | 11pt |
| Current Task | `.body` secondary | 13pt |
| Activity タイムスタンプ | `.monospacedSystemFont(ofSize:)` | 11pt |
| Settings ラベル | `.body` | 13pt |

### スペーシング

- 行の高さ: 44pt（HIG 推奨タップターゲット。macOS では 36pt でも可）
- セクション間パディング: 16pt
- カラム間パディング: 12pt

---

## アクセシビリティ方針

- すべてのインタラクティブ要素に `accessibilityLabel` を付与
- ステータスドットは色のみに依存しない（テキストも併記）
- VoiceOver でエージェント行を読み上げる際: `"Clinic System, Claude Code, Waiting, 3 minutes 22 seconds"`
- キーボードのみで全操作可能にする
- `Dynamic Type` には対応しない（デスクトップアプリのため最小 11pt を保証）
