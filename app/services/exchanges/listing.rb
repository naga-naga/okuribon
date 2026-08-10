# frozen_string_literal: true

module Exchanges
  # 交換会一覧に並べるカード（docs/spec.md 6.6）。
  #
  # カード1枚には、フェーズ・次の締切・すべきことに加えて、主催者名と参加人数が載る。
  # 交換会だけを引いて必要になったものをビューから足していくと、
  # 並ぶ件数だけ問い合わせが増えるので、並べるものをここで組み立てて渡す。
  class Listing
    # @param exchange [Exchange] フェーズと次の締切はここから引く
    # @param participation [Participation] 見ている本人の参加。取得枠を出すのに要る
    # @param headline [String] すべきことの1行。交換会トップと同じ文言を並べる
    # @param participants_count [Integer] 参加人数
    # @param active [Boolean] 書き込みが開いているか。見出しの下の一文が数える
    Card = Data.define(:exchange, :participation, :headline, :participants_count, :active)

    # @param user [User] 見ている本人
    # @param at [Time] 基準時刻。既定値は置かない。呼ぶたびに現在時刻が進むと、
    #   締切をまたいだ瞬間に並び順とカードの中身が別の時刻を指しうる
    def initialize(user, at:)
      @user = user
      @at = at
    end

    # @return [Array<Card>]
    def call
      participations.sort_by { sort_key(it.exchange) }.map { build_card(it) }
    end

    private

    def participations
      @participations ||= @user.participations.includes(exchange: :owner).to_a
    end

    # 次の締切の近い順に並べ、締切が無いもの（マッチング実行待ちと結果公開）を下へ送る。
    # フェーズで群に分けないのは、フェーズが変わった瞬間にカードが群をまたいで
    # 大きく動くため。日時は1本の軸なので、進んでも位置が少しずつしか動かない。
    # 締切が無いものどうしは日程の新しい順にする。待つ日時が無く、
    # 順序を決めないと開くたびに位置が入れ替わる
    def sort_key(exchange)
      deadline = exchange.next_deadline(at: @at)
      return [0, deadline.to_i] if deadline

      [1, -exchange.registration_starts_at.to_i]
    end

    def build_card(participation)
      exchange = participation.exchange

      Card.new(exchange:, participation:,
               headline: Todo.new(participation, at: @at).call.headline,
               participants_count: participants_counts.fetch(exchange.id, 0),
               active: exchange.writable?(:book, at: @at) || exchange.writable?(:wish, at: @at))
    end

    # 参加人数は1回の問い合わせでまとめて数える。カードごとに数えると、
    # 並ぶ件数だけ COUNT が飛ぶ
    def participants_counts
      @participants_counts ||=
        Participation.where(exchange_id: participations.map(&:exchange_id))
                     .group(:exchange_id).count
    end
  end
end
