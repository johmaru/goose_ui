# Architecture & Performance — 内部設計と性能特性

`goose_ui` は、Goose 言語の **ゼロヒープ・データスタックモデル** を最大限に活かし、デスクトップ GUI フレームワークでありながら極小フットプリント・高レスポンスを実現しています。

---

## 1. ゼロヒープ `root struct App` と世代付きハンドル

従来の C++ GUI フレームワーク（Qt の `QObject` 等）はウィジェットごとに個別 `new` / `delete` や仮想関数テーブル・シグナルメタオブジェクトをヒープ上に確保しますが、`goose_ui` はすべてのデータを単一の `root struct App` 内の連続配列（独立データスタック）に集約しています（[`widget.goose`](../widget.goose)）。

```
root struct App
 ├── windows:     Window[>..]      // ウィンドウ状態・HWND/D2D/GDIフォント
 ├── widgets:     Widget[>..]      // 全ウィジェットのフラット配列
 ├── free_widgets:i64[>..]         // 破棄スロット再利用リスト
 ├── str_pool:    u8[>..]          // 共有文字列プール（StrSpan で参照）
 ├── list_items:  ListItem[>..]    // ListView / ComboBox / TabWidget の項目
 ├── connections: Connection[>..]  // 宣言的 Signal -> Slot 接続テーブル
 ├── timers:      TimerInfo[>..]   // アクティブタイマー一覧
 ├── signals:     Signal[>..]      // 1 フレームのシグナルキュー
 └── focus_order: WidgetId[>..]    // Tab 移動順キャッシュ
```

### 世代付きハンドル (`WindowId`, `WidgetId`)

ポインタの代わりに `{ index: i32, gen: u32 }` の 8 バイト値ハンドルを使用します。

- `destroy_widget(id)` でウィジェットを破棄するとスロットは `free_widgets` に返却され、再利用時に `gen` がインクリメントされます。
- 破棄済みの古い `WidgetId` を渡しても `valid_widget` が `false` を返すため、ダングリングポインタ（Use-After-Free）が構造上起きません。

---

## 2. メモリ最適化のポイント

### 共有文字列プール (`App.str_pool` ＋ 12 バイト `StrSpan`)

各 `Widget` が固定長バッファ（例: `u8[..256]` × 4 フィールド = ~1 KB）を持つと、ラベルやパネルを数千個並べた際にほぼ空のバイト列がメモリを圧迫します。

`goose_ui` では、`text`, `placeholder`, `tooltip`, `name`, `subtext` をすべて 12 バイトの `StrSpan { off, len, cap }` で表現し、実データだけを `App.str_pool` に詰めます。

- **インプレース再利用**: `str_set` は新しい文字列長 `n <= s.cap` であれば既存の領域を上書きするため、カウンター表示やステータスバー更新のような頻繁なテキスト書き換えでも **追加領域を 0 バイト** に抑えます。
- **実測効果**: 5,000 個のコントロール（総計 6,003 ノード）の文字列プール合計はわずか **31.8 KB** です。

### パック済み `WidgetStyle`（24 バイト）

ウィジェット個別の色上書き（`bg`, `fg`, `border`）は 16 バイトの `Color { f32 × 4 }` をそのまま持たず、`u32` パック RGBA（4 バイト）＋ `flags: u8` ビットマスクで圧縮しています。

結果として、1 ウィジェットあたりの実測増分メモリは **約 350 バイト**（Qt 6 Widgets の約 1/8.5）に収まっています。

---

## 3. デュアル描画バックエンドの設計

| 観点 | `RenderBackend.Software` | `RenderBackend.Direct2D` |
| --- | --- | --- |
| 描画 API | Win32 ダブルバッファ GDI (`begin_paint` / `end_paint`) + ClearType `CreateFontA` | Direct2D (`ID2D1HwndRenderTarget`) + DirectWrite |
| 初期化コスト | **d2d1 / d3d11 DLL を一切ロードしない**（GPU ドライバ常駐メモリ ~56 MB を回避） | GPU コンテキスト＋スワップチェーン初期化あり |
| フォント管理 | ウィンドウあたり 6 本の `HFONT`（`GdiFontSet`） | `win32-goose` の `W32_MAX_D2D_FONTS = 64` 制約に合わせて 6 本（`FontSet`）＋動的 `set_align` |
| `Canvas` 座標系 | `Painter.ox / oy` ソフトウェア平行移動 | `d2d.set_transform` による GPU 平行移動 |
| 半透明色 | テーマ背景色 `surface_bg` への事前アルファブレンド (`gdi_colorref`) | ハードウェアアルファブレンディング |

