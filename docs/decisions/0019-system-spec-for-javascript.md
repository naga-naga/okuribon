# 0019 JavaScript の振る舞いを system spec で押さえる

- 日付：2026-08-22
- 発端：issue #180

## 決めたこと

system spec を導入し、JavaScript が動いて初めて成立する振る舞いを押さえる。
押さえる範囲と押さえない範囲は `CLAUDE.md`「テスト > JavaScript の振る舞い」に書いた。

足場を入れて希望リストの並べ替えを押さえるところまでと、残りの Stimulus controller を
押さえるところを、別の issue に分けた。ブラウザとドライバの選定は前者で決める。

## なぜ

Stimulus controller が7つあり、request spec が見ているのは data 属性による接続までだった。
接続から先の振る舞いは手で確かめており、確かめる範囲が回ごとに変わる。

範囲を絞らなかったのは、足場の費用が対象の数でほとんど変わらないため。
ブラウザとドライバを1つ用意すれば、そこから先は例を足す作業になる。

その足場も、着手前に見込んでいたより小さかった。devcontainer には Playwright MCP のために
Chromium が入っており（`~/.cache/ms-playwright`）、CI の `ubuntu-latest` にも Chrome が同梱されている。
どちらも CDP で繋げるので、chromedriver の版合わせは要らない。

## 却下した代替案

- **手で確かめる運用を続ける。** run skill と Playwright MCP で画面を通す道は既にあるが、
  リリース前の手作業に頼ると、確かめる範囲が回ごとに変わる。`wish_reorder` だけでも
  ドラッグ・キー操作・保存の待ち合わせ・保存後のフォーカス復帰と経路が分かれており、
  毎回同じだけ通せる分量ではない
- **対象をキーボード操作に絞り、ドラッグを外す。** ドラッグは `pointermove` の座標計算に
  乗っているためドライバ依存で不安定になりやすいが、外すと、いちばん手で確かめにくいものが
  手元に残る。不安定さは対象を減らして避けるのではなく、足場の側で扱う
- **Stimulus controller を Node 側の単体テストで押さえる。** テスト環境がもう1つ増える。
  壊れて困るのは DOM とサーバーへの往復を含めたつなぎ目で、controller 単体では
  `ResizeObserver` も `IntersectionObserver` も本物ではない
- **並べ替えの結果の正しさを system spec でも見る。** `Participation#reorder_wishes!` の
  spec が既に持っている。同じ判定を2か所で見ると、片方だけ直したときに食い違う

## 影響する場所

- `CLAUDE.md`「テスト > JavaScript の振る舞い」
- `app/javascript/controllers/`
- `docs/decisions/0017`（見た目の検証を system spec へ移さないと決めた範囲は変わらない）
