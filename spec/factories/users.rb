# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    provider { 'github' }
    sequence(:uid, &:to_s)
    name { Faker::Name.name }
    avatar_url { Faker::Internet.url }
  end
end
