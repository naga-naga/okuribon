# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # ギフトコードと OAuth の認可コードは既定のパターンに引っかからないため明示する。
  # :code は部分一致なので gift_code も兼ねるが、意図が読めるよう両方を残す
  :gift_code, :code,
  # Webhook URL はチャンネルへ投稿できる資格情報にあたる。パスにトークンが載るため、
  # URL そのものを知られた時点で誰でも投稿できる
  :webhook_url,
]
