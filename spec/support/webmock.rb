# frozen_string_literal: true

require 'webmock/rspec'

# 通知は外部の Webhook へ POST する。spec がうっかり本物の URL を叩くと、
# 手元の実行がチャンネルに届いてしまう。登録していない通信はすべて落とす。
# 送信サービスを差し替えられるようにするだけでは、そこを通らない経路が残る。
#
# localhost だけは通す。system spec のブラウザを起こす ferrum が、
# 繋ぎ先を決めるのに CDP の待ち受けポートへ Net::HTTP で問い合わせる。
# 通知先のホストは localhost ではないので、塞ぎたいものは塞がったまま
WebMock.disable_net_connect!(allow_localhost: true)
