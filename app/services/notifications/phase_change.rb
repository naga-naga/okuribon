# frozen_string_literal: true

module Notifications
  # フェーズの変わり目をチャンネルへ知らせる。
  #
  # 定期実行が交換会を順に見て、最後に知らせたフェーズ（notified_phase）と
  # いまのフェーズが食い違うものだけを投稿する。
  #
  # 本文に載せるのは交換会名・フェーズ・締切・リンクだけにする。チャンネルへの
  # 投稿は誰が読むかを選べないので、ギフトコードと個人の希望リストは載せられない
  # （docs/spec.md 8.）。送信サービスは渡された本文をそのまま投げるため、
  # 混ぜないのはここの責任にあたる
  class PhaseChange
    # 準備中は入っていない。交換会が作られた直後の状態で、始まりを知らせる
    # 変わり目ではない。記録だけは進めるので、登録期間に入れば1回だけ出る
    NOTIFIABLE_PHASES = [:registration, :wish, :awaiting_matching, :published].freeze

    SCOPE = 'notification.phase_change'

    # 基準時刻は入口で1回だけ読んだものを回す（docs/spec.md 11.）。
    # 走査の途中で読み直すと、境目にいる交換会を前半と後半で違うフェーズとして見る
    def self.deliver_all(at:)
      Exchange.find_each { new(it, at:).deliver }
    end

    def initialize(exchange, at:)
      @exchange = exchange
      @at = at
    end

    def deliver
      phase = @exchange.phase(at: @at)
      return if notified?(phase)

      # 本文を先に組む。組めないまま記録だけ進めると、原因を直しても
      # その交換会の変わり目は二度と出ない。組めなければ落ちて、次の走査に任せる
      text = message(phase) if NOTIFIABLE_PHASES.include?(phase)
      return unless claim(phase)

      Notifications::DeliveryJob.perform_later(@exchange, text) if text
    end

    private

    # 記録を先に進め、進められたときだけ投稿する。走査が前の回と重なっても、
    # 同じフェーズを二度は出さない。積む前に落ちれば取りこぼすが、
    # チャンネルへの投稿は取りこぼしより重複のほうが困る。
    # 飛ばしたフェーズは通らない。いまのフェーズをそのまま記録するので、
    # 定期実行が止まっている間にまたいだ分はここで捨てる。
    # 本文を組んでいる間に主催者が日時を動かすかマッチングを実行すると、
    # 行を押さえて読み直したフェーズが変わる。そのときは何もせず次の走査に任せる。
    # 組んだ本文と記録するフェーズが食い違うほうが困る
    def claim(phase)
      @exchange.with_lock do
        next false unless @exchange.phase(at: @at) == phase && !notified?(phase)

        @exchange.update!(notified_phase: phase)
        true
      end
    end

    def notified?(phase)
      @exchange.notified_phase == phase.to_s
    end

    def message(phase)
      [
        I18n.t("headline.#{phase}", scope: SCOPE, name: @exchange.name),
        I18n.t("detail.#{phase}", scope: SCOPE),
        deadline_line,
        screen_url(phase),
      ].compact.join("\n")
    end

    # 次の締切が無いフェーズがある。マッチング実行待ちが待っているのは主催者の
    # 操作で日時では動かず、結果公開はもう終わっている（docs/spec.md 4.）。
    # 行ごと落とし、締切の名前だけが残った行を出さない
    def deadline_line
      deadline = @exchange.next_deadline(at: @at)
      return nil if deadline.nil?

      I18n.t('deadline', scope: SCOPE,
                         name: @exchange.next_deadline_name(at: @at),
                         at: I18n.l(deadline, format: :schedule))
    end

    # リンクは素の URL を1行で置く。Slack は <url|text>、Discord は [text](url) と
    # 記法が割れるが、素の URL はどちらもリンクになる。送り先ごとに文面を分けずに済む。
    # ジョブにはリクエストが無いので、ホストは設定から採る
    # （config/initializers/default_url_options.rb）
    def screen_url(phase)
      helpers = Rails.application.routes.url_helpers

      phase == :published ? helpers.exchange_result_url(@exchange) : helpers.exchange_url(@exchange)
    end
  end
end
