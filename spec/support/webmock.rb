# frozen_string_literal: true

require 'webmock/rspec'

# 通知は外部の Webhook へ POST する。spec がうっかり本物の URL を叩くと、
# 手元の実行がチャンネルに届いてしまう。登録していない通信はすべて落とす。
# 送信サービスを差し替えられるようにするだけでは、そこを通らない経路が残る
WebMock.disable_net_connect!(allow_localhost: false)
