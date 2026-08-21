# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::Webhook do
  let!(:discord_url) { 'https://discord.com/api/webhooks/123456789012345678/token' }
  let!(:slack_url) { 'https://hooks.slack.com/services/T00000000/B00000000/token' }

  describe '.for' do
    it 'Discord の URL なら Discord の形式を選ぶ' do
      exchange = build(:exchange, webhook_url: discord_url)

      expect(described_class.for(exchange).format.name).to eq(:discord)
    end

    it 'Slack の URL なら Slack の形式を選ぶ' do
      exchange = build(:exchange, webhook_url: slack_url)

      expect(described_class.for(exchange).format.name).to eq(:slack)
    end

    # 通知は交換会ごとの任意の設定なので、未設定は異常ではない。
    # 呼ぶ側それぞれに URL の有無を書かせないため、ここで nil に落とす
    it 'URL が未設定なら nil を返す' do
      expect(described_class.for(build(:exchange, webhook_url: nil))).to be_nil
    end

    it 'URL が空文字なら nil を返す' do
      expect(described_class.for(build(:exchange, webhook_url: ''))).to be_nil
    end

    it '対応していないホストなら nil を返す' do
      exchange = build(:exchange, webhook_url: 'https://example.com/webhooks/token')

      expect(described_class.for(exchange)).to be_nil
    end

    # URL にはトークンが載る。平文で流れる経路には投げない
    it 'https でなければ nil を返す' do
      exchange = build(:exchange, webhook_url: 'http://discord.com/api/webhooks/1/token')

      expect(described_class.for(exchange)).to be_nil
    end

    it 'URL として読めない文字列なら nil を返す' do
      expect(described_class.for(build(:exchange, webhook_url: 'ほげ'))).to be_nil
    end

    # 開発用データの URL はホストだけ本物にしてある。
    # 形式を手元で見分けられることが、そうしてある理由そのものにあたる
    it '開発用データの URL を見分けられる' do
      formats = [DevelopmentSeeds::DISCORD_WEBHOOK_URL, DevelopmentSeeds::SLACK_WEBHOOK_URL]
                .map { described_class.for(build(:exchange, webhook_url: it))&.format&.name }

      expect(formats).to eq([:discord, :slack])
    end
  end

  describe '#deliver' do
    subject(:deliver) { described_class.for(exchange).deliver('登録期間がはじまりました') }

    let!(:exchange) { build(:exchange, webhook_url: discord_url) }

    context 'Discord のとき' do
      it 'content として投稿する' do
        stub_request(:post, discord_url).to_return(status: 204)

        deliver

        expect(a_request(:post, discord_url)
          .with(body: { content: '登録期間がはじまりました' }.to_json,
                headers: { 'Content-Type' => 'application/json' })).to have_been_made
      end
    end

    context 'Slack のとき' do
      let!(:exchange) { build(:exchange, webhook_url: slack_url) }

      it 'text として投稿する' do
        stub_request(:post, slack_url).to_return(status: 200, body: 'ok')

        deliver

        expect(a_request(:post, slack_url)
          .with(body: { text: '登録期間がはじまりました' }.to_json)).to have_been_made
      end
    end

    # 交換会から本文以外の値を拾わせない。ここで値を足せるようにすると、
    # 文面を組む側が除いたはずのものが送信側で戻ってくる
    it '渡された本文だけを送る' do
      stub_request(:post, discord_url).to_return(status: 204)

      deliver

      expect(a_request(:post, discord_url)
        .with { |request| JSON.parse(request.body).keys == ['content'] }).to have_been_made
    end

    context '相手が失敗を返したとき' do
      it '5xx は時間をおけば通りうるものとして扱う' do
        stub_request(:post, discord_url).to_return(status: 500)

        expect { deliver }.to raise_error(described_class::TransientFailure)
      end

      it '429 は時間をおけば通りうるものとして扱う' do
        stub_request(:post, discord_url).to_return(status: 429)

        expect { deliver }.to raise_error(described_class::TransientFailure)
      end

      # Webhook が消された・失効したなど、待っても変わらないもの
      it '4xx は諦めるものとして扱う' do
        stub_request(:post, discord_url).to_return(status: 404)

        expect { deliver }.to raise_error(described_class::PermanentFailure)
      end

      it 'つながらないときは時間をおけば通りうるものとして扱う' do
        stub_request(:post, discord_url).to_timeout

        expect { deliver }.to raise_error(described_class::TransientFailure)
      end
    end

    # URL にはトークンが載る。例外はログにもジョブの失敗にも残るため、
    # メッセージにホストより先を出さない
    it '失敗のメッセージに URL のトークンを載せない' do
      stub_request(:post, discord_url).to_return(status: 404)

      expect { deliver }.to raise_error(described_class::PermanentFailure) do |error|
        expect(error.message).not_to include('token')
      end
    end
  end
end
