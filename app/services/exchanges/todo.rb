# frozen_string_literal: true

module Exchanges
  # 登録期間と希望提出期間で数週間かかるツールなので、久しぶりに開いた人が
  # その日なにをすればよいかを、この1行だけで掴めるようにする。
  # フェーズだけでは決まらない。同じ登録期間でも、1冊も登録していない人と
  # すでに登録した人では、次にすることが変わる。
  #
  # 文言の組み立てをビューに置かないのは、交換会一覧のカードが
  # 同じ headline を並べるため。
  class Todo
    # @param headline [String] すべきことの1行。交換会一覧はこれだけを使う
    # @param detail [String] 自分の状態にもとづく補足。トップだけが出す
    # @param tone [Symbol] 面の強さ。:urgent は朱、:done は松葉、:normal は生成り
    Statement = Data.define(:headline, :detail, :tone)

    # 朱を置くのは、放っておくと受け取る本が0冊になる状態だけに絞る。
    # 締切の近さでは変えない。残りの長さは締切の段が別に出しており、
    # 状態と時間の2つを同じ朱で表すと、どちらの意味の朱なのか読み分けられない
    TONES = {
      registration_none: :urgent,
      wish_empty: :urgent,
      published: :done,
      published_none: :done,
      published_without_slots: :done,
    }.freeze

    # @param participation [Participation] 見ている本人の参加。取得枠と希望冊数を持つ
    # @param at [Time] 基準時刻
    def initialize(participation, at:)
      @participation = participation
      @exchange = participation.exchange
      @at = at
    end

    # @return [Statement]
    def call
      key, options = statement

      # 差し込む値は headline と detail の両方に渡す。冊数は見出しにも入りうるので、
      # どちらが使うかをここで決め打たない。使わない値を渡しても I18n は無視する
      Statement.new(headline: t(key, :headline, **options), detail: t(key, :detail, **options),
                    tone: TONES.fetch(key, :normal))
    end

    private

    # フェーズごとの枝はすべて同じ名前のメソッドに預ける。1行で済むものを
    # ここへ書き下すと、どのフェーズが分岐を持つのかが並びから読めなくなる。
    # @return [Array(Symbol, Hash)] 文言のキーと、そこへ差し込む値
    def statement
      case @exchange.phase(at: @at)
      when :preparing then preparing
      when :registration then registration
      when :wish then wish
      when :awaiting_matching then awaiting_matching
      when :published then published
      end
    end

    # 待っているのは締切ではなく開始。登録期間がいつ始まるかを出す
    def preparing
      [:preparing, { at: schedule(@exchange.registration_starts_at) }]
    end

    # 登録した冊数がそのまま取得枠になる。0冊のままだと受け取る権利が無いので、
    # 冊数を出すより先に、そのことを伝える
    def registration
      slots.zero? ? [:registration_none, {}] : [:registration, { count: slots }]
    end

    def wish
      # 希望提出期間に入った時点で登録期間は終わっており、取得枠を増やす道が
      # 残っていない。果たせない促しはしない
      return [:wish_without_slots, {}] if slots.zero?

      count = @participation.wishes.count

      count.zero? ? [:wish_empty, {}] : [:wish, { count: }]
    end

    # 次に動くのは主催者の操作で、日時では決まらない。待つべき日時が無いので、
    # 締め切った日時のほうを出して、受付が終わったことを言う。
    # ここだけは主催者かどうかでも変わる。ほかのフェーズと違って、次に何が起きるかが
    # 見ている本人の操作にかかっているのが1人だけいる。その人にまで待てと言うと、
    # 交換会がそこで止まったままになる。
    # 主催者かどうかは実行の可否から引く
    def awaiting_matching
      options = { at: schedule(@exchange.wish_ends_at) }

      executable? ? [:awaiting_matching_owner, options] : [:awaiting_matching, options]
    end

    # 交換会ページが実行への導線を出すかどうかと同じ述語を見る
    def executable?
      @exchange.matching_executable?(@participation.user, at: @at)
    end

    def published
      # 返却は誰にも渡せなかった本が登録者へ戻ることで、受け取りには数えない
      received = @participation.assignments.where(returned: false)
      count = received.count

      # 受け取りが0冊になる理由は2つある。1冊も登録しなかったか、取得枠はあったが
      # 割り当てられる本が残らなかったか。前者は本人に心当たりがあり、後者は無い
      return [slots.zero? ? :published_without_slots : :published_none, {}] if count.zero?

      # 贈り主の名前だけが要るので、Book を読み込まずに名前を引く。
      # 同じ人から2冊届くことがあるので重複を落とす
      givers = received.joins(book: :registrant).distinct.pluck(:display_name)

      [:published, { count:, givers: givers.map { "#{it} さん" }.to_sentence }]
    end

    def slots
      @slots ||= @participation.books.count
    end

    def schedule(time)
      I18n.l(time, format: :schedule)
    end

    def t(key, part, **)
      I18n.t(part, scope: [:exchange, :todos, key], **)
    end
  end
end
