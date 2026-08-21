# frozen_string_literal: true

module ExchangesHelper
  # 大きいほうから順に、最初に1つ以上たまる単位で出す。
  # 「3日と5時間」のように併記しない。ざっと見て切迫度だけ掴めればよく、
  # 桁を増やすと、久しぶりに開いた人が読み解く手間が増える
  DURATION_UNITS = [[1.day.to_i, '日'], [1.hour.to_i, '時間'], [1.minute.to_i, '分']].freeze

  # 「あなたがすること」の描き分け。朱＝押すものと締切、松葉＝成立と完了なので、
  # 放っておくと受け取れる本が減る状態だけを朱の面で塗る。
  # 面が濃いと墨の濃淡が読めなくなるため、文字の色まで組で持つ。
  # 結果公開は状態ヘッダーごと松葉の面になるので（HEADER_STYLES）、ここでは面を持たない
  TODO_TONE_STYLES = {
    normal: { panel: '', eyebrow: 'text-ink-subtle',
              headline: 'text-ink', detail: 'text-ink-muted' },
    urgent: { panel: 'border border-accent bg-accent px-5 py-5', eyebrow: 'text-accent-soft',
              headline: 'text-paper', detail: 'text-accent-soft' },
    done: { panel: '', eyebrow: 'text-success-soft',
            headline: 'text-paper', detail: 'text-success-mute' },
  }.freeze

  # 状態ヘッダーの地と、その上に載る締切・状況の数字。
  # 結果公開だけ面ごと松葉に変わり、そのまま結果への入口になる。
  # 地が濃い側では墨の濃淡が読めないので、罫と文字の色まで組で持つ
  HEADER_STYLES = {
    paper: { face: 'bg-paper', rule: 'border-line', label: 'text-ink-subtle', value: 'text-ink' },
    success: { face: 'bg-success', rule: 'border-success-hover',
               label: 'text-success-soft', value: 'text-paper' },
  }.freeze

  # 締切を朱の面で急かす範囲。今日中に手を動かさないと間に合わない長さにする。
  # 一覧に何枚並んでも、朱の面になるのはこの範囲に入ったものだけなので、
  # ざっと見て1枚だけが目に飛び込む
  CARD_URGENT_WITHIN = 1.day

  # 交換会一覧のカードの描き分け。
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

  # 「あなたがすること」の直下に置く操作の見た目。
  # 行き先はフェーズごとに違うが、どれもそのフェーズの主となる導線にあたるので、
  # 位置も大きさも分けず、文言と行き先だけを差し替える。
  # 朱は1画面に1箇所だけなので、「あなたがすること」を朱で塗ったときは
  # こちらを輪郭だけに落とす
  def exchange_todo_action_class(tone)
    emphasis = if tone == :urgent
                 'border border-accent bg-paper text-accent hover:bg-paper-hover'
               else
                 'bg-accent text-paper hover:bg-accent-hover'
               end

    "inline-block rounded-[5px] px-6 py-3 text-[14px] font-medium no-underline #{emphasis}"
  end

  def exchange_card_style(tone, part)
    CARD_TONE_STYLES.fetch(tone).fetch(part)
  end

  def exchange_header_style(published, part)
    HEADER_STYLES.fetch(published ? :success : :paper).fetch(part)
  end

  # 状態ヘッダーに並べる3つの数字。
  # 枠の位置は動かさず、中身だけをフェーズで入れ替える。
  # 参加人数を出すのは登録期間まで。それより後は登録の締切が過ぎており、
  # まだ登録していない人が何人残っているかを数える用が無い。
  # 代わりに自分の希望の冊数を出す。取得枠に対して足りているかが、その時期に
  # いちばん確かめたい数になる。
  #
  # 数は呼ぶ側が読み込み済みのものを渡す。ここで数え直すと、絞り込んだ一覧の
  # 冊数と交換会全体の冊数が混ざる。
  # @return [Array<Array(String, String)>] ラベルと値の組を3つ
  def exchange_stats(phase, participants:, books:, slots:, wishes:, returned:)
    case phase
    # まだ登録が始まっていないだけで、受け取れないわけではない。
    # 取得枠に0冊と書くと、締め出されているようにも読める
    when :preparing then [['参加者', "#{participants}人"], ['本', "#{books}冊"], ['取得枠', '—']]
    when :registration then [['参加者', "#{participants}人"], ['本', "#{books}冊"], ['取得枠', "#{slots}冊"]]
    when :wish then [['本', "#{books}冊"], ['取得枠', "#{slots}冊"], ['希望', "#{wishes}冊"]]
    when :awaiting_matching then [['本', "#{books}冊"], ['取得枠', "#{slots}冊"], ['提出した希望', "#{wishes}冊"]]
    # 結果が出たあとに数えるのは、何冊が渡って何冊が戻ったか。
    # 一覧の見出しは冊数しか言わないので、内訳はここが引き受ける
    else [['本', "#{books}冊"], ['成立', "#{books - returned}冊"], ['返却', "#{returned}冊"]]
    end
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

  # 自分が主催なら名前ではなく「あなた」と書く。
  # 自分の名前を出しても、誰のことか読み替える手間が増えるだけ
  def exchange_owner_name(exchange, viewer)
    exchange.owner?(viewer) ? 'あなた' : exchange.owner.display_name
  end

  # 基準時刻は呼ぶ側から渡す。ここで現在時刻を読むと、
  # 同じ画面に並んだフェーズと残り時間が別々の時刻を指しうる
  def remaining_time_text(deadline, at:)
    counted = duration_text(deadline - at)

    # 分すら数えられないほど近いときは、残りを数えずに切迫だけ伝える。
    # 秒は毎秒変わるのに画面は更新されず、止まった数字を見せることになる
    return 'まもなく' if counted.nil?

    "あと#{counted}"
  end

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
