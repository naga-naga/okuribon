# frozen_string_literal: true

module Exchanges
  # 交換会の作成。交換会と主催者の参加を1つのトランザクションで作る。
  # モデルの save だけでは片方しか作れず、参加していない主催者が残る。
  #
  # 作成時に限り、登録の締切が未来であることも求める。判定に基準時刻が要るが、
  # ActiveRecord のバリデーションは引数を取れないため、ここに置く
  class Creation
    def initialize(owner:, attributes:, at:)
      @owner = owner
      @attributes = attributes
      @at = at
    end

    # 保存できた交換会を返す。作れなければ errors を積んだ未保存の交換会を返し、
    # フォームの差し戻しにそのまま使えるようにする
    def call
      exchange = @owner.owned_exchanges.build(@attributes)
      return exchange unless creatable?(exchange)

      exchange.transaction do
        exchange.save!
        # 参加を作る書き方を2つに増やさない。招待URLからの参加と同じ経路を通す
        exchange.join!(@owner, at: @at)
      end

      exchange
    end

    private

    # 締切を過ぎた日程では主催者の参加を作れず、参加者のいない交換会が残る。
    # 求めているのは「今この場で参加できるフェーズか」そのものなので、
    # 日時の比較を書き足さずフェーズの表から引く。
    # フェーズの導出は日時が揃っていることを前提にするため、不備を先に見る
    def creatable?(exchange)
      return false unless exchange.valid?
      return true if exchange.writable?(:participation, at: @at)

      exchange.errors.add(:registration_ends_at, :deadline_passed)
      false
    end
  end
end
