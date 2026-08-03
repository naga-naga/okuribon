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
  end
end
