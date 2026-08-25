# 0021 ステージングを独立した RAILS_ENV にする

- 日付：2026-08-24
- 発端：#45

## 決めたこと

- ステージングは `RAILS_ENV=staging` として独立させる
- credentials と鍵を3つに分ける。development・test は `config/credentials.yml.enc`、
  本番とステージングは `config/credentials/<環境>.yml.enc`
- `config/environments/staging.rb` は `production` を require して設定を揃える。
  環境ごとに変えたいものが出たら、そのあとに差分だけを足す
- デプロイした環境かどうかは `Rails.env.local?` の否定で見る。`production?` では見ない
- SSL の終端（`assume_ssl` / `force_ssl`）と `config/deploy.yml` の destination は
  この判断に含めない。Kamal のプロキシの設定と一体なので #46 で扱う

## なぜ

Epic #56 は「ステージングのホストに本番の鍵を置かない」を完了の定義に挙げている。
Rails は credentials を `config/credentials/#{Rails.env}.yml.enc` で引き、
無ければ `config/credentials.yml.enc` へ落ちる（railties の
`rails/application/configuration.rb`）。鍵を環境ごとに分ける道は `RAILS_ENV` を
分けることしか無い。

分ける値のうち最も重いのは Active Record Encryption の `primary_key` で、
これを失うと登録済みのギフトコードは二度と復号できない。逆に、鍵が分かれていれば
片方が漏れてももう片方のギフトコードは読めないままになる。

issue が挙げていた「production と二重に直す箇所ができる」という代償は、
`require_relative 'production'` でほぼ消える。増えるのは
`config/database.yml` などの節だけで、こちらは節の欠落を spec で弾ける。

## 却下した代替案

- **destination だけ分け、両方を production で動かす** — 設定ファイルは増えないが、
  `RAILS_MASTER_KEY` が同一になり、本番の鍵をステージングのホストへ配ることになる。
  ステージングは壊れ方を先に踏むための場所なので、そこへ本番の鍵を置くのは順序が逆になる
- **production のまま、秘密をすべて環境変数で渡す** — 鍵は環境ごとに分かれる。
  ただし何を設定すべきかがリポジトリから消え、文書だけが頼りになる。設定の漏れは
  起動しても分からず、ログインを試して初めて出る。`config/initializers/omniauth.rb` の
  読み先も credentials から環境変数へ変えることになり、development と test だけが
  別の経路で読む形が残る
- **`staging.rb` に production の内容を書き写す** — issue が代償として挙げていた
  「二重に直す箇所」がそのまま残る。片方だけ直したことは、ステージングで
  再現しない不具合として出る

## 影響する場所

- `config/environments/staging.rb` と、`config/database.yml`・`queue.yml`・
  `recurring.yml`・`cache.yml`・`cable.yml` の staging 節
- `config/initializers/default_url_options.rb` — 分岐を `local?` に変えた
- `config/credentials/{production,staging}.yml.enc` と `.gitignore`
- `docs/environments.md` — 環境変数と credentials の一覧
- #46 は destination ごとに `RAILS_ENV` と `RAILS_MASTER_KEY` を分けて渡す。
  Dockerfile は `RAILS_ENV=production` を焼き込んでいるので、ステージングは上書きが要る
