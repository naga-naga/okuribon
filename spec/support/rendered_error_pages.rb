# frozen_string_literal: true

# エラー画面は例外から描かれるので、request spec の既定では中身を見られない。
# test 環境は consider_all_requests_local = true で、DebugExceptions が
# 例外の詳細ページを先に返してしまうため。この1つの設定だけを例の間だけ倒し、
# 本番と同じく exceptions_app を通す。
# show_exceptions（:rescuable）はそのままにする。倒すと、拾うつもりのない
# 例外まで画面になり、spec が落ちるべきところで落ちなくなる
RSpec.shared_context 'エラー画面を描く' do
  around do |example|
    env_config = Rails.application.env_config
    key = 'action_dispatch.show_detailed_exceptions'
    original = env_config[key]
    env_config[key] = false
    example.run
  ensure
    env_config[key] = original
  end
end

RSpec.configure do |config|
  config.include_context 'エラー画面を描く', rendered_error_pages: true
end
