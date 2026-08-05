# frozen_string_literal: true

FactoryBot.define do
  factory :exchange do
    owner factory: :user
    name { "#{Faker::Book.genre}の交換会" }
    description { Faker::Lorem.paragraph }
    # 希望提出期間の開始は registration_ends_at から導出されるため、ここでは指定しない
    registration_starts_at { 1.week.ago }
    registration_ends_at { 1.week.from_now }
    wish_ends_at { 3.weeks.from_now }
    # 招待トークンと乱数シードはモデルが作成時に発行するため、ここでは指定しない

    # 主催者は必ず参加者を兼ねる（docs/spec.md 2. 用語 / 6.9）。参加を持たない主催者は
    # Exchanges::Creation では作れないので、spec でもその状態を撒かない。
    # 結果公開の交換会にも要るため、フェーズを見る join! ではなく直に作る
    after(:create) do |exchange|
      exchange.participations.create_or_find_by!(user: exchange.owner)
    end
  end
end