---

## 4. ベンチマーク手法と詳細結果

### 測定条件

- **環境**: Windows 11 x64 / NVIDIA GeForce RTX 5070 Ti
- **ビルド**: Goose v2026.4 + Clang `-O2` / Qt 6.11.1 MinGW `g++ -O2` / Python 3.14 Tkinter
- **シナリオ**: `ScrollArea` 内に `N` 個の混合コントロール（`Label`, `LineEdit`, `CheckBox`, `ProgressBar`, `Button`）を生成・レイアウト・初回描画した直後に、各独立プロセス内で `K32GetProcessMemoryInfo`（`PROCESS_MEMORY_COUNTERS_EX`）の `PrivateUsage`（Private Bytes）と `WorkingSetSize`（Working Set）を計測。
- **再現コマンド**: `pwsh -File bench/run_bench.ps1`（ソースは [`bench/`](../bench) 配下）

### Private Bytes (MB)

| フレームワーク | バックエンド | 0 個 | 100 個 | 1,000 個 | 5,000 個 | 1個あたり増分 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| **`goose_ui` (Software)** | GDI + ClearType (CPU) | **9.17** | 10.38 | **10.34** | **11.25** | **~350 B** |
| **`goose_ui` (Headless)** | Pure Data Stack | 8.09 | 9.15 | 9.12 | 10.30 | ~370 B |
| **Qt 6.11.1 Widgets** | C++ Raster (CPU) | 10.05 | 9.79 | 14.11 | 27.84 | ~2,965 B (8.5×) |
| **`goose_ui` (Direct2D)** | Direct2D + DirectWrite (GPU) | **65.05** | **66.76** | **66.18** | **67.57** | **~420 B** |
| **Qt 6.11.1 Quick / QML** | Direct3D 11 RHI (GPU) | 88.37 | 104.19 | 180.85 | — | ~77 KB (~220×) |
| **Python 3.14 Tkinter** | Tcl/Tk (CPU) | 14.40 | 16.58 | 21.52 | — | ~5.9 KB (17×) |

### Working Set (MB)・初回描画時間・配布サイズ

| フレームワーク | 0個 WS | 1,000個 WS | 5,000個 WS | 1,000個 時間 | 5,000個 時間 | 配布サイズ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **`goose_ui` (Software)** | **21.97** | **22.30** | **24.02** | **32.7 ms** | **35.8 ms** | **386 KB**（単体 `.exe`） |
| **`goose_ui` (Direct2D)** | 55.18 | 56.59 | 58.08 | 216.3 ms | 197.6 ms | **386 KB**（単体 `.exe`） |
| **Qt 6.11.1 Widgets** | 42.29 | 48.13 | 63.86 | 317.9 ms | 380.9 ms | 32.3 MB（`.exe` + Qt/MinGW DLL） |
| **Qt 6.11.1 Quick / QML** | 92.74 | 177.52 | — | 673.0 ms | — | > 40 MB（Qt/QML/Controls DLL） |
| **Python 3.14 Tkinter** | 31.81 | 51.31 | — | 1,435.7 ms | — | Python + Tcl/Tk ランタイム |

### モジュール依存関係

```
goose_ui.goose (公開エントリ)
 ├── types.goose    (基本型・ハンドル・列挙・Signal・ANCHOR_*)
 ├── theme.goose    (Theme・WidgetStyle・UTF-8 メトリクス)
 ├── widget.goose   (Widget・Window・root struct App)
 ├── tree.goose     (ライフサイクル・str_pool・フォント・add_*/set_*・connect)
 ├── layout.goose   (2パスレイアウトエンジン・Anchor 絶対配置)
 ├── painter.goose  (Software GDI / Direct2D デュアル描画・各ウィジェット描画)
 ├── events.goose   (ヒットテスト・フォーカス・編集・イベントループ・inject_*)
 ├── native.goose   (Win32 メニュー・ダイアログ・クリップボード・タイマー・D&D)
 └── dsl.goose      (スコープ付きネスト DSL: Ui / Node)
```
