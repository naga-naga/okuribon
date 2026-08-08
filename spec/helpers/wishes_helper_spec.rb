# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WishesHelper do
  describe '#wish_guidance_state' do
    # 希望リストは長いほうが有利。取得枠の2倍以上を推奨する（docs/spec.md 3.）
    it '取得枠の2倍に満たなければ増やすことを促す' do
      expect(helper.wish_guidance_state(slots: 2, wishes: 3)).to eq(:short)
    end

    it '1冊も選んでいなければ促す' do
      expect(helper.wish_guidance_state(slots: 2, wishes: 0)).to eq(:short)
    end

    # ちょうど2倍は推奨を満たしている。ここを短いほうに寄せると、
    # 推奨どおりに並べ終えた人にまで増やせと出続ける
    it 'ちょうど2倍なら促さない' do
      expect(helper.wish_guidance_state(slots: 2, wishes: 4)).to eq(:enough)
    end

    it '2倍を超えていれば促さない' do
      expect(helper.wish_guidance_state(slots: 2, wishes: 5)).to eq(:enough)
    end

    # 取得枠が0の人は希望を何冊並べても受け取れない。
    # 増やすことを促すと、やれば届くように読める
    it '取得枠が0なら冊数によらず別の状態になる' do
      expect(helper.wish_guidance_state(slots: 0, wishes: 0)).to eq(:no_slots)
      expect(helper.wish_guidance_state(slots: 0, wishes: 3)).to eq(:no_slots)
    end
  end

  # 畳んだシートに出す1行。ここで組み立てるのは、ERB で継ぎ足すと
  # 改行がそのまま空白になり、区切りの前に隙間が入るため
  describe '#wish_summary_text' do
    it '足りなければ不足分を続ける' do
      expect(helper.wish_summary_text(slots: 2, wishes: 3)).to eq('枠2冊／希望3冊・あと1冊推奨')
    end

    it '足りていれば冊数だけを出す' do
      expect(helper.wish_summary_text(slots: 2, wishes: 4)).to eq('枠2冊／希望4冊')
    end

    it '取得枠が0なら受け取れないことだけを出す' do
      expect(helper.wish_summary_text(slots: 0, wishes: 3)).to eq('枠0冊・受け取れません')
    end
  end

  describe '#recommended_wish_count' do
    it '取得枠の2倍を推奨する' do
      expect(helper.recommended_wish_count(3)).to eq(6)
    end
  end
end
