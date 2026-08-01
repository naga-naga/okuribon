# frozen_string_literal: true

require 'rails_helper'

# 書き込み口ごとの手書きにしないための仕組みを、仕組み単体で確かめる。
# 実際のコントローラは #12 以降で入るため、ここでは concern を載せた最小のものを立てて回す
RSpec.describe 'フェーズによる書き込み制御' do
  let!(:registration_period) { '2026-08-04T00:00:00+09:00'.in_time_zone }
  let!(:wish_period) { '2026-08-11T00:00:00+09:00'.in_time_zone }

  let!(:exchange) do
    create(
      :exchange,
      registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
      registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
      wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
    )
  end

  # 拒否がアクションの手前で効いているかを見るため、走ったアクションを記録する
  let!(:performed) { [] }

  # 操作名だけが違う2つのコントローラを立てる。
  # 拒否の応答が口を問わず同じ形になることを確かめるため
  before do
    performed_actions = performed

    [[:book, 'Books'], [:wish, 'Wishes']].each do |operation, prefix|
      controller = Class.new(ApplicationController) do
        include PhaseGuard

        guard_phase operation, only: [:create]

        define_method(:create) do
          performed_actions << operation
          head :created
        end

        define_method(:index) do
          performed_actions << :"#{operation}_index"
          head :ok
        end

        private

        define_method(:current_exchange) do
          Exchange.find(params[:exchange_id])
        end
      end

      stub_const("#{prefix}GuardTestController", controller)
    end

    Rails.application.routes.draw do
      scope '/phase_guard_test/exchanges/:exchange_id' do
        post '/books' => 'books_guard_test#create'
        get '/books' => 'books_guard_test#index'
        post '/wishes' => 'wishes_guard_test#create'
      end
    end
  end

  after { Rails.application.reload_routes! }

  it '許可されたフェーズなら書き込める' do
    travel_to(registration_period) do
      post "/phase_guard_test/exchanges/#{exchange.id}/books"
    end

    expect(response).to have_http_status(:created)
    expect(performed).to eq([:book])
  end

  it '許可されていないフェーズの書き込みは拒否される' do
    travel_to(wish_period) do
      post "/phase_guard_test/exchanges/#{exchange.id}/books"
    end

    expect(response).to have_http_status(:conflict)
  end

  # before_action で止めないと、拒否の応答を返しながら書き込みだけ通ってしまう
  it '拒否されたときアクションは走らない' do
    travel_to(wish_period) do
      post "/phase_guard_test/exchanges/#{exchange.id}/books"
    end

    expect(performed).to be_empty
  end

  # 読み取りは全フェーズで開いている。書き込みだけを止める
  it '対象に指定していないアクションは止めない' do
    travel_to(wish_period) do
      get "/phase_guard_test/exchanges/#{exchange.id}/books"
    end

    expect(response).to have_http_status(:ok)
    expect(performed).to eq([:book_index])
  end

  # 対象の交換会を返せないまま黙って素通りすると、制御が効いていないことに気付けない
  it '交換会の取り出し方を書き忘れたコントローラは落ちる' do
    stub_const('ForgotGuardTestController', Class.new(ApplicationController) do
      include PhaseGuard

      guard_phase :book, only: [:create]

      def create
        head :created
      end
    end)

    Rails.application.routes.draw do
      post '/phase_guard_test/forgot' => 'forgot_guard_test#create'
    end

    expect { post '/phase_guard_test/forgot' }.to raise_error(NotImplementedError)
  end

  describe '拒否の応答' do
    it 'コントローラが違っても同じステータスになる' do
      travel_to(wish_period) do
        post "/phase_guard_test/exchanges/#{exchange.id}/books"
      end
      books_status = response.status

      travel_to(registration_period) do
        post "/phase_guard_test/exchanges/#{exchange.id}/wishes"
      end

      expect(response.status).to eq(books_status)
      expect(response).to have_http_status(:conflict)
    end

    # 待てば書けるのか、そもそも権限が無いのかが利用者に分かる必要がある。
    # 現在のフェーズと、できなかった操作の両方を出す
    it '現在のフェーズと操作をメッセージに含む' do
      travel_to(wish_period) do
        post "/phase_guard_test/exchanges/#{exchange.id}/books"
      end

      expect(response.body).to include('現在は希望提出期間のため、本の登録・編集はできません')
    end

    it 'コントローラごとに操作名が入れ替わる' do
      travel_to(registration_period) do
        post "/phase_guard_test/exchanges/#{exchange.id}/wishes"
      end

      expect(response.body).to include('現在は登録期間のため、希望リストの変更はできません')
    end
  end

  describe '基準時刻' do
    # クライアントの時計や送られてきた値ではなく、サーバーの現在時刻で判定する
    it 'サーバーの現在時刻が締切を越えると、通っていた書き込みが拒否に変わる' do
      boundary = '2026-08-08T00:00:00+09:00'.in_time_zone

      travel_to(boundary - 1.second) do
        post "/phase_guard_test/exchanges/#{exchange.id}/books"
      end
      expect(response).to have_http_status(:created)

      travel_to(boundary) do
        post "/phase_guard_test/exchanges/#{exchange.id}/books"
      end
      expect(response).to have_http_status(:conflict)
    end

    it 'パラメータで許可されたフェーズを送っても拒否される' do
      travel_to(wish_period) do
        post "/phase_guard_test/exchanges/#{exchange.id}/books",
             params: { phase: 'registration' }
      end

      expect(response).to have_http_status(:conflict)
      expect(performed).to be_empty
    end

    it 'パラメータで期間内の時刻を送っても拒否される' do
      travel_to(wish_period) do
        post "/phase_guard_test/exchanges/#{exchange.id}/books",
             params: { at: registration_period.iso8601 }
      end

      expect(response).to have_http_status(:conflict)
      expect(performed).to be_empty
    end
  end
end
