# Widgets, Events & Native API — ウィジェット・イベント・Win32 連携リファレンス

---

## 1. ウィジェット一覧（全 21 種）

### コンテナ・構造系
`Panel`, `Frame`, `GroupBox`, `Spacer`, `Separator`, `TabWidget`, `ScrollArea`, `Splitter`, `StatusBar`

### リーフウィジェット（DSL ビルダー）

| DSL メソッド | 説明・主な機能 |
| --- | --- |
| `u.label(text, role = FontRole.Body)` | 単一行テキスト表示（`.heading()`, `.subheading()`, `.bold()`, `.caption()`, `.mono()`, `.center()`） |
| `u.button(text, variant = Default)` | クリック可能ボタン（`.primary()`, `.secondary()`, `.danger()`, `.ghost()`, `.checkable()`） |
| `u.checkbox(text, checked = false)` | チェックボックス（`Toggled` / `Clicked` 発火） |
| `u.radio(text, checked = false)` | 同一親内で自動的に排他選択されるラジオボタン |
| `u.toggle(text, checked = false)` | トグルスイッチ（`Toggled` 発火） |
| `u.line_edit(placeholder = "", initial_text = "")` | UTF-8・日本語・絵文字（サロゲートペア）対応テキスト入力、範囲選択、Home/End/矢印、`Ctrl+A/C/X/V`（Windows クリップボード連携）、`.password()`, `.read_only()` |
| `u.slider(min, max, initial, step, orientation)` | 水平 / 垂直スライダー（ドラッグ・ホイール・矢印キー対応） |
| `u.spin_box(min, max, initial, step, decimals)` | `+/-` ボタン・ホイール・矢印キー対応数値入力 |
| `u.progress_bar(min, max, initial)` | 進捗バー（パーセント表示は `app.set_show_percentage` で切替可） |
| `u.combo_box()` | ドロップダウン選択（最前面オーバーレイ描画、Esc で閉じる、`.item(text)` で項目追加） |
| `u.list_view(item_height = 30.0)` | 仮想化スクロール対応リスト（主テキスト＋サブテキスト＋`item_tag`、矢印キー・ダブルクリック対応） |
| `u.canvas(min_w = 200.0, min_h = 160.0)` | カスタム 2D 描画サーフェス（マウス・ホイールイベント付き） |

### ステータスバー

トップレベルウィンドウの下端にドッキングされます：

```goose
app.set_status_bar(win, "準備完了");
// 任意のタイミングで更新（インプレース文字列再利用）
app.set_status_text(win, "保存しました");
```

### 主な `Node` 修飾子（UFCS チェーン）

- **識別・参照**: `.action(id)`, `.name("...")`, `.bind(var_id)`, `.widget()`
- **レイアウト**: `.stretch(s)`, `.fixed(w, h)`, `.width(w)`, `.height(h)`, `.min_size(w, h)`, `.max_size(w, h)`, `.policy(h, v)`, `.align(h, v)`, `.padding(all)`, `.spacing(sp)`, `.bounds(x, y, w, h, anchor, ref_w, ref_h)`
- **文字・配置**: `.heading()`, `.subheading()`, `.bold()`, `.caption()`, `.mono()`, `.center()`, `.text_align(h, v)`
- **外観**: `.primary()`, `.secondary()`, `.danger()`, `.ghost()`, `.checkable()`, `.bg(c)`, `.fg(c)`, `.border(c, w)`, `.radius(r)`
- **状態・入力**: `.tooltip("...")`, `.placeholder("...")`, `.password()`, `.read_only()`, `.enabled(bool)`, `.visible(bool)`
- **項目操作**: `.item(text, subtext = "", tag = 0)`, `.select(idx)`
- **宣言的接続**: `.connect(sig, receiver, slot, param)`, `.on_toggle_theme()`, `.on_click_close()`

---

## 2. イベントループと `Signal`

### イベントループの起動

- 通常アプリ: `app.exec() { sig => ... };`
- カスタム `Canvas` あり: `app.exec_with_canvas(paint_fn) { sig => ... };`

