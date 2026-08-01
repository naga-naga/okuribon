# frozen_string_literal: true

# spec では実際のプロバイダへ出ていかない。
# テストモードでは認証の要求も応答も OmniAuth が偽装し、mock_auth の中身を返す。
# example ごとに元へ戻し、差し替えた認証情報が他の example に漏れないようにする
RSpec.configure do |config|
  config.around do |example|
    OmniAuth.config.test_mode = true
    original_mock_auth = OmniAuth.config.mock_auth.dup

    example.run
  ensure
    OmniAuth.config.mock_auth.replace(original_mock_auth)
    OmniAuth.config.test_mode = false
  end
end
