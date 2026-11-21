# UI DSL & Layout Guide — UI 記述とレイアウト設計

`goose_ui` は、**SwiftUI / Jetpack Compose 風のスコープ付きネスト DSL**、**Win32 風の整数アクション ID**、そして **WinForms / Win32 風の `Anchor` 付き絶対配置** をシームレスに組み合わせられる「いいとこ取り」構成を採用しています（実装: [`dsl.goose`](../dsl.goose) / [`layout.goose`](../layout.goose)）。

---

## 1. スコープ付きネスト DSL の基本

`app.ui(win) { u => ... }` を使うと、ウィンドウのルートコンテナに対して親子構造をインデントそのままに記述できます。

- `Ui { app: App&, parent: WidgetId }`（16 バイト値型）: 現在のコンテナカーソル
- `Node { app: App&, id: WidgetId }`（16 バイト値型）: 生成直後のウィジェットに対するメソッドチェーンハンドル

どちらもコンパイル時にレジスタへ最適化され、追加メモリ確保は 0 バイトです。

```goose
let ID_INPUT = 100;
let ID_ADD   = 101;
let ID_LIST  = 102;

app.ui(win) { u =>
    u.padding(16.0).spacing(10.0);

    u.hbox(8.0) { row =>
        row.line_edit("タスクを入力...").stretch(1.0).action(ID_INPUT);
        row.button("追加").primary().action(ID_ADD);
    };

    u.list_view(34.0).stretch(1.0).action(ID_LIST);
};
```

既存のコンテナ `WidgetId` の中身を動的に追加したい場合は `app.ui_in(container) { u => ... }` を使います。

### 作成したウィジェットの ID を受け取る方法

用途に応じて 3 通りの参照方法を使い分けられます：

1. **Win32 風アクション ID（推奨）**: `.action(ID_*)` を付け、イベント側で `app.action_id(s.widget)` や `app.by_id(win, ID_*)` / `app.text_of(win, ID_*)` / `app.set_text_of(win, ID_*, ...)` を使う
2. **変数バインド**: `var my_btn = goose_ui::WIDGET_NONE;` に対して `.bind(my_btn)` をチェーンする（または `.widget()` で `WidgetId` を受け取る）
3. **名前検索**: `.name("submit_btn")` を付けて `app.find_by_name(win, "submit_btn")` で引く

---

## 2. コンテナ一覧（DSL メソッド）

すべてのコンテナはトレイリングブロックを受け取り、自身の `Node` を返すため、ブロック末尾に `.stretch(1.0)` や `.fixed(w, h)` 等をチェーンできます。

| DSL メソッド | 説明 | 主なデフォルト引数 |
| --- | --- | --- |
| `u.vbox(spacing, padding) { v => ... }` | 縦積みボックスレイアウト（`LayoutKind.VBox`） | `spacing = 8.0, padding = 0.0` |
| `u.hbox(spacing, padding) { h => ... }` | 横並びボックスレイアウト（`LayoutKind.HBox`） | `spacing = 8.0, padding = 0.0` |
| `u.grid(columns, spacing, padding) { g => ... }` | 等幅 N 列グリッド（`LayoutKind.Grid`） | `columns = 2, spacing = 8.0, padding = 0.0` |
| `u.form(label_width, spacing, padding) { f => ... }` | ラベル＋入力欄の 2 列フォーム（`LayoutKind.Form`、子を 2 個ずつペア配置） | `label_width = 130.0, spacing = 10.0, padding = 0.0` |
| `u.stack(padding) { s => ... }` | ページ切替コンテナ（`LayoutKind.Stack`、`selected_index` の子のみ表示） | `padding = 0.0` |
| `u.frame(layout, spacing, padding) { f => ... }` | 背景色＋枠線付きのカード/パネル | `layout = VBox, spacing = 8.0, padding = 12.0` |
| `u.group_box(title, layout, spacing, padding) { g => ... }` | 見出しタイトル付きグループ枠 | `layout = VBox, spacing = 8.0, padding = 12.0` |
| `u.scroll_area(spacing, padding) { sc => ... }` | 縦スクロール可能なパネル（マウスホイール＋スクロールバー対応） | `spacing = 8.0, padding = 10.0` |
| `u.splitter(orientation, ratio) { sp => ... }` | 2 ペインをドラッグで比率変更できるスプリッタ | `orientation = Horizontal, ratio = 0.35` |
| `u.tabs() { t => t.tab("名前") { p => ... }; }` | タブ切り替えコンテナ（`TabWidget` ＋ 各ページ `Panel`） | `layout = VBox, spacing = 10.0, padding = 12.0` |
| `u.anchored_panel(padding) { a => ... }` | Win32 / WinForms 風の絶対座標＋`Anchor` 追従パネル（`LayoutKind.None`） | `padding = 0.0` |

### コンテナ自身の設定（`Ui` メソッド）

ブロック先頭で現在のコンテナ自身を設定できます：

```goose
u.padding(16.0).spacing(10.0).bg(goose_ui::color_hex(0x1E222F)).radius(8.0);
```