`win32::wait_event` によるブロッキング待機のため、**操作していない間の CPU 使用率は 0%** です。ウィンドウの `dirty` フラグが立ったときだけ再描画します。

### 全 `Signal` バリアント

| Signal | 発生タイミング | 主なフィールド |
| --- | --- | --- |
| `Clicked` | Button / CheckBox / Radio / Toggle の押下確定 | `widget`, `window` |
| `DoubleClicked` | ウィジェットのダブルクリック | `widget`, `window` |
| `Toggled` | チェック状態の変化 | `widget`, `window`, `checked` |
| `ValueChanged` | Slider / SpinBox の値変更 | `widget`, `window`, `value` |
| `TextChanged` | LineEdit の文字列変更 | `widget`, `window` |
| `TextSubmitted` | LineEdit で Enter キー押下 | `widget`, `window` |
| `SelectionChanged` | ComboBox / ListView の選択変更 | `widget`, `window`, `index` |
| `ItemActivated` | ListView のダブルクリック / Enter | `widget`, `window`, `index` |
| `TabChanged` | TabWidget のタブ切替 | `widget`, `window`, `index` |
| `FocusChanged` | フォーカス移動 | `widget`, `window`, `focused` |
| `ActionTriggered` | ネイティブ MenuBar / ContextMenu の選択（`WM_COMMAND`） | `window`, `action_id` |
| `TimerFired` | `start_timer` で登録したタイマー発火 | `window`, `timer_id` |
| `KeyPressed` | キー押下（`KMOD_SHIFT`, `KMOD_CTRL`, `KMOD_ALT`） | `window`, `widget`, `key`, `mods` |
| `CanvasMouseDown` / `Move` / `Up` / `Wheel` | Canvas 上のローカル座標入力 | `widget`, `window`, `x`, `y`, (`button` / `delta`) |
| `FilesDropped` | ウィンドウへのファイル D&D（要 `app.enable_drop_files(win)`） | `window`, `count` |
| `WindowResized` / `WindowClosed` | リサイズ・クローズ通知 | `window`, (`width`, `height`) |

### Win32 風アクション ID ディスパッチ

大量の `WidgetId` 変数を宣言せず、整数 ID で見通しよく処理できます：

```goose
let ID_SAVE = 101;
let ID_NAME = 201;

app.exec() { sig =>
    match sig {
        Clicked s => match app.action_id(s.widget) {
            ID_SAVE => {
                let name = app.text_of(win, ID_NAME);
                app.set_status_text(win, str("Saved: ", name));
            },
            _ => {},
        },
        _ => {},
    }
};
```

ヘルパー一覧:
`app.action_id(widget)`, `app.by_id(win, id)`, `app.text_of(win, id)`, `app.set_text_of(win, id, s)`, `app.value_of(win, id)`, `app.set_value_of(win, id, v)`, `app.checked_of(win, id)`, `app.set_checked_of(win, id, b)`

---

## 3. 宣言的 Signal → Slot 接続 (`connect`)

スライダーとプログレスバーの同期やテーマ切替など、定型的な連動はイベントループに書かず `connect` で完結させられます。

```goose
app.connect(slider_id, goose_ui::SignalKind.OnValueChange, progress_id, goose_ui::SlotAction.SetValue);
app.connect(slider_id, goose_ui::SignalKind.OnValueChange, value_lbl, goose_ui::SlotAction.SetValueLabel);
```

- **`SignalKind`**: `OnClick`, `OnToggle`, `OnValueChange`, `OnTextChange`, `OnTextSubmit`, `OnSelectionChange`, `OnTabChange`
- **`SlotAction`**: `SetVisible`, `SetVisibleInverted`, `SetEnabled`, `SetEnabledInverted`, `SetChecked`, `ToggleChecked`, `SetValue`, `SetValueLabel`, `SyncText`, `SetCurrentTab`, `ClearText`, `IncrementValue`, `CloseWindow`, `ToggleTheme`

