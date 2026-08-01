# frozen_string_literal: true

# 認証情報は credentials に置く。リポジトリに平文で入れない
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           Rails.application.credentials.dig(:google, :client_id),
           Rails.application.credentials.dig(:google, :client_secret)
end

# 既定では標準出力へ直接書く。Rails のログに寄せる
OmniAuth.config.logger = Rails.logger
