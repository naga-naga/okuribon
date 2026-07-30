# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Current do
  describe '.time' do
    it '既定では現在時刻を返す' do
      expect(described_class.time).to be_within(1.second).of(Time.zone.now)
    end

    it 'JST で返る' do
      expect(described_class.time.time_zone.name).to eq('Tokyo')
    end

    it '代入した時刻を返す' do
      fixed = Time.zone.local(2026, 7, 30, 12, 0, 0)
      described_class.time = fixed

      expect(described_class.time).to eq(fixed)
    end

    it 'UTC で代入しても JST で返る' do
      described_class.time = Time.utc(2026, 7, 30, 3, 0, 0)

      expect(described_class.time.time_zone.name).to eq('Tokyo')
      expect(described_class.time).to eq(Time.zone.local(2026, 7, 30, 12, 0, 0))
    end

    it 'travel_to で固定した時刻を返す' do
      fixed = Time.zone.local(2026, 7, 30, 12, 0, 0)

      travel_to(fixed) do
        expect(described_class.time).to eq(fixed)
      end
    end
  end

  # executor は Rails が1リクエストと1ジョブをそれぞれ包む単位。
  # フェーズ判定が前のリクエストの時刻を引きずると、権限判定ごと壊れる。
  describe 'リクエストの境界' do
    it '代入した時刻が次のリクエストへ漏れない' do
      fixed = Time.zone.local(2020, 1, 1)

      Rails.application.executor.wrap { described_class.time = fixed }

      Rails.application.executor.wrap do
        expect(described_class.time).to be_within(1.second).of(Time.zone.now)
      end
    end

    it 'travel_to での固定はリクエストをまたいでも効く' do
      fixed = Time.zone.local(2026, 7, 30, 12, 0, 0)

      travel_to(fixed) do
        Rails.application.executor.wrap do
          expect(described_class.time).to eq(fixed)
        end
      end
    end
  end
end
