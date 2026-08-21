# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::RemindAllDeadlinesJob do
  include ActiveJob::TestHelper

  # 登録の締切が12時間後。予約を取りこぼした状態にあたる
  let!(:exchange) do
    create(:exchange, registration_starts_at: 1.day.ago, registration_ends_at: 12.hours.from_now,
                      wish_ends_at: 3.weeks.from_now)
  end

  before { clear_enqueued_jobs }

  it '締切が近い交換会の投稿を積む' do
    expect { described_class.perform_now }
      .to have_enqueued_job(Notifications::DeliverJob).with(exchange, String)
  end

  # 走査の途中で現在時刻を読み直すと、窓の縁にいる交換会を前半と後半で
  # 違う扱いにする
  it '現在時刻を1回だけ読んで渡す' do
    allow(Notifications::DeadlineReminder).to receive(:deliver_all)

    described_class.perform_now

    expect(Notifications::DeadlineReminder)
      .to have_received(:deliver_all).with(at: be_within(5.seconds).of(Time.current))
  end

  # 窓が24時間ちょうどなので、1日1回の走査が必ず1回だけ窓の中に入る。
  # 間隔を空けると、予約を取りこぼした締切が一度も窓に入らないまま過ぎる
  it '1日1回の定期実行として登録されている' do
    definitions = YAML.safe_load(ERB.new(Rails.root.join('config/recurring.yml').read).result, aliases: true)

    expect(definitions['production'].values)
      .to include(hash_including('class' => described_class.name, 'schedule' => 'every day at 9am'))
  end
end
