# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    # 実装があるのは Google だけ。log_in_as がこの値をそのまま
    # 認証情報に載せるので、実際に発行されないプロバイダを既定に置かない
    provider { 'google_oauth2' }
    sequence(:uid, &:to_s)
    display_name { Faker::Name.name }
    avatar_url { Faker::Internet.url }
  end
end
