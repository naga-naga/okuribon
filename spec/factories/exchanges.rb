# frozen_string_literal: true

FactoryBot.define do
  factory :exchange do
    owner factory: :user
    name { "#{Faker::Book.genre}の交換会" }
    description { Faker::Lorem.paragraph }
    # 各期間は開始時刻を含み終了時刻を含まないため、境界が一致していても重ならない
    registration_starts_at { 1.week.ago }
    registration_ends_at { 1.week.from_now }
    wish_starts_at { 1.week.from_now }
    wish_ends_at { 3.weeks.from_now }
    invite_token { SecureRandom.urlsafe_base64(16) }
    random_seed { SecureRandom.random_number(2**62) }
  end
end
