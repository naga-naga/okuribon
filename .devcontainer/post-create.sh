#!/bin/bash
#
# コンテナを作り直したときに一度だけ走る。
#
set -euo pipefail

git config --global --add safe.directory /workspaces/okuribon

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
