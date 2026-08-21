# frozen_string_literal: true

module Exchanges
  # 実行すると何人に何冊が渡り、何が思いどおりにならないのかを、押す前に数で示す。
  # 取り返しのつかない操作なので、一覧を読み比べて自分で数えさせない。
  # 出すのは人数と冊数だけで、誰が何を希望したかには触れない。
  class MatchingSummary
    Result = Data.define(:target_count, :books_count, :unsubmitted_count,
                         :without_books_count, :returning_count)

    # @param participations [Enumerable] books_count と wishes_count に答える参加。
    #   Participation.with_counts が付ける。数を出すだけなので Book は読み込まない
    def initialize(participations)
      @participations = participations
    end

    # @return [Result]
    def call
      # 取得枠は登録冊数と同数なので、1冊も登録していない人は割当に現れない
      targets = @participations.select { |participation| participation.books_count.positive? }

      Result.new(
        target_count: targets.length,
        books_count: targets.sum(&:books_count),
        # 希望を出していなくても余り物が回る。取得枠が0の人は出しようがないので、
        # 対象の中だけで数える。声を掛けても変わらない相手を追わせない
        unsubmitted_count: targets.count { |participation| participation.wishes_count.zero? },
        # 締め出されたのではなく仕組みの結果。実行してから
        # 「なぜこの人には何も届かないのか」を問われないよう、先に数で出す。
        # count ではなく length で数える。with_counts は GROUP BY を持つので、
        # count は全体の件数ではなくグループごとの件数を数える SQL になる
        without_books_count: @participations.length - targets.length,
        # 冊数だけから決まる下限。判定は登録期間中の警告と同じものを使う。
        # 別に書くと、確認画面と管理画面の警告で冊数が食い違う
        returning_count: Exchanges::BookImbalance.new(@participations).call&.returning_count.to_i
      )
    end
  end
end
