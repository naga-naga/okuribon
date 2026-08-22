# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exchanges::Listing do
  let!(:user) { create(:user) }
  # 締切の前後を突くので、基準時刻を1つ決めて全体で回す
  let!(:at) { Time.zone.parse('2026-02-10 12:00') }

  # 並ぶ条件は参加していること。招待されただけでは並ばない
  def participating(**attributes)
    exchange = create(:exchange, **attributes)
    exchange.participations.create_or_find_by!(user:)
    exchange
  end

  def wish_exchange(**attributes)
    participating(registration_starts_at: Time.zone.parse('2026-01-20 00:00'),
                  registration_ends_at: Time.zone.parse('2026-02-01 00:00'),
                  wish_ends_at: Time.zone.parse('2026-02-10 16:00'),
                  **attributes)
  end

  def registration_exchange(**attributes)
    participating(registration_starts_at: Time.zone.parse('2026-02-05 00:00'),
                  registration_ends_at: Time.zone.parse('2026-02-16 00:00'),
                  wish_ends_at: Time.zone.parse('2026-02-23 00:00'),
                  **attributes)
  end

  def preparing_exchange(**attributes)
    participating(registration_starts_at: Time.zone.parse('2026-02-28 00:00'),
                  registration_ends_at: Time.zone.parse('2026-03-07 00:00'),
                  wish_ends_at: Time.zone.parse('2026-03-14 00:00'),
                  **attributes)
  end

  def awaiting_matching_exchange(**attributes)
    participating(registration_starts_at: Time.zone.parse('2026-01-01 00:00'),
                  registration_ends_at: Time.zone.parse('2026-01-20 00:00'),
                  wish_ends_at: Time.zone.parse('2026-02-05 00:00'),
                  **attributes)
  end

  def cards
    described_class.new(user, at:).call
  end

  def names
    cards.map { it.exchange.name }
  end

  it '参加している交換会だけを並べる' do
    registration_exchange(name: '参加した交換会')
    create(:exchange, name: 'よその交換会')

    expect(names).to eq(['参加した交換会'])
  end

  describe '並び順' do
    it '次の締切が近いものから並ぶ' do
      registration_exchange(name: '6日後が締切')
      wish_exchange(name: '4時間後が締切')

      expect(names).to eq(['4時間後が締切', '6日後が締切'])
    end

    # 準備中が待っているのは締切ではなく開始だが、待つ日時があることは変わらない。
    # 同じ軸に並べる
    it '準備中も登録期間の開始で同じ軸に並ぶ' do
      preparing_exchange(name: '18日後に開始')
      registration_exchange(name: '6日後が締切')

      expect(names).to eq(['6日後が締切', '18日後に開始'])
    end

    # 待つ日時が無いものを日時のあるものと混ぜると、並べる基準が無くなる
    it '次の締切が無いものは、あるものより下に来る' do
      awaiting_matching_exchange(name: '実行待ち')
      preparing_exchange(name: '18日後に開始')

      expect(names).to eq(['18日後に開始', '実行待ち'])
    end

    it '次の締切が無いものどうしは日程の新しい順に並ぶ' do
      awaiting_matching_exchange(name: '古い実行待ち',
                                 registration_starts_at: Time.zone.parse('2025-12-01 00:00'))
      awaiting_matching_exchange(name: '新しい実行待ち')
      registration_exchange(name: '結果公開', matched_at: Time.zone.parse('2026-02-09 00:00'))

      expect(names).to eq(['結果公開', '新しい実行待ち', '古い実行待ち'])
    end
  end

  describe 'カードの中身' do
    it '参加人数が入る' do
      exchange = registration_exchange
      create(:participation, exchange:)

      # 主催者・自分・足した1人で3人
      expect(cards.first.participants_count).to eq(3)
    end

    # 交換会トップと同じ一文を Exchanges::Todo から引く
    it '「あなたがすること」の見出しが入る' do
      registration_exchange

      expect(cards.first.headline).to eq('本を登録する')
    end

    # 見出しは Exchanges::Todo から引くので、主催者かどうかで変わる分もそのまま
    # カードに出る。実行待ちのカードを開く前に、待っている側なのか自分の番なのかが分かる
    it '主催している実行待ちの見出しは、マッチングの実行になる' do
      awaiting_matching_exchange(owner: user)

      expect(cards.first.headline).to eq('マッチングを実行する')
    end

    it '主催していない実行待ちの見出しは、待つことになる' do
      awaiting_matching_exchange

      expect(cards.first.headline).to eq('結果を待ちます')
    end

    it '自分の参加が入る' do
      exchange = registration_exchange

      expect(cards.first.participation).to eq(exchange.participations.find_by!(user:))
    end
  end
end
