# frozen_string_literal: true

module Matching
  # マッチングの実行。Engine と Active Record の橋渡しをする。
  #
  # Engine はレコードを知らないので、参加と本を識別子へ詰め替えて渡し、
  # 返ってきた割当を保存する。参加者の識別子には participation.id を使う。
  # 割当も本も参加にぶら下がっているため、利用者まで遡らずに書き戻せる。
  #
  # 実行できるのは一度だけ（CLAUDE.md「マッチング」）。行ロックの内側で
  # フェーズを見ることで、同時に2回呼ばれても片方だけが通る
  class Execution
    def initialize(exchange:, at:)
      @exchange = exchange
      @at = at
    end

    # @return [Exchange] 結果公開に入った交換会
    def call
      # with_lock はロックを取るときに交換会を読み直す。あとから入った側は
      # 先に入った側が書いた matched_at を見るので、フェーズの判定がそのまま
      # 二重実行の防止になる
      @exchange.with_lock do
        verify_executable!

        result = engine_result
        save_assignments(result)
        save_draft_order(result)
        @exchange.update!(matched_at: @at)
      end

      @exchange
    end

    private

    # 締切前の実行も再実行も、拒む理由は「そのフェーズでは書き込めない」の一つ。
    # マッチング実行日時が入った交換会は結果公開フェーズになるため（Exchange#phase）、
    # 実行済みかどうかを別に見なくてよい
    def verify_executable!
      return if @exchange.writable?(:matching, at: @at)

      raise Exchange::PhaseViolation.new(@exchange, :matching, at: @at)
    end

    # 参加も本も id 順に並べて渡す。Engine はシャッフルの元になる並びを
    # 受け取った順のまま使うので、並び順が変われば同じシードでも結果が変わる。
    # 並べずに読むと、DB がどの順で行を返すかに結果が左右される
    def engine_result
      participations = @exchange.participations.order(:id).to_a

      Matching::Engine.new(
        participants: participations.map(&:id),
        # Engine が見るのは識別子だけ。Book のレコードを読み込むと、暗号化された
        # ギフトコードまで一緒に運ばれてくる。取得経路は1つに限る（CLAUDE.md）ので、
        # 必要な2列だけを取り出して Matching::Book へ詰め替える。
        # この module の中では Book と書くと Matching::Book が先に見つかるため、
        # レコードのほうと読み違えないよう名前空間ごと書く
        books: @exchange.books.order(:id).pluck(:id, :participation_id)
                        .map { |id, owner_id| Matching::Book.new(id:, owner_id:) },
        # 希望リストは順序が意味を持つ。association の order をあてにせず、
        # ここでも順位で並べ直す
        wishes: participations.to_h { |part| [part.id, part.wishes.order(:position).pluck(:book_id)] },
        seed: @exchange.random_seed
      ).call
    end

    # Matching::Assignment（Engine が返す構造体）と Assignment（レコード）は
    # 名前が重なる。この module の中では前者が先に見つかるため、
    # レコードのほうは :: を付けて名指しする
    def save_assignments(result)
      result.assignments.each do |assignment|
        ::Assignment.create!(
          book_id: assignment.book_id,
          participation_id: assignment.participant_id,
          round: assignment.round,
          returned: assignment.returned?
        )
      end
    end

    # 抽選順は Engine が毎回返しているが、これまで捨てていた。結果公開後に見せるので
    # （docs/spec.md 8.）、実行された事実として保存する。
    # 読むときにシードから引き直す手もあるが、乱数の消費順という Engine の内部に
    # 画面が依存し、Engine を変えた瞬間に保存済みの割当と表示がずれる。
    # 参加の識別子には participation.id を渡してある（engine_result）
    def save_draft_order(result)
      # 数人から十数人の交換会なので（docs/spec.md 10.）、1件ずつ書いてよい
      result.draft_order.each_with_index do |participation_id, index|
        Participation.find(participation_id).update!(draft_position: index + 1)
      end
    end
  end
end
