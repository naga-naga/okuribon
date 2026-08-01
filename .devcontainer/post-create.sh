#!/bin/bash
#
# コンテナを作り直したときに一度だけ走る。
#
set -euo pipefail

git config --global --add safe.directory /workspaces/okuribon

# origin は SSH URL のままにしておき、コンテナ内でだけ HTTPS に読み替える。
# .git/config はホストと共有しているため、origin 自体を書き換えるとホスト側の
# SSH での push まで巻き添えになる。~/.gitconfig はコンテナ固有なのでここに置く
git config --global url."https://github.com/".insteadOf "git@github.com:"

# HTTPS の認証は gh に任せる。gh は GH_TOKEN を読むので、
# .devcontainer/.env にトークンを置けば push まで通る（gh auth login は不要）。
#
# VS Code が独自の credential helper を登録しており、そのままだと先に試されて
# 「User cancelled dialog」で一度失敗する。空文字を挟んで一覧をリセットし、
# github.com に対しては gh だけが使われるようにする
git config --global --unset-all credential."https://github.com".helper 2>/dev/null || true
git config --global --add credential."https://github.com".helper ""
git config --global --add credential."https://github.com".helper "!gh auth git-credential"

# コミットの author をホストの gitconfig から引き継ぐ。未設定だと commit が落ちる。
#
# ~/.gitconfig にそのまま被せない理由は、上で設定した insteadOf が
# ホスト側へ流れ込み、ホストの SSH での push を壊してしまうため。
# 読み取り専用でマウントしたものから、必要な値だけを取り出す
host_gitconfig=/tmp/host-gitconfig
if [ -f "$host_gitconfig" ]; then
    host_user_name=$(git config --file "$host_gitconfig" --get user.name || true)
    host_user_email=$(git config --file "$host_gitconfig" --get user.email || true)

    if [ -n "$host_user_name" ]; then
        git config --global user.name "$host_user_name"
    fi
    if [ -n "$host_user_email" ]; then
        git config --global user.email "$host_user_email"
    fi
fi

# ブラウザで画面を確認するための Playwright MCP（.mcp.json から起動する）。
#
# chromium は @playwright/mcp が抱える playwright-core と同じリビジョンでないと
# 「Executable doesn't exist」で落ちる。グローバルの npx playwright ではなく、
# ここで入れたものの CLI を使ってリビジョンを合わせる。
# --with-deps は共有ライブラリを apt で入れるため sudo が要る
echo "==> 開発ツール（Playwright MCP）"
npm --prefix .devcontainer ci
.devcontainer/node_modules/.bin/playwright install --with-deps chromium

if [ -f Gemfile ]; then
    echo "==> bundle install"
    bundle install
else
    # まだ Rails アプリを作っていない段階。本体だけ入れておく
    echo "==> Rails をインストール"
    gem install rails --no-document
    cat <<'MSG'

--------------------------------------------------------------------
Rails アプリがまだありません。次のコマンドで作成してください。

    rails new . --name=okuribon \
                --database=postgresql \
                --javascript=importmap \
                --skip-devcontainer \
                --skip-test

作成後、接続確認まで:

    bin/rails db:prepare
    bin/rails server

DATABASE_URL がコンテナに渡してあるので、database.yml の編集は不要です。
--------------------------------------------------------------------

MSG
fi
