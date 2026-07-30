# frozen_string_literal: true

# 時刻を前後させる spec を書けるようにする。フェーズ境界の検証で使う。
#
# 固定の手段は2つあり、リクエストをまたぐかどうかで使い分ける。
#
# - `Current.time = t` … モデルやサービスの spec 向け。リクエストの終わりに
#   Rails の executor が CurrentAttributes を消すため、リクエストをまたぐと効かない
# - `travel_to(t)` … リクエスト spec 向け。`Time.zone.now` 自体を差し替えるので、
#   `Current.time` の既定値を通してリクエストをまたいでも効き続ける
#
# example 間のリセットは rspec-rails が
# `ActiveSupport::CurrentAttributes::TestHelper` を include して行うため、ここでは足さない。
RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
end
