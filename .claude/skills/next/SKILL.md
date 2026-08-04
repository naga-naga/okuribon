---
name: next
description: 次に着手できる issue を判断して提示する。「次は何をやる？」「着手できるものは？」「今どこまで進んだ？」と聞かれたときに使う。提示までが仕事で、着手はしない。
---

# 次に着手できる issue を出す

現況を集め、着手可能な issue を理由付きで並べる。**選ぶのはユーザー。**
提示したあと、勝手に `issue` skill へ進まない。指示を待つ。

## 1. 現況を取る

task issue の状態、所属する Epic、Epic ごとの進捗が1コマンドで取れる。

```
gh issue list --state all --limit 100 --json number,title,state,labels,parent \
  --jq '[.[] | select(.labels[].name == "type:task")] | sort_by(.number) | .[] | "\(.number)\t\(.state)\tEpic #\(.parent.number // "-")\t\(.title)"'
```

Epic ごとの進捗はこちら。

```
gh issue list --state all --limit 100 --json number,labels,parent,state \
  --jq '[.[] | select(.labels[].name=="type:task")] | group_by(.parent.number) | .[] | "Epic #\(.[0].parent.number): \([.[] | select(.state=="CLOSED")] | length)/\(length)"'
```

**task の番号順が着手順の既定にあたる。** sub-issues も同じ順に並べてあるので、
原則として Epic 内では番号の小さいものから片付ける。

ただし**番号順を上書きする例外がある。** 次の節で見る依存関係が優先する。

あわせて `git log --oneline -10` を見る。issue が open のままでも、
実装が先に進んでいることがある。issue の状態だけを信じない。

## 2. 依存関係を見る

**番号順より依存関係が優先する。** 番号は振り直せないため、あとから分かった
着手順の誤りは GitHub の issue dependencies で表している。

```
gh api repos/naga-naga/okuribon/issues/<番号>/dependencies/blocked_by \
  -q '.[] | "#\(.number) \(.state) \(.title)"'
```

一覧の `blocked_by` の有無だけなら、まとめて取れる。

```
gh issue list --state open --limit 100 --json number,title,labels \
  --jq '[.[] | select(.labels[].name=="type:task")] | sort_by(.number) | .[].number' \
  | while read n; do
      d=$(gh api repos/naga-naga/okuribon/issues/$n/dependencies/blocked_by \
            -q '[.[] | select(.state=="open") | "#\(.number)"] | join(" ")' 2>/dev/null)
      [ -n "$d" ] && echo "#$n ← $d"
    done
```

**open な blocked_by が1つでも残っていれば着手できない。** closed なものは無視してよい。

登録されている依存は、番号順から外れるものと、行き先が先に無いと暫定を作ることになる
ものに絞ってある。**依存が無いことは「今すぐ着手してよい」を意味しない。**
番号順と Epic の「前提」も引き続き見る。

## 3. 関係する Epic の「前提」を読む

**Epic 間の依存は Epic 本文の「## 前提」にしかない。** task issue には書かれていない。

未完了の Epic のうち番号の小さいものから読む。全部読む必要はない。
着手候補が属する Epic と、そこが依存している Epic だけでよい。

```
gh issue view <Epic番号>
```

「前提」の書き方は3種類あり、意味が違う。読み分ける。

- **完了が必要** —「1. 基盤（#5 のスキーマ、#8 のフェーズ導出、#10 の書き込み制御）が
  完了していること」→ 挙がっている issue が closed になるまで着手できない
- **一部だけ必要** —「#41 と #42 は 2. 認証と参加のあとであれば着手できる」
  → Epic 単位で止めない。task ごとに判断する
- **参照・制約** —「#38 は #6（期間の整合性検証）を通す」「#39 は #17 と同じ制約に従う」
  → 着手を止めるものではない。実装時に見るべき先を指している

3つ目を依存と読み違えると、着手できるものを不当に塞いでしまう。注意する。

**番号順を上書きする指示も「前提」に書いてある。**「#29 だけは、この Epic の最後ではなく
5. マッチングと結果の #33 の後に着手する」のように、太字で書かれている。
issue dependencies にも同じ内容が入っているので、食い違ったら本文を信じる。

## 4. 提示する

着手できるものを**最大3件**に絞る。多く並べても選べない。

各件について次を書く。

- issue 番号とタイトル
- 所属する Epic と、その進捗
- **なぜ今着手できるのか**（前提が無い / 依存が closed になっている）
- 分量の見当（触るファイル、マイグレーションの有無）

続けて、次に控えているものを1〜2件、番号とタイトルだけ挙げる。

着手できないものが気になる場合は、**何の完了を待っているか**を書く。
「Epic 2 は #5 #8 #10 の完了待ち」のように、待ち対象の issue 番号を示す。

## 注意

- 候補がすべて出揃わないときは、その旨を言う。無理に3件に埋めない
- Epic の「前提」を読まずに番号順だけで答えない。Epic をまたぐ依存を見落とす
- **番号が小さいことを理由に、blocked_by が open のものを候補に挙げない**
- 進捗が sub-issues の集計と食い違っていたら、集計ではなく issue の state を信じる
