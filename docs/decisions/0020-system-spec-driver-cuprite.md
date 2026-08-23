# 0020 system spec の足場を cuprite で組む

- 日付：2026-08-22
- 発端：issue #194

## 決めたこと

Capybara のドライバに cuprite を使い、Chrome へ CDP で直に繋ぐ。chromedriver は持たない。
ブラウザの実行ファイルは、devcontainer が `~/.cache/ms-playwright` の Chromium、
CI が `ubuntu-latest` 同梱の `google-chrome` を PATH から拾う。

`--no-sandbox`（ferrum の `dockerize`）を常に付ける。

WebMock の localhost 遮断を解く。

並べ替えが送られたことは、コントローラの `process_action` 通知に届いた `book_ids` で見る。

## なぜ

CDP は Chrome が自分で備えている通信規約なので、間に立つ実行ファイルが要らない。
chromedriver を挟むと、ブラウザの版に合わせて別の実行ファイルを用意することになる。

`--no-sandbox` は devcontainer と `ubuntu-latest` の両方で要る。どちらも非特権の
user namespace を作れず、Chrome は sandbox を張れないまま起動に失敗する。
環境で出し分けても、付けない側が使われる場面が無い。

localhost を通すのは、ferrum が繋ぎ先を決めるのに CDP の待ち受けポートへ
Net::HTTP で問い合わせるため。通知先のホストは localhost ではないので、
本物の Webhook を叩かせない目的のほうは満たされたままになる。

送られたことをコントローラの通知で見るのは、画面からは読めないため。
並びは送る前から JavaScript が動かしているので、動かした並びと返ってきた並びを
画面の中身で見分けられない。

## 却下した代替案

- **Capybara + selenium。** Rails の既定で、Selenium Manager が版の合う chromedriver を
  引いてくるので手で揃える作業は起きない。ただしテストのたびにドライバの取得が挟まり、
  取得できるかどうかが実行環境の外に出る
- **playwright-ruby-client。** devcontainer に入っている Chromium は Playwright のものなので
  相性はよいが、ブラウザを動かす実体が Node 側に移り、テスト環境がもう1つ増える
- **ブラウザを CI と devcontainer で別々に用意して版を固定する。** どちらの環境にも
  すでに Chrome がある。取ってくるものを増やすと、その取得が落ちたときに
  差分と無関係な赤が出る
- **保存された `Wish` の並びを見て、送られたことを確かめる。** 順位の振り直しは
  `Participation#reorder_wishes!` の spec が持っている。同じ判定を2か所で見ると、
  片方だけ直したときに食い違う
- **WebMock の `allow` に CDP のポートだけを並べる。** 待ち受けポートは起動のたびに変わる

## 影響する場所

- `spec/support/system.rb`
- `spec/support/webmock.rb`
- `CLAUDE.md`「検証 > system spec」
- `.github/workflows/ci.yml`
