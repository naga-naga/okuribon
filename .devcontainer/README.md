# devcontainer

Claude Code をホストから隔離して動かすための開発環境。

## 構成

| ファイル | 役割 |
|---|---|
| `devcontainer.json` | VS Code から見た設定。ボリューム、拡張機能、フック |
| `compose.yaml` | アプリコンテナと Postgres |
| `Dockerfile` | 公式の Ruby 3.4 に Rails 用の依存を足したもの |
| `post-create.sh` | コンテナ作成時に一度だけ走るセットアップ |

## はじめかた

1. VS Code に Dev Containers 拡張を入れる
2. このリポジトリを開き、「Reopen in Container」を選ぶ
3. ビルドが終わったらターミナルで `claude` を実行してサインイン

## 何から守られているか

**コンテナによる隔離が唯一かつ主要な防御。** ホストのホームディレクトリ、SSH 鍵、
ブラウザのプロファイル、他のプロジェクトは、コンテナからは見えない。

一方で、次のものには手が届く。

- `/workspaces/okuribon` 配下のファイル（ホスト側の実体そのもの）
- コンテナ内から到達できるあらゆるネットワーク
- Claude Code の認証トークン

通信の制限はかけていない。gem やパッケージの取得先が増えるたびに
原因の分かりにくい失敗を生むため、このプロジェクトでは割に合わないと判断した。

## 守るべきこと

- **本番の `RAILS_MASTER_KEY` をこのコンテナに置かない。** 開発用は別の鍵を使う
- **`~/.ssh` やクラウドの認証情報をマウントしない。** コンテナ内で読めるものは
  Claude Code からも読める
- GitHub へのアクセスが必要なら、リポジトリに限定した短命のトークンを使う

## デプロイの道具

`docker` / `aws` / `terraform` が入っている。**認証情報はこのコンテナに置かない。**
上の「守るべきこと」がそのまま当たる。置けば Claude Code からも読める。

| | 中で通るもの | ホストで打つもの |
|---|---|---|
| Terraform | `fmt`、`validate`（`init -backend=false` の後） | `init`、`plan`、`apply` |
| Kamal | イメージのビルド | `deploy`、`rollback` |
| AWS CLI | 無し | すべて |

`terraform init` が認証を要るのは、state を S3 バックエンドに置いているため。
`kamal deploy` にはレジストリへの push と本番の `RAILS_MASTER_KEY` が要る。
どちらもここでは通らない。**書くのはコンテナの中、配るのはホストから**になる。

Docker を入れてあるのは、`Dockerfile` が通るかを手元で確かめるため。
ビルドだけなら認証は要らない。

ホストの Docker ソケットは渡していない。渡すと、コンテナから
`docker run -v /:/host` でホストの全ファイルに手が届いてしまい、
「何から守られているか」が成り立たなくなる。代わりに docker-in-docker を使い、
コンテナの中に閉じた dockerd を持つ。`compose.yaml` の `privileged` はこのため。

## 権限プロンプトについて

通信制限がないため、`--dangerously-skip-permissions` は常用しないこと。
実装をまとめて走らせたいときに、作業の性質を見て使う。

普段は既定のまま（確認あり）か、auto mode を使う。

## 永続化されるもの

| 対象 | 保存先 |
|---|---|
| Claude Code の認証・設定・履歴 | 名前付きボリューム（プロジェクトごとに分離） |
| インストールした gem | 名前付きボリューム `okuribon_bundle` |
| Postgres のデータ | 名前付きボリューム `okuribon_postgres` |
| Docker のイメージ | 名前付きボリューム `okuribon_docker` |
| ソースコード | ホスト側のリポジトリ（bind mount） |

コンテナを作り直しても再ログインは不要。完全に消したい場合は該当のボリュームを削除する。

```
docker volume rm okuribon_postgres okuribon_bundle
```
