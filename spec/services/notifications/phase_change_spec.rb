# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::PhaseChange do
  include ActiveJob::TestHelper

  # 定期実行が読む時刻。入口で1回だけ読んだものを回す（docs/spec.md 11.）
  let!(:at) { Time.zone.parse('2026-08-16 12:00') }

  let!(:exchange) do
    create(:exchange, name: '夏の交換会',
                      registration_starts_at: Time.zone.parse('2026-08-10 10:00'),
                      registration_ends_at: Time.zone.parse('2026-08-20 21:00'),
                      wish_ends_at: Time.zone.parse('2026-09-01 21:00'),
                      notified_phase: 'preparing')
  end

  def deliver(now = at)
    described_class.new(exchange, at: now).deliver
  end

  # 積まれた本文を読む。DeliveryJob の引数は交換会と本文の2つ
  def delivered_text
    enqueued_jobs.filter_map { it[:args].last if it[:job] == Notifications::DeliveryJob }.last
  end

  it 'フェーズが変わったら、その交換会宛に投稿を積む' do
    expect { deliver }.to have_enqueued_job(Notifications::DeliveryJob).with(exchange, String)
  end

  it '知らせたフェーズを記録する' do
    deliver

    expect(exchange.reload.notified_phase).to eq('registration')
  end

  it '同じフェーズのまま走らせても、二度は積まない' do
    deliver

    expect { deliver }.not_to have_enqueued_job(Notifications::DeliveryJob)
  end

  describe '本文' do
    before { deliver }

    it '交換会名と新しいフェーズを出す' do
      expect(delivered_text).to include('夏の交換会').and include('登録期間が始まりました')
    end

    it '次の締切を出す' do
      expect(delivered_text).to include('登録の締切').and include('2026年8月20日 21:00')
    end

    it '該当画面へのリンクを出す' do
      expect(delivered_text).to include("http://localhost:3000/exchanges/#{exchange.id}")
    end
  end

  # 定期実行が止まっていた間に登録期間が丸ごと終わっていた、という状況。
  # 締切が過ぎた期間の開始を今さら知らせても、促す行動がもう無い
  context '複数のフェーズをまたいだとき' do
    let!(:crossed) { Time.zone.parse('2026-08-25 12:00') }

    it 'いまのフェーズだけを積む' do
      expect { deliver(crossed) }.to have_enqueued_job(Notifications::DeliveryJob)
        .with(exchange, a_string_including('希望提出期間が始まりました')).once
    end

    it '飛ばしたフェーズは記録にも残さず、いまのフェーズを記録する' do
      deliver(crossed)

      expect(exchange.reload.notified_phase).to eq('wish')
    end
  end

  # リンクのホストが未設定のまま動かした状況（APP_HOST）。記録を先に進めてしまうと、
  # 設定を直してもその交換会の変わり目は二度と出ない
  context '本文を組めないとき' do
    before { allow(Rails.application.routes).to receive(:default_url_options).and_return({}) }

    it '記録を進めず、次の走査でやり直せる状態で落ちる' do
      expect { deliver }.to raise_error(ArgumentError, /host/)

      expect(exchange.reload.notified_phase).to eq('preparing')
    end
  end

  # 交換会が作られた直後の状態にあたる。始まりを知らせる変わり目ではない
  context '準備中のとき' do
    let!(:exchange) do
      create(:exchange, registration_starts_at: Time.zone.parse('2026-08-20 10:00'),
                        registration_ends_at: Time.zone.parse('2026-08-30 21:00'),
                        wish_ends_at: Time.zone.parse('2026-09-10 21:00'),
                        notified_phase: nil)
    end

    it '何も積まない' do
      expect { deliver }.not_to have_enqueued_job(Notifications::DeliveryJob)
    end

    it '記録だけ進める' do
      deliver

      expect(exchange.reload.notified_phase).to eq('preparing')
    end
  end

  context 'マッチング実行待ちのとき' do
    let!(:at) { Time.zone.parse('2026-09-02 12:00') }

    before { deliver }

    it '主催者の実行を待っていることを出す' do
      expect(delivered_text).to include('希望の提出を締め切りました')
    end

    # 待っているのは主催者の操作で、日時では動かない（docs/spec.md 4.）
    it '締切を出さない' do
      expect(delivered_text).not_to include('締切:')
    end
  end

  context '結果公開のとき' do
    let!(:exchange) do
      create(:exchange, name: '夏の交換会', matched_at: Time.zone.parse('2026-08-16 11:00'),
                        notified_phase: 'awaiting_matching')
    end

    before { deliver }

    it '公開したことを出す' do
      expect(delivered_text).to include('結果を公開しました')
    end

    it '結果画面へのリンクを出す' do
      expect(delivered_text).to include("http://localhost:3000/exchanges/#{exchange.id}/result")
    end
  end

  # 通知はチャンネルへの投稿で、誰が読むかを選べない（docs/spec.md 8.）
  describe '載せないもの' do
    let!(:exchange) do
      create(:exchange, name: '夏の交換会', matched_at: Time.zone.parse('2026-08-16 11:00'),
                        notified_phase: 'awaiting_matching')
    end
    let!(:book) do
      create(:book, participation: exchange.participations.first,
                    title: '沈黙のはじまり', gift_code: 'GIFTCODE12345678')
    end

    before { deliver }

    it 'ギフトコードを含まない' do
      expect(delivered_text).not_to include('GIFTCODE12345678')
    end

    it '本の題名を含まない' do
      expect(delivered_text).not_to include(book.title)
    end
  end

  describe '.deliver_all' do
    # 変わり目に無い交換会。走査が全件を見ても、積むのは変わったものだけ
    let!(:unchanged) do
      create(:exchange, registration_starts_at: Time.zone.parse('2026-08-10 10:00'),
                        registration_ends_at: Time.zone.parse('2026-08-20 21:00'),
                        wish_ends_at: Time.zone.parse('2026-09-01 21:00'),
                        notified_phase: 'registration')
    end

    it '交換会を順に見て、変わり目にあるものだけを積む' do
      expect { described_class.deliver_all(at:) }
        .to have_enqueued_job(Notifications::DeliveryJob).with(exchange, String).once

      expect(enqueued_jobs.count { it[:job] == Notifications::DeliveryJob }).to eq(1)
      expect(unchanged.reload.notified_phase).to eq('registration')
    end
  end
end
