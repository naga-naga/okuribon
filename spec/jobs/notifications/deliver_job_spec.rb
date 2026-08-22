# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::DeliverJob do
  include ActiveJob::TestHelper

  subject(:deliver) { perform_enqueued_jobs { described_class.perform_later(exchange, '登録期間がはじまりました') } }

  let!(:url) { 'https://discord.com/api/webhooks/123456789012345678/token' }
  let!(:exchange) { create(:exchange, webhook_url: url) }

  it '交換会の Webhook へ本文を投稿する' do
    stub_request(:post, url).to_return(status: 204)

    deliver

    expect(a_request(:post, url).with(body: { content: '登録期間がはじまりました' }.to_json)).to have_been_made
  end

  context 'Webhook URL が未設定のとき' do
    let!(:exchange) { create(:exchange, webhook_url: nil) }

    # 通知は任意の設定なので、送り先が無いのは異常ではない。失敗として残さない
    it '何も送らない' do
      expect { deliver }.not_to raise_error
    end
  end

  # 送信の失敗を呼ぶ側へ返さない。1件の Webhook の不調で走査が止まると、
  # 後ろの交換会に通知が届かなくなる
  context '時間をおけば通りうる失敗が続くとき' do
    before { stub_request(:post, url).to_return(status: 500) }

    it '諦めるまで積み直し、例外を投げない' do
      expect { deliver }.not_to raise_error
      expect(a_request(:post, url)).to have_been_made.times(described_class::MAX_ATTEMPTS)
    end

    it '諦めたことをログに残す' do
      allow(Rails.logger).to receive(:error)

      deliver

      expect(Rails.logger).to have_received(:error).with(/#{exchange.id}/)
    end
  end

  context '待っても変わらない失敗のとき' do
    before { stub_request(:post, url).to_return(status: 404) }

    it '積み直さず、例外を投げない' do
      expect { deliver }.not_to raise_error
      expect(a_request(:post, url)).to have_been_made.once
    end

    it '諦めたことをログに残す' do
      allow(Rails.logger).to receive(:error)

      deliver

      expect(Rails.logger).to have_received(:error).with(/#{exchange.id}/)
    end
  end

  # 積んでから実行されるまでの間に交換会が消えることがある。送り先も本文の意味も無い
  context '交換会が消えていたとき' do
    it '何もせず終わる' do
      described_class.perform_later(exchange, '登録期間がはじまりました')
      exchange.destroy!

      expect { perform_enqueued_jobs }.not_to raise_error
    end
  end
end
