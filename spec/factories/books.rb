# frozen_string_literal: true

FactoryBot.define do
  factory :book do
    participation
    title { Faker::Book.title }
    summary { Faker::Lorem.paragraph }
    url { Faker::Internet.url }
    recommendation { Faker::Lorem.sentence }
    gift_code { SecureRandom.alphanumeric(16) }
  end
end
