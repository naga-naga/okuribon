# frozen_string_literal: true

module ExchangesHelper
  # 期間を数える単位。大きいほうから順に、最初に1つ以上たまる単位で出す。
  # 「3日と5時間」のように併記しない。ざっと見て切迫度だけ掴めればよく、
  # 桁を増やすと、久しぶりに開いた人が読み解く手間が増える
  DURATION_UNITS = [[1.day.to_i, '日'], [1.hour.to_i, '時間'], [1.minute.to_i, '分']].freeze

  # 「あなたがすること」の面の描き分け。朱＝押すものと締切、松葉＝成立と完了なので、
  # 放っておくと受け取れる本が減る状態だけを朱で塗り、結果公開を松葉にする。
  # 面が濃いと墨の濃淡が読めなくなるため、文字の色まで組で持つ
  TODO_TONE_STYLES = {
    normal: { panel: 'border-line bg-paper', eyebrow: 'text-ink-subtle',
              headline: 'text-ink', detail: 'text-ink-muted' },
    urgent: { panel: 'border-accent bg-accent', eyebrow: 'text-accent-soft',
              headline: 'text-paper', detail: 'text-accent-soft' },
    done: { panel: 'border-success bg-paper', eyebrow: 'text-success',
            headline: 'text-ink', detail: 'text-ink-muted' },
  }.freeze

  # 締切を朱の面で急かす範囲。今日中に手を動かさないと間に合わない長さにする。
  # 一覧に何枚並んでも、朱の面になるのはこの範囲に入ったものだけなので、
  # ざっと見て1枚だけが目に飛び込む
  CARD_URGENT_WITHIN = 1.day

  # 交換会一覧のカードの描き分け（docs/spec.md 6.6）。
  # 朱＝押すものと締切、松葉＝成立と完了の担当なので、締切が迫ったものを朱、
  # 結果公開を松葉にし、待つだけのものは生成りへ沈める。
  # 面が濃いと墨の濃淡が読めなくなるため、文字の色まで組で持つ
  CARD_TONE_STYLES = {
    urgent: { card: 'border-line bg-paper', badge: 'border border-accent bg-accent text-paper',
              aside: 'bg-accent', label: 'text-accent-soft', value: 'text-paper',
              note: 'text-accent-soft' },
    soon: { card: 'border-line bg-paper', badge: 'border border-accent text-accent',
            aside: 'border-t border-line sm:border-t-0 sm:border-l', label: 'text-ink-subtle',
            value: 'text-accent', note: 'text-ink-muted' },
    quiet: { card: 'border-line bg-surface-sunken', badge: 'border border-fill bg-fill text-ink-subtle',
             aside: 'border-t border-line sm:border-t-0 sm:border-l', label: 'text-ink-subtle',
             value: 'text-ink-muted', note: 'text-ink-subtle' },
    idle: { card: 'border-line bg-paper', badge: 'border border-fill bg-fill text-ink-muted',
            aside: 'border-t border-line sm:border-t-0 sm:border-l', label: 'text-ink-subtle',
            value: 'text-ink-muted', note: 'text-ink-subtle' },
    done: { card: 'border-success bg-paper', badge: 'border border-success bg-success text-paper',
            aside: 'border-t border-line sm:border-t-0 sm:border-l', label: 'text-ink-subtle',
            value: 'text-ink-muted', note: 'text-ink-muted' },
  }.freeze

  # fetch で落として、綴り間違いを黙って既定の見た目に化けさせない
  def exchange_todo_style(tone, part)
    TODO_TONE_STYLES.fetch(tone).fetch(part)
  end

  def exchange_card_style(tone, part)
    CARD_TONE_STYLES.fetch(tone).fetch(part)
  end

  # カード1枚の強さ。締切の近さを3段階で出し分け、待つ日時を持たない
  # フェーズはそれぞれの姿を持つ。基準時刻は呼ぶ側から渡す
  def exchange_card_tone(exchange, at:)
    case exchange.phase(at:)
    when :published then :done
    # 待っているのは主催者の操作で、日時では動かない
    when :awaiting_matching then :idle
    # 待っているのは締切ではなく開始。急いでも早められないので、
    # 開始が迫っていても目を引かせる用がない
    when :preparing then :quiet
    else exchange.next_deadline(at:) - at < CARD_URGENT_WITHIN ? :urgent : :soon
    end
  end

  # 交換会一覧のカードに出す主催者。自分が主催なら名前ではなく「あなた」と書く。
  # 自分の名前を出しても、誰のことか読み替える手間が増えるだけ
  def exchange_owner_name(exchange, viewer)
    exchange.owner?(viewer) ? 'あなた' : exchange.owner.display_name
  end

  # 締切までの残り。基準時刻は呼ぶ側から渡す。ここで現在時刻を読むと、
  # 同じ画面に並んだフェーズと残り時間が別々の時刻を指しうる
  def remaining_time_text(deadline, at:)
    counted = duration_text(deadline - at)

    # 分すら数えられないほど近いときは、残りを数えずに切迫だけ伝える。
    # 秒は毎秒変わるのに画面は更新されず、止まった数字を見せることになる
    return 'まもなく' if counted.nil?

    "あと#{counted}"
  end

  # 締切を過ぎてからの経過。マッチングの押し忘れが何日続いているかを出す。
  # 単位の選び方は残り時間と分け合う。片方だけ端数の扱いが違うと、
  # 同じ交換会の画面に並んだ「あと1日」と「1日」が別の長さを指すことになる
  def elapsed_time_text(since, at:)
    # 「0分」では、まだ何も起きていないようにも読める。
    # 締切前に呼ぶのは呼ぶ側の誤りで、負の経過を描いても気付けない
    duration_text(at - since) || '1分未満'
  end

  private

  # 端数は切り捨てる。切り上げると、1日を切ってからも「1日」と出続けて、
  # 締切に近づいたことが表示に現れない。
  # @return [String, nil] 最小の単位にも満たなければ nil。そのときの言い方は呼ぶ側が決める
  def duration_text(seconds)
    seconds = seconds.to_i
    unit, name = DURATION_UNITS.find { |threshold, _| seconds >= threshold }
    return nil if unit.nil?

    "#{seconds / unit}#{name}"
  end
end
