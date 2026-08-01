# okuribon

読書交換会ツール。参加者が本を持ち寄り、希望順にもとづくマッチングで交換する。

仕様は `docs/spec.md` にある。開発の規約は `CLAUDE.md` を見ること。

## 開発環境

VS Code の Dev Containers で開く。`.devcontainer/post-create.sh` が
bundle install と開発ツールの導入まで済ませる。

```
bin/rails db:prepare
bin/dev
```

`bin/dev` は Rails サーバーと Tailwind の watch を同時に動かす（`Procfile.dev`）。
http://localhost:3000 で開く。

OAuth のクライアント ID と秘密鍵は credentials に置く。未設定でもログイン画面までは開ける。

```
bin/rails credentials:edit
```

## 検証

```
bin/rspec    # RSpec
bin/rubocop  # スタイル（-a で自動修正）
bin/ci       # rubocop、bundler-audit、importmap audit、brakeman
```

`bin/ci` にテストは含まれない。`bin/rspec` は別に走らせる。

## ブラウザで画面を確認する

コンテナはヘッドレスなので、レンダリング結果は Playwright MCP 経由で見る。
`.mcp.json` に `playwright` として登録してあり、ページを開く・スクリーンショットを撮る・
幅を変えるといった操作ができる。

実体は `.devcontainer/package.json` に固定した `@playwright/mcp`。
chromium はこのパッケージが抱える playwright-core と同じリビジョンでなければ
「Executable doesn't exist」で落ちるため、`post-create.sh` は必ず
`.devcontainer/node_modules` 側の CLI で入れる。手で入れ直すときも同じにする。

```
npm --prefix .devcontainer ci
.devcontainer/node_modules/.bin/playwright install --with-deps chromium
```

MCP には `--browser=chromium` を渡している。既定は branded Chrome を探しに行き、
コンテナには入っていないため起動に失敗する。

出力は `.playwright-mcp/` に落ちる。追跡しない。

## デザイン

配色と書体は Claude Design の「本の交換会ツールビジュアルガイド」の
DIRECTION 2a「見通しを紙の色で」に従う。トークンは
`app/assets/tailwind/application.css` の `@theme` にあり、ビューからは
`bg-surface` `text-ink` `border-line` のような Tailwind のクラスで参照する。

色には意味の担当を1つずつ持たせる。朱（`accent`）は押すものと締切、
松葉（`success`）は成立と完了、それ以外は生成りの濃淡で階層を作る。影は使わない。
