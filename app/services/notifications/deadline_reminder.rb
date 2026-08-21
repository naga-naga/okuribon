# frozen_string_literal: true

module Notifications
  # 出すかどうかは交換会の日時だけから決める。誰が登録したか、誰が希望を出したかは
  # 読まない。「全員が対応済み」は定義できず、0冊かどうかで
  # 測れるのは「まったく手を付けていない」だけになる。
  #
  # 本文に載せるのは交換会名・締切・リンクだけにする。チャンネルへの投稿は誰が読むかを
  # 選べないので、ギフトコードと個人の希望リストは載せられない
  class DeadlineReminder
    # 締切の何時間前から知らせるか。網（Notifications::RemindAllDeadlinesJob）の間隔と
    # 同じ24時間にする。これより短くすると、予約を取りこぼした日に走査が窓の中へ落ちない。
    # 24時間ちょうどなら、1日1回の走査が必ず1回だけ窓の中に入る
    WINDOW = 24.hours

    # 準備中が待っているのは締切ではなく登録期間の開始で、
    # まだ促す行動が無い。マッチング実行待ちが待っているのは主催者の操作、
    # 結果公開はもう終わっている。
    # Exchange#next_deadline は準備中にも日時を返すので、任せきりにせずここで絞る
    REMINDABLE_PHASES = [:registration, :wish].freeze

    SCOPE = 'notification.deadline_reminder'

    # 走査の途中で現在時刻を読み直すと、窓の縁にいる交換会を
    # 前半と後半で違う扱いにする
    def self.deliver_all(at:)
      Exchange.find_each { new(it, at:).deliver }
    end

    def initialize(exchange, at:)
      @exchange = exchange
      @at = at
    end

    def deliver
      deadline = approaching_deadline
      return if deadline.nil? || reminded?(deadline)

      # 本文を先に組む。組めないまま記録だけ進めると、原因を直しても
      # その締切のリマインドは二度と出ない（Notifications::PhaseChange と同じ）
      text = message(deadline)
      return unless claim(deadline)

      Notifications::DeliverJob.perform_later(@exchange, text)
    end

    private

    # 窓の中にいるときだけ締切を返す。窓の終端は締切そのものだが、締切を過ぎると
    # フェーズが次へ移るので、ここで上限を見る必要はない
    def approaching_deadline
      return nil unless REMINDABLE_PHASES.include?(@exchange.phase(at: @at))

      deadline = @exchange.next_deadline(at: @at)
      deadline if @at >= deadline - WINDOW
    end

    # 記録を先に進め、進められたときだけ投稿する。予約と走査が重なっても、
    # 同じ締切に二度は出さない。積む前に落ちれば取りこぼすが、チャンネルへの
    # 投稿は取りこぼしより重複のほうが困る。
    # 本文を組んでいる間に主催者が日時を動かすと、行を押さえて読み直した締切が変わる。
    # そのときは何もせず次の走査に任せる。組んだ本文と記録する締切が食い違うほうが困る
    def claim(deadline)
      @exchange.with_lock do
        next false unless approaching_deadline == deadline && !reminded?(deadline)

        @exchange.update!(reminded_deadline_at: deadline)
        true
      end
    end

    # 記録するのは締切の時刻そのもの。フェーズ名だと、登録期間のうちに主催者が
    # 締切を先へずらしても「登録期間は出し済み」のまま残り、新しい締切のリマインドが出ない
    def reminded?(deadline)
      @exchange.reminded_deadline_at == deadline
    end

    def message(deadline)
      phase = @exchange.phase(at: @at)

      [
        I18n.t("headline.#{phase}", scope: SCOPE, name: @exchange.name),
        I18n.t("detail.#{phase}", scope: SCOPE),
        deadline_line(deadline),
        # リンクは素の URL を1行で置く。Slack と Discord で記法が割れるが、
        # 素の URL はどちらもリンクになる。ジョブにはリクエストが無いので、
        # ホストは設定から採る（config/initializers/default_url_options.rb）
        Rails.application.routes.url_helpers.exchange_url(@exchange),
      ].join("\n")
    end

    def deadline_line(deadline)
      I18n.t('deadline', scope: SCOPE,
                         name: @exchange.next_deadline_name(at: @at),
                         at: I18n.l(deadline, format: :schedule))
    end
  end
end
