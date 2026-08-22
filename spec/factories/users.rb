# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    # log_in_as がこの値をそのまま認証情報に載せる
    provider { 'google_oauth2' }
    sequence(:uid, &:to_s)
    display_name { Faker::Name.name }
    avatar_url { Faker::Internet.url }
  end
end