利用可能な `Ui` メソッド:
`padding`, `padding_m`, `spacing`, `stretch`, `fixed`, `width`, `height`, `min_size`, `bg`, `border`, `radius`, `action`, `name`, `bind`, `layout_kind`, `self_node`, `id`

---

## 3. 2パスレイアウトの仕組み

`goose_ui` のレイアウトエンジン（`update_layout(win)`）は Qt と同様の 2 パス方式です。

1. **計測パス (`measure_widget`)**: ボトムアップに各ウィジェットの自然サイズ（`size_hint`）を算出します（テキスト幅、`padding`、`spacing`、`min_size`/`max_size`/`fixed_w`/`fixed_h` を反映）。
2. **配置パス (`layout_widget`)**: トップダウンに親の矩形から子へ領域を配分します。

### 伸縮・サイズ制御修飾子

| 修飾子 | 役割 |
| --- | --- |
| `.stretch(weight)` | `VBox`/`HBox` の余剰スペースを比率配分（例: `stretch(1.0)` と `stretch(2.0)` で 1:2） |
| `.fixed(w, h)` / `.width(w)` / `.height(h)` | 固定サイズ指定（`SizePolicy.Fixed` に設定） |
| `.min_size(w, h)` / `.max_size(w, h)` | 最小・最大サイズ制約 |
| `.policy(h, v)` | `SizePolicy`（`Fixed`, `Minimum`, `Preferred`, `Expanding`）を明示指定 |
| `.align(h, v)` | 親セル内の配置（`Align.Start`, `Center`, `End`, `Stretch`） |
| `u.spacer(stretch)` | 伸縮する空白スペーサー（ボタンを右寄せしたいとき等に便利） |
| `u.separator(orientation)` | 水平 / 垂直の区切り線 |

```goose
// ボタンを右寄せする定型パターン
u.hbox(8.0) { bar =>
    bar.spacer(1.0);
    bar.button("キャンセル").secondary();
    bar.button("保存").primary();
};
```

---

## 4. Win32 / WinForms 風 絶対配置 ＋ `Anchor` モード

設定ダイアログやインスペクタなど「ピクセル単位で厳密に座標を決めたい」場面では、`u.anchored_panel()` の中で `.bounds(x, y, w, h, anchor)` を使います。

```goose
u.anchored_panel() { dlg =>
    // 左上固定のラベル
    dlg.label("接続先ホスト:").bounds(16.0, 20.0, 100.0, 28.0, goose_ui::ANCHOR_TOP_LEFT);

    // 横幅いっぱいに伸縮する入力欄（左右マージンを維持）
    dlg.line_edit("localhost:8080")
       .bounds(124.0, 18.0, 240.0, 32.0, goose_ui::ANCHOR_H_STRETCH)
       .action(ID_HOST);

    // ウィンドウ右下に追従する OK ボタン
    dlg.button("OK").primary()
       .bounds(276.0, 140.0, 88.0, 32.0, goose_ui::ANCHOR_BOTTOM_RIGHT)
       .action(ID_OK);
}.stretch(1.0);
```

### `ANCHOR_*` 定数一覧

| 定数 | ビット構成 | リサイズ時の挙動 |
| --- | --- | --- |
| `ANCHOR_TOP_LEFT`（既定） | `LEFT \| TOP` | 左上からの距離固定 |
| `ANCHOR_TOP_RIGHT` | `TOP \| RIGHT` | 右上からの距離固定 |
| `ANCHOR_BOTTOM_LEFT` | `LEFT \| BOTTOM` | 左下からの距離固定 |
| `ANCHOR_BOTTOM_RIGHT` | `RIGHT \| BOTTOM` | 右下からの距離固定 |
| `ANCHOR_H_STRETCH` | `LEFT \| TOP \| RIGHT` | 上固定、横幅が親に追従して伸縮 |
| `ANCHOR_V_STRETCH` | `LEFT \| TOP \| BOTTOM` | 左固定、高さが親に追従して伸縮 |
| `ANCHOR_ALL` | `LEFT \| TOP \| RIGHT \| BOTTOM` | 上下左右マージンを維持して全方向伸縮 |

> **基準サイズ (`ref_w`, `ref_h`)**: `.bounds(x, y, w, h, anchor)` で `ref_w` / `ref_h` を省略（`0.0`）すると、作成時のウィンドウサイズが基準設計サイズとして記録されます。ネストされたパネル内で設計基準を明示したい場合は `.bounds(x, y, w, h, anchor, 400.0, 220.0)` のように渡します。

---

## 5. 低レベル Qt 風 API との併用

DSL はすべて [`tree.goose`](../tree.goose) の `add_*` / `set_*` 関数への薄いゼロコスト変換です。動的にノードを生成・破棄する場合や、従来の Qt 風記述を使いたい場合は低レベル API を直接呼べます。

```goose
let root = app.root(win);
let row = app.add_hbox(root, 8.0, 0.0);
let btn = app.add_button(row, "Click", goose_ui::ButtonVariant.Primary);
app.set_stretch(btn, 1.0);

// 動的削除（子孫・ListItem・Connection も再帰的に自動クリーンアップ）
app.destroy_widget(row);
```
