# frozen_string_literal: true

module Exchanges
  # 登録冊数の偏りから、受け取り手のない本が何冊出るかを見積もる。
  #
  # 自分が登録した本は受け取れないため（docs/spec.md 3.）、1人の登録冊数が
  # ほかの全員の合計を超えると、超えた分は誰にも渡せず登録者へ返る。
  # 冊数だけで決まり希望リストの中身を見ないので、希望提出が始まる前の
  # 登録期間中に出せる。主催者に打つ手が残っているのはそこまでしかない。
  #
  # 出るのは下限にあたる。ドラフトは希望の上位から取っていくので、
  # 返却を避けられた組み合わせを取り逃して、実際にはこれより増えることがある。
  class BookImbalance
    # 条件を満たす参加は多くても1つしかない。2人が同時に満たすとすると
    # 両者の冊数の和が総冊数を超えることになり、そんな数え方はできない
    Result = Data.define(:participation, :returning_count, :others_count)

    # @param participations [Enumerable] books_count に答える参加。
    #   Participation.with_counts が付ける。冊数を数えるだけの用なので、
    #   Book そのものは読み込まない（ギフトコードを運ばないため）
    def initialize(participations)
      @participations = participations
    end

    # @return [Result, nil] 受け取り手のない本が出ないなら nil
    def call
      top = @participations.max_by(&:books_count)
      return nil if top.nil?

      others_count = @participations.sum(&:books_count) - top.books_count
      returning_count = top.books_count - others_count
      return nil unless returning_count.positive?

      Result.new(participation: top, returning_count:, others_count:)
    end
  end
end
