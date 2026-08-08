# frozen_string_literal: true

FactoryBot.define do
  factory :wish do
    transient do
      # 希望を出す人に交換会を揃える。参加が欠けている spec もあるので、
      # そこから引けなければ新しく作る
      exchange { participation&.exchange || association(:exchange) }
    end

    participation
    # 希望は同じ交換会の中で完結し、自分が登録した本は選べない。
    # 参加と本をそれぞれ単独で作ると、どちらも満たさない組み合わせができる
    book { association :book, participation: association(:participation, exchange:) }
    sequence(:position, 1)
  end
end
