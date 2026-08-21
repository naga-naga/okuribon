# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::DeadlineReminder do
  include ActiveJob::TestHelper

  # 登録の締切（2026-08-20 21:00）の9時間前。ウィンドウの中にいる
  let!(:at) { Time.zone.parse('2026-08-20 12:00') }

  let!(:exchange) do
    create(:exchange, name: '夏の交換会',
                      registration_starts_at: Time.zone.parse('2026-08-10 10:00'),
                      registration_ends_at: Time.zone.parse('2026-08-20 21:00'),
                      wish_ends_at: Time.zone.parse('2026-09-01 21:00'))
  end

  # 交換会の保存そのものが予約を積む。ここで見たいのは投稿のほうだけ
  before { clear_enqueued_jobs }

  def deliver(now = at)
    described_class.new(exchange, at: now).deliver
  end

  # 積まれた本文を読む。DeliverJob の引数は交換会と本文の2つ
  def delivered_text
    enqueued_jobs.filter_map { it[:args].last if it[:job] == Notifications::DeliverJob }.last
  end

  it '締切が近ければ、その交換会宛に投稿を積む' do
    expect { deliver }.to have_enqueued_job(Notifications::DeliverJob).with(exchange, String)
  end

  it '出した締切を記録する' do
    deliver

    expect(exchange.reload.reminded_deadline_at).to eq(exchange.registration_ends_at)
  end

  it '同じ締切に対して二度は積まない' do
    deliver

    expect { deliver }.not_to have_enqueued_job(Notifications::DeliverJob)
  end

  # ウィンドウは24時間ちょうど。走査が1日1回なので、これより短くすると
  # 予約を取りこぼした日に走査がウィンドウの中へ落ちない
  it 'ちょうど24時間前はウィンドウの中に入る' do
    expect { deliver(Time.zone.parse('2026-08-19 21:00')) }
      .to have_enqueued_job(Notifications::DeliverJob)
  end

  it '24時間前に達していなければ積まない' do
    expect { deliver(Time.zone.parse('2026-08-19 20:59')) }
      .not_to have_enqueued_job(Notifications::DeliverJob)
  end

  # 記録がフェーズ名だと、動かしたあとも「登録期間は出し済み」のまま残り、
  # 新しい締切のリマインドが出ない
  context '主催者が締切を動かしたとき' do
    before do
      deliver
      exchange.update!(registration_ends_at: Time.zone.parse('2026-08-27 21:00'))
      clear_enqueued_jobs
    end

    it '動かしたあとの締切に対して改めて積む' do
      expect { deliver(Time.zone.parse('2026-08-27 12:00')) }
        .to have_enqueued_job(Notifications::DeliverJob)
    end
  end

  context '希望提出の締切が近いとき' do
    let!(:at) { Time.zone.parse('2026-09-01 12:00') }

    before { deliver }

    it '希望提出の締切として出す' do
      expect(delivered_text).to include('希望提出').and include('2026年9月1日 21:00')
    end

    it '希望提出の締切を記録する' do
      expect(exchange.reload.reminded_deadline_at).to eq(exchange.wish_ends_at)
    end
  end

  # 準備中が待っているのは締切ではなく登録期間の開始で、まだ促す行動が無い。
  # Exchange#next_deadline は準備中にも日時を返すので、フェーズで明示的に絞る
  context '準備中のとき' do
    let!(:at) { Time.zone.parse('2026-08-09 12:00') }

    it '開始の24時間前を切っていても積まない' do
      expect { deliver }.not_to have_enqueued_job(Notifications::DeliverJob)
    end

    it '記録も進めない' do
      deliver

      expect(exchange.reload.reminded_deadline_at).to be_nil
    end
  end

  # 待っているのが主催者の操作で、日時では動かない
  context 'マッチング実行待ちのとき' do
    let!(:at) { Time.zone.parse('2026-09-02 12:00') }

    it '積まない' do
      expect { deliver }.not_to have_enqueued_job(Notifications::DeliverJob)
    end
  end

  context '結果公開のとき' do
    let!(:exchange) do
      create(:exchange, registration_starts_at: Time.zone.parse('2026-08-10 10:00'),
                        registration_ends_at: Time.zone.parse('2026-08-20 21:00'),
                        wish_ends_at: Time.zone.parse('2026-09-01 21:00'),
                        matched_at: Time.zone.parse('2026-08-19 11:00'))
    end

    it '積まない' do
      expect { deliver }.not_to have_enqueued_job(Notifications::DeliverJob)
    end
  end

  describe '本文' do
    before { deliver }

    it '交換会名と締切が近いことを出す' do
      expect(delivered_text).to include('夏の交換会').and include('締切が近づいています')
    end

    it '締切を出す' do
      expect(delivered_text).to include('登録の締切').and include('2026年8月20日 21:00')
    end

    it '交換会ページへのリンクを出す' do
      expect(delivered_text).to include("http://localhost:3000/exchanges/#{exchange.id}")
    end
  end

  # 出すかどうかも本文も、交換会の日時だけから決める。誰が登録したか、誰が希望を
  # 出したかは見ない。あとから「まだの人が3人います」を足そうとしたときに止める
  describe '参加者の状態' do
    let!(:latecomer) { create(:user, display_name: '佐藤花子') }

    before { deliver }

    it '参加者の名前を含まない' do
      expect(delivered_text).not_to include(exchange.owner.display_name)
    end

    it '参加者が増えても本文が変わらない' do
      first_text = delivered_text

      book = create(:book, participation: exchange.participations.create!(user: latecomer))
      exchange.update!(reminded_deadline_at: nil)
      clear_enqueued_jobs
      deliver

      expect(delivered_text).to eq(first_text)
      expect(delivered_text).not_to include(book.title)
    end
  end

  # リンクのホストが未設定のまま動かした状況（APP_HOST）。記録を先に進めてしまうと、
  # 設定を直してもその締切のリマインドは二度と出ない
  context '本文を組めないとき' do
    before { allow(Rails.application.routes).to receive(:default_url_options).and_return({}) }

    it '記録を進めず、次の走査でやり直せる状態で落ちる' do
      expect { deliver }.to raise_error(ArgumentError, /host/)

      expect(exchange.reload.reminded_deadline_at).to be_nil
    end
  end

  describe '.deliver_all' do
    # 締切がまだ遠い交換会。走査が全件を見ても、積むのはウィンドウの中にあるものだけ
    let!(:far) do
      create(:exchange, registration_starts_at: Time.zone.parse('2026-08-10 10:00'),
                        registration_ends_at: Time.zone.parse('2026-09-10 21:00'),
                        wish_ends_at: Time.zone.parse('2026-09-20 21:00'))
    end

    before { clear_enqueued_jobs }

    it '交換会を順に見て、締切が近いものだけを積む' do
      expect { described_class.deliver_all(at:) }
        .to have_enqueued_job(Notifications::DeliverJob).with(exchange, String).once

      expect(enqueued_jobs.count { it[:job] == Notifications::DeliverJob }).to eq(1)
      expect(far.reload.reminded_deadline_at).to be_nil
    end
  end
end
