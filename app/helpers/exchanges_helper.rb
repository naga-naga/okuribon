# frozen_string_literal: true

module ExchangesHelper
  # 残りを数える単位。大きいほうから順に、最初に1つ以上たまる単位で出す。
  # 「3日と5時間」のように併記しない。ざっと見て切迫度だけ掴めればよく、
  # 桁を増やすと、久しぶりに開いた人が読み解く手間が増える
  REMAINING_UNITS = [[1.day.to_i, '日'], [1.hour.to_i, '時間'], [1.minute.to_i, '分']].freeze

  # 締切までの残り。基準時刻は呼ぶ側から渡す。ここで現在時刻を読むと、
  # 同じ画面に並んだフェーズと残り時間が別々の時刻を指しうる。
  # 端数は切り捨てる。切り上げると、1日を切ってからも「あと1日」と出続けて、
  # 締切が近づいていることが表示に現れない
  def remaining_time_text(deadline, at:)
    remaining = (deadline - at).to_i
    unit, name = REMAINING_UNITS.find { |seconds, _| remaining >= seconds }

    # 分すら数えられないほど近いときは、残りを数えずに切迫だけ伝える。
    # 秒は毎秒変わるのに画面は更新されず、止まった数字を見せることになる
    return 'まもなく' if unit.nil?

    "あと#{remaining / unit}#{name}"
  end
end
