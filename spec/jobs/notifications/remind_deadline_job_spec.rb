# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::RemindDeadlineJob do
  include ActiveJob::TestHelper

  # 登録の締切が12時間後。窓の中にいる
  let!(:exchange) do
    create(:exchange, registration_starts_at: 1.day.ago, registration_ends_at: 12.hours.from_now,
                      wish_ends_at: 3.weeks.from_now)
  end

  before { clear_enqueued_jobs }

  describe '.reserve' do
    # 何時間前に知らせるかはリマインドの都合なので、引き算はジョブが持つ。
    # 交換会はどの締切を持つかだけを答える
    it '締切の24時間前を予約する' do
      deadline = Time.zone.parse('2026-10-01 21:00')

      expect { described_class.reserve(exchange, deadlines: [deadline]) }
        .to have_enqueued_job(described_class).with(exchange).at(deadline - 24.hours)
    end
  end

  it '締切が近ければ投稿を積む' do
    expect { described_class.perform_now(exchange) }
      .to have_enqueued_job(Notifications::DeliverJob).with(exchange, String)
  end

  it '締切がまだ遠ければ何もしない' do
    exchange.update!(registration_ends_at: 5.days.from_now)
    clear_enqueued_jobs

    expect { described_class.perform_now(exchange) }.not_to have_enqueued_job(Notifications::DeliverJob)
  end

  # 予約は数週間先まで残るので、その間に交換会が消えることがある
  it '交換会が消えていたら何もせず終わる' do
    described_class.perform_later(exchange)
    exchange.destroy!

    expect { perform_enqueued_jobs }.not_to raise_error
  end

  # 予約は「この時刻に確認しに来て」という合図でしかない。日時を動かされた古い予約が
  # 残っていても、実行時に導出した締切しか見ないので、間違ったものは出ない
  it '予約した時刻ではなく、走った時刻の締切を見る' do
    exchange.update!(registration_ends_at: 10.days.from_now, wish_ends_at: 20.days.from_now)
    clear_enqueued_jobs

    expect { described_class.perform_now(exchange) }.not_to have_enqueued_job(Notifications::DeliverJob)
    expect(exchange.reload.reminded_deadline_at).to be_nil
  end
end
