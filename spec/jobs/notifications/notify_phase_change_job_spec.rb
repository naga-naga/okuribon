# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::NotifyPhaseChangeJob do
  include ActiveJob::TestHelper

  # 登録期間に入ったまま、まだ知らせていない交換会
  let!(:exchange) do
    create(:exchange, :registration, notified_phase: 'preparing')
  end

  before { clear_enqueued_jobs }

  it '変わり目に来ていれば投稿を積む' do
    expect { described_class.perform_now(exchange) }
      .to have_enqueued_job(Notifications::DeliverJob).with(exchange, String)
  end

  it '変わり目に来ていなければ何もしない' do
    exchange.update!(notified_phase: 'registration')

    expect { described_class.perform_now(exchange) }.not_to have_enqueued_job(Notifications::DeliverJob)
  end

  # 予約は数週間先まで残るので、その間に交換会が消えることがある
  it '交換会が消えていたら何もせず終わる' do
    described_class.perform_later(exchange)
    exchange.destroy!

    expect { perform_enqueued_jobs }.not_to raise_error
  end

  # 予約は「この時刻に確認しに来て」という合図でしかない。日時を動かされた古い予約が
  # 残っていても、実行時に導出したフェーズしか出さないので、間違ったものは出ない
  it '予約した時刻ではなく、走った時刻のフェーズを見る' do
    exchange.update!(registration_starts_at: 1.hour.from_now,
                     registration_ends_at: 2.days.from_now,
                     wish_ends_at: 3.days.from_now)
    clear_enqueued_jobs

    expect { described_class.perform_now(exchange) }.not_to have_enqueued_job(Notifications::DeliverJob)
    expect(exchange.reload.notified_phase).to eq('preparing')
  end
end