---

## 4. カスタム描画 (`Canvas` ＋ `Painter`)

`Canvas` ウィジェットでは、ローカル座標 `(0, 0) .. (p.width, p.height)` で描画コールバックを受け取ります。`Software` GDI と `Direct2D` のどちらでも同じコードで動作します。

```goose
fn paint_canvas(cid: goose_ui::WidgetId, p: const goose_ui::Painter&) {
    p.fill_rounded_rect(0.0, 0.0, p.width, p.height, 8.0, p.theme.input_bg);
    p.fill_ellipse(p.width * 0.5, p.height * 0.5, 48.0, 48.0, p.theme.accent);
    p.draw_text("Canvas", 0.0, 0.0, p.width, p.height, p.theme.accent_text,
                goose_ui::FontRole.BodyBold, goose_ui::Align.Center, goose_ui::Align.Center);
}

// 起動時:
app.exec_with_canvas(paint_canvas) { sig =>
    // CanvasMouseDown / TimerFired などで状態更新し、app.mark_dirty(win) を呼ぶ
};
```

`Painter` 描画メソッド一覧:
`fill_rect`, `draw_rect`, `fill_rounded_rect`, `draw_rounded_rect`, `fill_ellipse`, `draw_ellipse`, `draw_line`, `draw_text`

---

## 5. ネイティブ Windows 連携 (`native.goose`)

- **メニューバー & コンテキストメニュー**:
  - `create_menu_bar(app, win)` / `create_popup_menu()` / `add_submenu(parent, title)`
  - `add_action(menu, action_id, text, enabled, checked)` / `add_menu_separator(menu)`
  - `set_action_enabled` / `set_action_checked` / `refresh_menu_bar` / `show_context_menu` / `destroy_menu`
- **メッセージボックス**: `msg_info`, `msg_warning`, `msg_error`, `msg_question -> bool`
- **コモンダイアログ**:
  - `open_file_dialog(app, win, out_path, title, filter, default_ext)`
  - `save_file_dialog(app, win, out_path, title, filter, default_ext, initial_name)`
  - `select_folder_dialog(app, win, out_path, title)`
  - `choose_color_dialog(app, win, color_ref)`
  - `input_dialog(app, win, out_text, title, prompt, initial_text)`
- **クリップボード**: `clipboard_text() -> u8[>..]`, `set_clipboard_text(text)`
- **タイマー (`QTimer`)**: `start_timer(app, win, interval_ms, single_shot = false) -> u64`, `stop_timer(app, timer_id)`
- **ドラッグ＆ドロップ**: `app.enable_drop_files(win, true)` → `FilesDropped` シグナル内で `dropped_file_count()` / `dropped_file_path(i)`

---

## 6. テーマとスタイリング

- 組み込みテーマ: `theme_dark()`, `theme_light()`
- 実行時切替: `app.set_theme(custom_theme)` / `app.toggle_theme()`（Windows 11 の DWM ダークタイトルバーも自動連動）
- 色ユーティリティ: `rgb(r, g, b)`, `rgba(r, g, b, a)`, `color_hex(0x3B82F6, a = 1.0)`, `with_alpha(c, a)`, `lerp_color(a, b, t)`

---

## 7. ヘッドレス自動テスト

OS ウィンドウや GPU を生成せず、レイアウト・クリック・キー入力・シグナルを高速に単体テストできます（実例: [`test/goose_ui_test.goose`](../test/goose_ui_test.goose)）。

```goose
let win = app.create_headless_window("Test", 600, 400);
// UI 構築...
app.update_layout(win);

let r = app.widget_rect(btn);
app.inject_click(win, r.x + r.w * 0.5, r.y + r.h * 0.5);

var sig = goose_ui::Signal.None;
while app.next_signal(sig) {
    // Signal を検証
}
```

利用可能な注入関数:
`inject_mouse_move`, `inject_click`, `inject_mouse_down`, `inject_mouse_up`, `inject_mouse_wheel`, `inject_key`, `inject_char`, `inject_text`
