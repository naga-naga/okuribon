# frozen_string_literal: true

module WishesHelper
  # 推奨する希望冊数は取得枠の何倍か（docs/spec.md 3.）。
  # 上位が他の人に取られると下位へ降りていくので、取得枠と同数では足りない
  RECOMMENDED_WISHES_PER_SLOT = 2

  # 希望リストに添える案内の出し分け。文言そのものはロケールに置く。
  # 3つに分けるのは、取得枠が0の人だけ促しても届かないため。
  # 登録期間はもう終わっているので、その人には増やす道が残っていない
  def wish_guidance_state(slots:, wishes:)
    return :no_slots if slots.zero?

    wishes < recommended_wish_count(slots) ? :short : :enough
  end

  # 畳んだシートに出す1行。開かなくても取得枠と希望冊数だけは読める短さにする。
  # ERB で継ぎ足さずここで組むのは、行を分けたぶんの改行がそのまま空白になり、
  # 区切りの中黒の前に隙間が入るため
  def wish_summary_text(slots:, wishes:)
    state = wish_guidance_state(slots:, wishes:)
    return t('wish.summaries.no_slots') if state == :no_slots

    counts = t('wish.summaries.counts', slots:, wishes:)
    return counts unless state == :short

    "#{counts}・#{t('wish.summaries.shortfall', count: recommended_wish_count(slots) - wishes)}"
  end

  def recommended_wish_count(slots)
    slots * RECOMMENDED_WISHES_PER_SLOT
  end
end
