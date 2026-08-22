# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::NotifyAllPhaseChangesJob do
  include ActiveJob::TestHelper

  # 登録期間に入ったまま、まだ知らせていない交換会。予約を取りこぼした状態にあたる
  let!(:exchange) do
    create(:exchange, :registration, notified_phase: 'preparing')
  end

  before { clear_enqueued_jobs }

  it '変わり目にある交換会の投稿を積む' do
    expect { described_class.perform_now }
      .to have_enqueued_job(Notifications::DeliverJob).with(exchange, String)
  end

  # 走査の途中で現在時刻を読み直すと、境目にいる交換会を前半と後半で
  # 違うフェーズとして見る
  it '現在時刻を1回だけ読んで渡す' do
    allow(Notifications::PhaseChange).to receive(:deliver_all)

    described_class.perform_now

    expect(Notifications::PhaseChange).to have_received(:deliver_all).with(at: be_within(5.seconds).of(Time.current))
  end

  # 変わり目そのものは予約が拾うので、ここは取りこぼしを拾うだけでよい。頻度を上げると、
  # 空振りの走査を1日に何百回も積むことになる
  it '1日1回の定期実行として登録されている' do
    definitions = YAML.safe_load(ERB.new(Rails.root.join('config/recurring.yml').read).result, aliases: true)

    expect(definitions['production'].values)
      .to include(hash_including('class' => described_class.name, 'schedule' => 'every day at 9am'))
  end
end
