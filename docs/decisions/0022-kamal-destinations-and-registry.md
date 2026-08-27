# 0022 destination ごとに配り先を分け、レジストリを ECR にする

- 日付：2026-08-26
- 発端：#46

## 決めたこと

- `config/deploy.yml` に共通の設定を置き、`config/deploy.production.yml` と
  `config/deploy.staging.yml` に差分を置く。差分はホスト・ドメイン・`RAILS_ENV`・
  データベースのコンテナ名の4つ
- `require_destination: true` を置き、destination の無い実行を弾く。
  `.kamal/secrets` は削除し、`.kamal/secrets-common` と
  `.kamal/secrets.<destination>` に分ける
- PostgreSQL 17 は Kamal のアクセサリとして、アプリと同じホストで動かす。
  アクセサリの `service` に環境名を入れ、ポートは公開しない
- コンテナイメージのレジストリは Amazon ECR
- ホストの OS は Ubuntu とし、ssh のユーザーは `ubuntu`
- ホストの IP とドメインは仮の値を書く。IP は TEST-NET-3（203.0.113.0/24）、
  ドメインは `example.com` の下に置く
- マイグレーションはコンテナの起動時に走る `bin/docker-entrypoint` の
  `db:prepare` に任せ、Kamal のフックは置かない

## なぜ

destination の分け方は #45（`docs/decisions/0021`）が決めた環境の持ち方に従う。
`RAILS_ENV` と `RAILS_MASTER_KEY` を環境ごとに分けるところまでは決まっていたので、
残るのは、それをどこに書くかだけだった。

秘密のファイルを分けるのは Kamal の探し方に合わせたため。Kamal は destination が
付いたときだけ `.kamal/secrets-common` と `.kamal/secrets.<destination>` を読み、
付かないと `.kamal/secrets` へ落ちる（`Kamal::Secrets#secrets_filenames`）。
落ちた先に本番の鍵が書いてあると、destination を付け忘れた実行がそのまま通る。
`require_destination` と `.kamal/secrets` の削除は、この経路を塞ぐためのもの。

アクセサリの `service` を明示するのは、既定の名前に destination が入らないため
（`Kamal::Configuration::Accessory#service_name` は `<service>-<accessory>`）。
アプリのコンテナには入るので、明示しないとデータベースだけが名前を共有する。
本番とステージングを1台に載せるかは #47 で決まるが、名前を分けておけば
どちらに決まっても当たる。ボリュームの置き場もこの名前から決まるので、
名前が同じだとデータそのものを共有することになる。

ポートを公開しないのも同じ理由で、1台に載せたときに 5432 を取り合う。
アプリは `kamal` のネットワークからコンテナ名で引くため、公開しなくても届く。

ホストの OS は Kamal 側の都合で決めた。`kamal server bootstrap` は Docker が
入っていなければ `https://get.docker.com` のスクリプトを流し込むが、これは
Amazon Linux 2023 を未対応のディストリビューションとして弾く。

仮の値に予約済みのアドレスとドメインを使うのは、置き換え忘れたまま流したときに
実在の宛先へ向かわないようにするため。

## 却下した代替案

- **destination を分けず、環境変数だけで切り替える** — ファイルは1つで済むが、
  どちらの環境へ配ったのかがコマンドの履歴にしか残らない。Kamal が秘密の
  ファイルを destination で選ぶ仕組みにも乗れない
- **レジストリに ghcr.io を使う** — リポジトリと同じ場所にあり、認証は
  PAT 1つで済む。ECR を採ったのは、ホストが EC2 で、イメージの転送が
  同じリージョンの中で閉じるため。代償として、トークンが12時間で切れるので
  デプロイのたびに `aws ecr get-login-password` を通す
- **レジストリに Docker Hub を使う** — 無料の枠では private のリポジトリが
  1つまでで、ほかの用途と取り合う
- **PostgreSQL を EC2 のホストに直接入れる** — アクセサリにすると Kamal が
  コンテナの寿命を持つ。ホストに入れると、バージョンの固定と再構築の手順が
  リポジトリの外に出る
- **RDS を使う** — 運用は楽になるが、常時起動の費用が顔見知りの少人数で使う
  ツールに見合わない。データは1台の中に置き、バックアップで守る
- **ホストの OS を Amazon Linux 2023 にする** — AWS 純正で EC2 との相性はよいが、
  Docker を `dnf install docker` で先に入れておく前提になり、
  `kamal server bootstrap` が受け持つはずの範囲が手順書へ移る
- **マイグレーションを Kamal の pre-deploy フックで走らせる** — 起動より前に
  終わるので、新旧のコンテナが一瞬だけ違うスキーマを見る時間が消える。
  ただしサーバーは1台で、`db:prepare` は Rails が既定で用意している経路なので、
  そのために別の入口を増やさない

## 影響する場所

- `config/deploy.yml`、`config/deploy.production.yml`、`config/deploy.staging.yml`
- `.kamal/secrets-common`、`.kamal/secrets.production`、`.kamal/secrets.staging`
- `config/database.yml` — production と staging の `host` を `DB_HOST` から採る
- `config/environments/production.rb` — kamal-proxy が SSL を終端する前提を置いた
- `docs/environments.md` — 秘密の置き場と `DB_HOST`
- #47 は仮の値を実際のホストとドメインに置き換える。1台に相乗りさせるかも #47 で決める
