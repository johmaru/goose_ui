# Getting Started — goose_ui 入門ガイド

`goose_ui` は、Goose 言語（v2026.4+）向けの純 Goose 製・ゼロヒープ GUI フレームワークです。[`win32-goose`](https://github.com/johmaru/win32-goose) サブモジュール上で動作し、**Software GDI + ClearType** と **Direct2D + DirectWrite (GPU)** の 2 つの描画バックエンドを切り替えられます。

---

## 1. 動作要件

- **OS**: Windows 10 / 11 (x64)
- **Goose コンパイラ**: v2026.4 以降（`goose` コマンドが PATH にあること）
- **Clang (任意・ネイティブビルド時)**: `goose build` で単体 `.exe` を生成する場合に必要（`goose run` は内蔵 TinyCC JIT で即座に実行可能）

---

## 2. リポジトリ取得と動作確認

`win32-goose` は git サブモジュールとして組み込まれています。

```powershell
git clone --recursive <repo-url>
# すでに clone 済みの場合:
git submodule update --init --recursive
```

まずはテストと 3 つのサンプルを実行して動作を確認します。

```powershell
# 自動テスト（デバッグチェック付き JIT 実行）
goose run --debug test/goose_ui_test.goose

# サンプルアプリ実行
goose run examples/counter.goose       # Software GDI: カウンター
goose run examples/todo_app.goose      # Software GDI: Todo 管理 + メニューバー
goose run examples/kitchen_sink.goose  # Direct2D GPU: 全ウィジェット + Canvas アニメーション
```

---

## 3. 新しいアプリの作成方法

### import の書き方

Goose のパッケージ依存解決仕様により、外部のルートファイル（自分のアプリの `main.goose` 等）からは、**`win32-goose` と `goose_ui` の両方を import** します。

```goose
import std;
import win32 from "./path/to/goose_ui/win32-goose";
import goose_ui from "./path/to/goose_ui";
```

リポジトリ内の `examples/` や `test/` からは相対パスで以下のように書きます：

```goose
import std;
import win32 from "../win32-goose";
import goose_ui from "..";
```

### アプリの基本ライフサイクル

```goose
fn main() {
    // 1. 全 GUI 状態を保持する root struct App を作成（ヒープ確保なし）
    var app = goose_ui::App { .. };

    // 2. 初期化: (dark_theme, backend)
    app.init(true, goose_ui::RenderBackend.Software);

    // 3. トップレベルウィンドウを作成
    let win = app.create_window("My App", 640, 420);

    // 4. スコープ付き DSL で UI ツリーを構築
    app.ui(win) { u =>
        u.padding(16.0).spacing(10.0);
        u.label("こんにちは goose_ui!").heading();
        u.button("閉じる").primary().on_click_close();
    };

    // 5. ウィンドウを表示してイベントループ開始（アイドル時 CPU 0%）
    app.show_window(win);
    app.exec() { sig =>
        match sig {
            _ => {},
        }
    };
}
```

---

## 4. 描画バックエンドの選び方

`goose_ui` は同じウィジェットコードのまま、2 種類の描画バックエンドを選択できます。

| バックエンド | 指定方法 | メモリ (Private) | 初回描画 | 向いている用途 |
| --- | --- | --- | --- | --- |
| **`RenderBackend.Software`** | `app.init(true, goose_ui::RenderBackend.Software)` | **~9.2–11.3 MB** | **~36 ms** | 常駐ツール、設定ダイアログ、エディタ、管理画面、起動速度・省メモリ重視 |
| **`RenderBackend.Direct2D`** | `app.init(true, goose_ui::RenderBackend.Direct2D)`（既定） | ~65–68 MB（※GPU ドライバ分） | ~200 ms | アンチエイリアス曲線、半透明合成、アニメーション付き `Canvas` 描画重視 |

ウィンドウ単位でバックエンドを変えることも可能です：

```goose
let win = app.create_window_with_backend(
    "GPU Canvas", 900, 600, true, goose_ui::RenderBackend.Direct2D
);
```

---

## 5. ネイティブ単体 `.exe` のビルド

`goose build` を使うと、外部 DLL 依存ゼロの単体 Windows 実行ファイル（約 386 KB）を出力できます。

```powershell
# 型チェック（エラー0・警告0を確認）
goose check examples/counter.goose

# Clang -O2 で単体実行ファイルをビルド
goose build examples/counter.goose
.\examples\counter.exe
```

---

## 次のステップ

- [UI DSL & Layout Guide](dsl-and-layout.md) — ネスト DSL・全レイアウトコンテナ・`Anchor` 絶対配置
- [Widgets, Events & Native API](widgets-and-events.md) — 全 21 ウィジェット・イベント処理・ダイアログ・`Canvas`
- [Architecture & Performance](architecture.md) — ゼロヒープ設計と Qt 6 比較ベンチマーク
