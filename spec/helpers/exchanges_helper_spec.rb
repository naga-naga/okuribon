# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExchangesHelper do
  describe '#remaining_time_text' do
    let!(:at) { '2026-08-04T00:00:00+09:00'.in_time_zone }

    def text(deadline)
      helper.remaining_time_text(deadline, at:)
    end

    # 数週間にわたって待つツールなので、遠い締切は日数で足りる。
    # 端数は切り捨てる。切り上げると、あと1日を切ってから「あと1日」と出て
    # 締切が近づいているのに表示が変わらない
    it '1日以上あれば日数で出す' do
      expect(text(at + 3.days + 5.hours)).to eq('あと3日')
    end

    it 'ちょうど1日なら日数で出す' do
      expect(text(at + 1.day)).to eq('あと1日')
    end

    # 締切当日に「あと0日」と出ても、今日中なのか分からない。
    # 1日を割ったところで時間単位へ切り替える
    it '1日に満たなければ時間で出す' do
      expect(text(at + 1.day - 1.second)).to eq('あと23時間')
    end

    it 'ちょうど1時間なら時間で出す' do
      expect(text(at + 1.hour)).to eq('あと1時間')
    end

    # 「あと0時間」では、まだ余裕があるのか切迫しているのか読み取れない
    it '1時間に満たなければ分で出す' do
      expect(text(at + 1.hour - 1.second)).to eq('あと59分')
    end

    it 'ちょうど1分なら分で出す' do
      expect(text(at + 1.minute)).to eq('あと1分')
    end

    # 秒まで出すと数字が毎秒変わるように見えるが、画面は更新されない。
    # 数えられる単位が尽きたら、残りを数えずに切迫だけを伝える
    it '1分に満たなければ数えずに知らせる' do
      expect(text(at + 59.seconds)).to eq('まもなく')
    end

    # 締切を過ぎた瞬間にフェーズが変わり、次の締切は別の日時になる。
    # 過ぎた日時を渡されるのは呼ぶ側の誤りなので、負の残りを描いて隠さない
    it '締切ちょうどでも数えない' do
      expect(text(at)).to eq('まもなく')
    end

    # 「あと-3日」や「あと-4320分」を描くと、誤った呼び出しが画面で
    # それらしく見えてしまい、気付ける機会がなくなる
    it '締切を過ぎていても数えない' do
      expect(text(at - 3.days)).to eq('まもなく')
    end

    # 単位ごとに符号の扱いが分かれていないこと。日をまたがない過ぎ方でも同じ
    it '締切を1秒過ぎていても数えない' do
      expect(text(at - 1.second)).to eq('まもなく')
    end
  end

  describe '#elapsed_time_text' do
    let!(:at) { '2026-08-04T00:00:00+09:00'.in_time_zone }

    def text(since)
      helper.elapsed_time_text(since, at:)
    end

    # 単位の選び方は残り時間と揃える。押し忘れが何日続いているのかを
    # 掴めればよく、日と時間を併記しても切迫度は変わらない
    it '1日以上経っていれば日数で出す' do
      expect(text(at - 3.days - 5.hours)).to eq('3日')
    end

    it '1日に満たなければ時間で出す' do
      expect(text(at - 14.hours)).to eq('14時間')
    end

    it '1時間に満たなければ分で出す' do
      expect(text(at - 59.minutes)).to eq('59分')
    end

    # 「0分」と出すと、まだ何も起きていないようにも読める。
    # 締切を過ぎたことだけは伝わる言い方にする
    it '1分に満たなければ数えずに知らせる' do
      expect(text(at - 59.seconds)).to eq('1分未満')
    end

    it '締切ちょうどなら数えない' do
      expect(text(at)).to eq('1分未満')
    end

    # 締切前に呼ぶのは呼ぶ側の誤り。「-3日」を描くと、
    # それらしく見えて気付ける機会がなくなる
    it '締切前でも数えない' do
      expect(text(at + 3.days)).to eq('1分未満')
    end
  end

  # 交換会一覧のカードの描き分け。
  # 一覧の中で1枚だけが目を引くように、今日中に迫ったものだけを朱の面にする
  describe '#exchange_card_tone' do
    let!(:at) { '2026-08-04T00:00:00+09:00'.in_time_zone }

    def tone(**attributes)
      helper.exchange_card_tone(build(:exchange, **attributes), at:)
    end

    def registration(**attributes)
      { registration_starts_at: at - 3.days, registration_ends_at: at + 6.days,
        wish_ends_at: at + 13.days, **attributes }
    end

    it '締切まで24時間を切っていれば朱の面にする' do
      expect(tone(**registration(registration_ends_at: at + 4.hours))).to eq(:urgent)
    end

    # 境目はどちらかに倒す。ちょうど24時間はまだ今日中ではない
    it 'ちょうど24時間なら朱の文字にする' do
      expect(tone(**registration(registration_ends_at: at + 1.day))).to eq(:soon)
    end

    it '数日先なら朱の文字にする' do
      expect(tone(**registration)).to eq(:soon)
    end

    # 待っているのは締切ではなく開始で、急いでも早められない。
    # 残りが短くても、一覧の中で目を引かせる用がない
    it '準備中は開始が迫っていても生成りにする' do
      expect(tone(registration_starts_at: at + 4.hours, registration_ends_at: at + 7.days,
                  wish_ends_at: at + 14.days)).to eq(:quiet)
    end

    it 'マッチング実行待ちは生成りにする' do
      expect(tone(registration_starts_at: at - 20.days, registration_ends_at: at - 10.days,
                  wish_ends_at: at - 3.days)).to eq(:idle)
    end

    # 松葉は成立と完了の担当
    it '結果公開は松葉にする' do
      expect(tone(**registration(matched_at: at - 1.day))).to eq(:done)
    end
  end
end
