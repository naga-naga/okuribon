# frozen_string_literal: true

FactoryBot.define do
  factory :exchange do
    owner factory: :user
    name { "#{Faker::Book.genre}の交換会" }
    description { Faker::Lorem.paragraph }
    # 登録期間の終了と希望提出期間の開始は同時刻でなければならない。
    # 1.week.from_now を2回書くと評価のたびにマイクロ秒がずれるため、参照して揃える
    registration_starts_at { 1.week.ago }
    registration_ends_at { 1.week.from_now }
    wish_starts_at { registration_ends_at }
    wish_ends_at { 3.weeks.from_now }
    # 招待トークンと乱数シードはモデルが作成時に発行するため、ここでは指定しない
  end
end
