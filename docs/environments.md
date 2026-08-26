# 環境ごとの設定

本番（`production`）とステージング（`staging`）は同じ構成で動かす。
アプリの設定は `config/environments/staging.rb` が `production` を読んで揃えており、
違うのは接続先と鍵だけになる。

規範は `docs/spec.md` が持つ。ここに書くのは、どこに何を置くかと、
置き忘れたときに何が起きるか。

## 鍵と credentials

| 環境 | credentials | 鍵 |
| --- | --- | --- |
| development / test | `config/credentials.yml.enc` | `config/master.key` |
| 本番 | `config/credentials/production.yml.enc` | `config/credentials/production.key` |
| ステージング | `config/credentials/staging.yml.enc` | `config/credentials/staging.key` |

Rails は `RAILS_ENV` に対応するファイルがあればそれを読み、無ければ
`config/credentials.yml.enc` へ落ちる。**落ちてもエラーにならない。**
環境ごとのファイルを消すと、デプロイ先が development と同じ鍵で動き出す。

`.key` はリポジトリに入らない（`.gitignore`）。コンテナへは `RAILS_MASTER_KEY` で渡す。
渡す先はその環境の `.key` の中身で、環境をまたいで使い回さない。

### 鍵を失うとどうなるか

**Active Record Encryption の `primary_key` を失うと、登録済みのギフトコードは
二度と復号できない。** credentials を作り直しても戻らない。本を登録した人が
控えを持っていない限り、そのギフトコードは失われる。

鍵はパスワードマネージャに控える。手元の `.key` だけを頼りにしない。

### credentials の中身

```yaml
secret_key_base: ...

active_record_encryption:
  primary_key: ...
  deterministic_key: ...
  key_derivation_salt: ...

google:
  client_id: ...
  client_secret: ...
```

編集は `bin/rails credentials:edit --environment production`（`staging` も同じ形）。

`google` は環境ごとに別のクライアントを発行する。同じクライアントを使い回すと、
ステージングの設定を間違えたときに本番のコールバック URL ごと巻き込む。

## OAuth のコールバック URL

`https://<APP_HOST>/auth/google_oauth2/callback`

Google Cloud console の「承認済みのリダイレクト URI」に、環境ごとの URL を登録する。
`APP_HOST` と食い違うと認証の最後で `redirect_uri_mismatch` になる。

## 環境変数

コンテナへ渡すもの。

| 変数 | 値 | 何に使うか |
| --- | --- | --- |
| `RAILS_ENV` | `production` / `staging` | 読む設定と credentials を決める |
| `RAILS_MASTER_KEY` | その環境の `.key` の中身 | credentials の復号 |
| `APP_HOST` | 各環境のホスト名 | 通知に載せるリンクのホスト |
| `DB_HOST` | `okuribon-db-production` / `okuribon-db-staging` | PostgreSQL のコンテナ名 |
| `OKURIBON_DATABASE_PASSWORD` | DB の `okuribon` のパスワード | PostgreSQL への接続 |
| `SOLID_QUEUE_IN_PUMA` | `true` | Solid Queue を Puma の中で動かす |

`RAILS_ENV` は Dockerfile が `production` で焼き込んでいるので、
ステージングへ配るときは `staging` で上書きする。

`APP_HOST` に既定値は無い。未設定でも起動は通る（Docker のビルド中に
`assets:precompile` が production で走るため）が、通知の文面を組む段でジョブが失敗する。

`DB_HOST` はアクセサリのコンテナ名を指す。アプリと PostgreSQL は同じ `kamal` の
ネットワークにいるので、名前で引ける。未設定だとアプリのコンテナの中の
Unix ソケットを見に行き、起動時の `db:prepare` が接続に失敗する。

任意のもの。既定のままでよい。

| 変数 | 既定 | 何に使うか |
| --- | --- | --- |
| `RAILS_LOG_LEVEL` | `info` | ログの量 |
| `RAILS_MAX_THREADS` | 3 | Puma のスレッド数と DB の接続数 |
| `WEB_CONCURRENCY` | 1 | Puma のワーカー数 |
| `JOB_CONCURRENCY` | 1 | Solid Queue のワーカー数 |

## Kamal へ渡す秘密

`.kamal/` に置く。値そのものは書かず、取り出すコマンドか環境変数の参照だけを書く。
どのファイルも追跡している。

| ファイル | 読まれるとき | 中身 |
| --- | --- | --- |
| `.kamal/secrets-common` | 常に | レジストリの認証 |
| `.kamal/secrets.production` | `-d production` | 本番の `RAILS_MASTER_KEY` と DB のパスワード |
| `.kamal/secrets.staging` | `-d staging` | ステージングの同じもの |

**destination を付けると `.kamal/secrets` は読まれない。** Kamal が探すのは
`secrets-common` と `secrets.<destination>` の2つになる。`config/deploy.yml` の
`require_destination` が destination の無い実行を弾いているので、
`.kamal/secrets` は置いていない。

`OKURIBON_DATABASE_PASSWORD` はシェルの環境変数から入る。パスワードマネージャから
取り出して export してからデプロイする。未設定でも Kamal は止まらず、
PostgreSQL のコンテナが初期化に失敗するところまで進む。

レジストリは ECR で、`aws ecr get-login-password` が返すトークンを使う。
12時間で切れるので、デプロイのたびに取り直している。`aws` のプロファイルは
デプロイする手元の端末が持つ。

## データベース

環境ごとに4つ持つ。ジョブとキャッシュとケーブルを主のデータベースと分けるのは
どの環境でも同じ（`docs/spec.md` 11.）。

| | 本番 | ステージング |
| --- | --- | --- |
| 主 | `okuribon_production` | `okuribon_staging` |
| キャッシュ | `okuribon_production_cache` | `okuribon_staging_cache` |
| ジョブ | `okuribon_production_queue` | `okuribon_staging_queue` |
| ケーブル | `okuribon_production_cable` | `okuribon_staging_cable` |

ホストは分かれるが、名前も分けてある。名前が同じだと、接続先を取り違えたときに
ステージングの `db:prepare` が本番のデータを触る。

4つとも PostgreSQL 17 のアクセサリの中にある。アプリと同じホストで動き、
データは `$PWD/okuribon-db-<環境>/data` に残る。デプロイでは作り直さない
（`kamal accessory` が別に扱う）。ポートは公開していないので、外から触るには
`bin/kamal dbc -d <環境>` か、ホストで `docker exec` を通す。

作成は起動時の `db:prepare` に任せている。アクセサリは `POSTGRES_USER` と同じ名前の
データベースだけを作り、アプリが使う4つはそこに含まれない。

## タイムゾーン

`config.time_zone = 'Tokyo'` は `config/application.rb` にあり、環境で分かれない。
ホスト側の TZ にも依存しない。
