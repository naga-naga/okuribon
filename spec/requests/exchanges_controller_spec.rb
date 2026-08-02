# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExchangesController do
  let!(:user) { create(:user) }

  let!(:attributes) do
    {
      name: '夏の交換会',
      description: 'Kindle のみ。1000円前後を目安に。',
      webhook_url: 'https://discord.com/api/webhooks/1/abc',
      registration_starts_at: '2026-08-10T10:00',
      registration_ends_at: '2026-08-24T10:00',
      wish_ends_at: '2026-09-07T10:00',
    }
  end

  before { log_in_as(user) }

  describe '#new' do
    it '開ける' do
      get '/exchanges/new'

      expect(response).to have_http_status(:ok)
    end

    it 'ログインしていなければログイン画面へ送る' do
      log_out

      get '/exchanges/new'

      expect(response).to redirect_to(login_path)
    end

    describe '日時の入力欄' do
      before { get '/exchanges/new' }

      it '3つある' do
        expect(response.body.scan('type="datetime-local"').size).to eq(3)
      end

      # 希望提出期間の開始はカラムが無く registration_ends_at から導出する。
      # 入力欄を置くと、送られた値で上書きできるように見えてしまう
      it '希望提出期間の開始を送らせない' do
        expect(response.body).not_to include('wish_starts_at')
      end

      it '登録の締切が希望提出期間の開始も兼ねることが分かる' do
        expect(response.body).to include('登録の締切が、そのまま希望提出期間の始まりになります')
      end
    end
  end

  describe '#create' do
    it '交換会ができる' do
      expect { post '/exchanges', params: { exchange: attributes } }.to change(Exchange, :count).by(1)

      expect(Exchange.last).to have_attributes(
        name: '夏の交換会',
        description: 'Kindle のみ。1000円前後を目安に。',
        webhook_url: 'https://discord.com/api/webhooks/1/abc'
      )
    end

    it '作成した人が主催者になる' do
      post '/exchanges', params: { exchange: attributes }

      expect(Exchange.last.owner).to eq(user)
    end

    # 主催者を送れると、他人の名前で交換会を作れてしまう
    it '主催者を送りつけても無視する' do
      other = create(:user)

      post '/exchanges', params: { exchange: attributes.merge(owner_id: other.id) }

      expect(Exchange.last.owner).to eq(user)
    end

    it '日時を JST として受け取る' do
      post '/exchanges', params: { exchange: attributes }

      expect(Exchange.last.registration_starts_at).to eq(Time.zone.parse('2026-08-10 10:00'))
    end

    # 交換会トップ（#19）が入るまでの暫定。入ったらそちらへ移す
    it '編集画面へ送る' do
      post '/exchanges', params: { exchange: attributes }

      expect(response).to redirect_to(edit_exchange_path(Exchange.last))
    end

    it '作成できたことを知らせる' do
      post '/exchanges', params: { exchange: attributes }

      follow_redirect!

      expect(response.body).to include('交換会を作成しました')
    end

    it 'ログインしていなければ作成できない' do
      log_out

      expect { post '/exchanges', params: { exchange: attributes } }.not_to change(Exchange, :count)
    end

    describe '入力の不備' do
      it '登録の締切が開始より前だと作られない' do
        invalid = attributes.merge(registration_ends_at: '2026-08-01T10:00')

        expect { post '/exchanges', params: { exchange: invalid } }.not_to change(Exchange, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('登録期間の終了日時は開始日時より後にしてください')
      end

      # 希望提出期間の開始は登録の締切そのもの。同時刻だと期間の幅が無くなる
      it '希望提出の締切が登録の締切と同時刻だと作られない' do
        invalid = attributes.merge(wish_ends_at: attributes[:registration_ends_at])

        expect { post '/exchanges', params: { exchange: invalid } }.not_to change(Exchange, :count)

        expect(response.body).to include('希望提出期間の終了日時は開始日時より後にしてください')
      end

      it '交換会名が空だと作られない' do
        expect { post '/exchanges', params: { exchange: attributes.merge(name: '') } }
          .not_to change(Exchange, :count)

        expect(response.body).to include('交換会名を入力してください')
      end

      # 差し戻したフォームに入力が残らないと、全部打ち直しになる
      it '差し戻したフォームに入力が残る' do
        post '/exchanges', params: { exchange: attributes.merge(registration_ends_at: '2026-08-01T10:00') }

        expect(response.body).to include('夏の交換会')
      end
    end
  end

  # 状態カラムを持たないので、作った日時がそのままフェーズになる。
  # 送った日時を JST として読み違えると、作った直後から1つずれる
  describe '作成直後のフェーズ' do
    # 日時は入力欄と同じ形式で送る。境界そのものは spec/models/exchange_spec.rb が持つ
    [
      ['登録期間の開始前なら準備中', '2026-08-09 23:59', :preparing],
      ['登録期間の開始ちょうどなら登録期間', '2026-08-10 10:00', :registration],
      ['登録の締切ちょうどなら希望提出期間', '2026-08-24 10:00', :wish],
      ['希望提出の締切ちょうどならマッチング実行待ち', '2026-09-07 10:00', :awaiting_matching],
    ].each do |description, now, phase|
      it description do
        travel_to Time.zone.parse(now) do
          post '/exchanges', params: { exchange: attributes }

          expect(Exchange.last.phase(at: Time.current)).to eq(phase)
        end
      end
    end

    it '編集画面に現在のフェーズを出す' do
      travel_to Time.zone.parse('2026-08-15 10:00') do
        post '/exchanges', params: { exchange: attributes }

        follow_redirect!

        expect(response.body).to include('現在は登録期間です')
      end
    end
  end

  describe '#edit' do
    let!(:exchange) { create(:exchange, owner: user, name: '春の交換会') }

    it '主催者は開ける' do
      get edit_exchange_path(exchange)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('春の交換会')
    end

    # UTC で描かれると9時間ずれた値が既定で入り、開くたびに日程が巻き戻る
    it '日時の入力欄に JST の値が入る' do
      dated = create(:exchange, owner: user,
                                registration_starts_at: Time.zone.parse('2026-08-10 10:00'),
                                registration_ends_at: Time.zone.parse('2026-08-24 10:00'),
                                wish_ends_at: Time.zone.parse('2026-09-07 10:00'))

      get edit_exchange_path(dated)

      expect(response.body).to include('value="2026-08-10T10:00:00"')
    end

    # 403 だと、招待されていない交換会の実在が漏れる
    it '主催者以外には見つからない' do
      log_in_as(create(:user))

      get edit_exchange_path(exchange)

      expect(response).to have_http_status(:not_found)
    end

    it 'ログインしていなければログイン画面へ送る' do
      log_out

      get edit_exchange_path(exchange)

      expect(response).to redirect_to(login_path)
    end
  end

  describe '#update' do
    let!(:exchange) { create(:exchange, owner: user, name: '春の交換会') }

    it '主催者は変更できる' do
      patch exchange_path(exchange), params: { exchange: { name: '初夏の交換会' } }

      expect(exchange.reload.name).to eq('初夏の交換会')
    end

    # 主催者は各期間の日時を後から変更できる（docs/spec.md 4. フェーズ）
    it '日程を変更できる' do
      patch exchange_path(exchange), params: { exchange: { wish_ends_at: '2026-10-01T10:00' } }

      expect(exchange.reload.wish_ends_at).to eq(Time.zone.parse('2026-10-01 10:00'))
    end

    it '変更できたことを知らせる' do
      patch exchange_path(exchange), params: { exchange: { name: '初夏の交換会' } }

      follow_redirect!

      expect(response.body).to include('交換会を更新しました')
    end

    it '不備があれば差し戻す' do
      patch exchange_path(exchange), params: { exchange: { name: '' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(exchange.reload.name).to eq('春の交換会')
    end

    it '主催者以外は更新できない' do
      log_in_as(create(:user))

      patch exchange_path(exchange), params: { exchange: { name: '乗っ取り' } }

      expect(response).to have_http_status(:not_found)
      expect(exchange.reload.name).to eq('春の交換会')
    end

    it 'ログインしていなければ更新できない' do
      log_out

      patch exchange_path(exchange), params: { exchange: { name: '乗っ取り' } }

      expect(exchange.reload.name).to eq('春の交換会')
    end

    # 差し替えられると、実行前に結果を引き直せてしまう
    it '乱数シードは変えられない' do
      seed = exchange.random_seed

      patch exchange_path(exchange), params: { exchange: { random_seed: 1 } }

      expect(exchange.reload.random_seed).to eq(seed)
    end
  end
end
