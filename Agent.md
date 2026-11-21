# Agent.md — goose_ui 開発・保守ガイド

このリポジトリは、Goose 言語（v2026.4+）向けの **保持モード・ゼロヒープ GUI フレームワーク `goose_ui`** です。[`win32-goose`](https://github.com/johmaru/win32-goose) を git サブモジュールとして使用し、追加の C コードを書かず純粋な Goose コードだけで構築されています。

---

## 1. アーキテクチャと不変条件

- **サブモジュール不変**: `win32-goose/` 配下は直接改変しない。追加 C ファイルも持ち込まず、`goose_ui` 側は純 Goose を維持する。
- **パッケージ設定 (`goose_ui.build`)**: `main_thread_only = true;` と `exclude = ["win32-goose", "examples", "test", "bench"];` を維持する。
- **ルートファイルの import 規約**: `examples/`, `test/`, `bench/` など外部ルートファイルでは、Goose の依存解決仕様上、推移依存も含めて両方を明記する：
  ```goose
  import win32 from "../win32-goose";
  import goose_ui from "..";
  ```
- **ゼロヒープ設計 (`root struct App`)**:
  - 全状態（`windows`, `widgets`, `free_widgets`, `str_pool`, `list_items`, `connections`, `timers`, `signals`, `focus_order`）は `root struct App` の独立データスタックに保持する。
  - Goose v1 の制約上、`root struct` 内に別の `root struct`（`slot_pool` / `slice_pool` 等）を値としてネストできないため、`App` 自身が直接 `[>..]` / `[>..<]` 配列を持つ。
- **コンパクトなメモリレイアウトを維持する**:
  - `Widget` / `ListItem` の文字列（`text`, `placeholder`, `tooltip`, `name`, `subtext`）は必ず `App.str_pool` ＋ 12 バイトの `StrSpan` で保持し、大きなインライン `u8[..N]` を構造体へ戻さない（現在 ~350 B/widget、既存容量内ならインプレース上書きで 0 バイト確保）。
  - `WidgetStyle` は `u32` パック RGBA ＋ ビットフラグでコンパクトに保つ。

---

## 2. デュアル描画バックエンドのルール

- **`RenderBackend.Software`（ダブルバッファ GDI + ClearType）**:
  - `d2d_create` を**一切呼ばない**ことで GPU ドライバの固定メモリ（約 56 MB）を回避する（空窓 ~9.2 MB / 5,000 個 ~11.3 MB / 初回描画 ~36 ms）。
  - フォント生成は `gdi32` の `CreateFontA`（`CLEARTYPE_QUALITY = 5`）を使用。
- **`RenderBackend.Direct2D`（Direct2D + DirectWrite GPU）**:
  - `win32-goose` 側のグローバルフォント上限が `W32_MAX_D2D_FONTS = 64` のため、ウィンドウあたり 6 フォント（`FontSet`）に抑え、`draw_text` 直前に `set_align` を切り替える。
- **パリティ維持**: `Painter` の描画プリミティブおよび `Canvas` のローカル座標オフセット（D2D は `set_transform`、GDI は `ox/oy`）は常に両バックエンドで同等動作させる。

---

## 3. UI 記述スタイル（いいとこ取り構成）

- **推奨スタイル (`dsl.goose`)**:
  - SwiftUI / Jetpack Compose 風のスコープ付きネスト DSL（`app.ui(win) { u => ... }` ＋ 16 バイト値ハンドル `Ui` / `Node` の UFCS メソッドチェーン）
  - ＋ Win32 風アクション ID（`.action(ID_*)` → `match app.action_id(s.widget)`、`app.by_id` / `app.text_of` / `app.set_text_of`）
  - ＋ 定型連動の宣言的 `app.connect(...)` / `.on_toggle_theme()`
- **絶対配置の逃げ道**: 固定ダイアログ等では `u.anchored_panel()`（`LayoutKind.None`）＋ `.bounds(x, y, w, h, ANCHOR_*)` による WinForms 風リサイズ追従を使う。
- 低レベルの Qt 風 API（`add_*` / `set_*`）も後方互換として維持する。

---

## 4. Goose v2026.4 コンパイラ・言語仕様の注意点

このリポジトリの開発中に踏んだ重要な仕様・制約：

1. **`pad` は予約語**: 構造体パディング用キーワードのため、変数名・引数名に `pad` は使えない（`padding` や `pd` を使う）。
2. **浮動小数→整数の切り捨ては `as!`**: `--debug` 実行時、小数部がある `float as i32` / `as i64` はランタイムアボートする。意図的な切り捨ては必ず `as!` を使う。
3. **冗長な拡大変換キャスト禁止**: `i32 -> f32`, `f32 -> f64`, `u8 -> i64` など暗黙拡大できる箇所に `as` を書くと警告になる。常に **エラー 0 / 警告 0** を維持する。
4. **複数戻り値と `match`**: `return match x { ... }` で複数値は返せない。各アーム内で明示的に `return a, b;` と書く。
5. **enum のワイルドカードは `_`**: `other => ...` のような任意識別子はバリアント名として解釈されるため `_ => ...` を使う。
6. **関数値（高階関数）**:
   - 関数値はコンパイル時ジェネリック引数のみで、通常の実行時引数には置けない。
   - コールバックが 2 つある場合（例: `exec_with_canvas<OnPaint, OnSignal>(app: App&)`）は、1 つ目を関数名引数・2 つ目をトレイリングブロックで渡す：`app.exec_with_canvas(paint_fn) { sig => ... };`。
   - トレイリングブロック内ではループ外で `continue` は使えない。
7. **再帰関数 (`recursive fn`)**: 明示的な引数・戻り値型が必要。再帰呼び出しを跨いでローカルの伸縮配列（`[>..]` / `[>..<]`）を生存させてはならない。
8. **TinyCC コード生成回避策**: ユニット enum バリアントをそのまま enum 引数関数に渡すと TinyCC で型変換エラー（`cannot convert '..._p' to '...'`）が出るケースがあったため、`run_connections` 等の内部ディスパッチでは整数コード（`signal_kind_code`）を使う。
9. **Win32 イベント範囲**: `win32-goose` の `w32_wndproc` はマウス・キーボード・`WM_CHAR`・`WM_SIZE`・`WM_PAINT`・`WM_COMMAND`・`WM_TIMER`・`WM_DROPFILES`・`WM_DPICHANGED` を転送する（`WM_NOTIFY` / `WM_HSCROLL` は未転送）。ダブルクリックは `tick_count_ms()` で Goose 側判定している。

---

## 5. 検証・ベンチマークコマンド

変更後は必ず以下で **エラー 0 / 警告 0・JIT `--debug`・ネイティブ Clang ビルド** を確認すること：

```powershell
# 全ファイルの型チェック
goose check test/goose_ui_test.goose
goose check examples/counter.goose
goose check examples/todo_app.goose
goose check examples/kitchen_sink.goose
goose check bench/goose_ui_bench.goose

# デバッグチェック付き JIT テスト（as 変換・境界チェック検証）
goose run --debug test/goose_ui_test.goose

# ネイティブ Clang ビルド＆実行
goose build test/goose_ui_test.goose && .\test\goose_ui_test.exe

# メモリ・起動速度ベンチマーク（vs Qt 6.11.1 Widgets / Quick / Python Tkinter）
pwsh -File bench/run_bench.ps1
```

ビルド生成物（`*.exe`, `bench/results.json`）はコミット前に削除する（`.gitignore` 対象）。

---

## 6. ドキュメント同期ルール

公開 API・DSL・ウィジェット・バックエンド・ベンチマーク結果を更新したら、以下のドキュメントも合わせて更新すること：
- `README.md` — プロジェクト概要・クイックスタート・ベンチマーク表・目次
- `docs/getting-started.md` — 環境構築・バックエンド選択・ビルド手順
- `docs/dsl-and-layout.md` — ネスト DSL・全コンテナ・2パスレイアウト・`Anchor` 絶対配置
- `docs/widgets-and-events.md` — 全 21 ウィジェット・`Signal`・`connect`・`Canvas`/`Painter`・Win32 連携・ヘッドレステスト
- `docs/architecture.md` — `root struct App`・`str_pool`・デュアルバックエンド・ベンチマーク詳細
