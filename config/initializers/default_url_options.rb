# frozen_string_literal: true

# 通知に載せる画面へのリンクは、定期実行のジョブが組み立てる（7.）。
# ジョブにはリクエストが無いので、ホストは設定から採るしかない。
# 環境ごとに値だけが変わるため、環境ファイルに散らさずここに並べる。
#
# production の APP_HOST に既定値を置かない。ホストを取り違えたリンクは
# 押した人が別のサイトへ飛ぶまで気付けない。
# 起動時に落とさないのは、Docker のビルド中に assets:precompile が
# production で走るため。未設定のときは通知の文面を組む段でジョブが失敗する
Rails.application.routes.default_url_options =
  if Rails.env.production?
    { host: ENV.fetch('APP_HOST', nil), protocol: 'https' }
  else
    { host: 'localhost', port: 3000 }
  end
