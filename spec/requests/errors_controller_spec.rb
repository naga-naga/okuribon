# frozen_string_literal: true

require 'rails_helper'

# 例外から描かれるエラー画面。ここで見るのは exceptions_app の配線と、
# 画面が漏らしてよい情報の範囲。個々の画面の 404 は、その画面の spec が持つ
RSpec.describe ErrorsController, :rendered_error_pages do
  let!(:user) { create(:user) }

  # 本文だけを取り出す。head の CSRF トークンはリクエストごとに変わるので、
  # 応答をまるごと突き合わせると、中身が同じでも必ず食い違う
  def main_text
    response.parsed_body.css('main').text.squish
  end

  describe '404' do
    it '存在しない交換会を開くとこのツールの 404 を返す' do
      log_in_as(user)

      get '/exchanges/0'

      expect(response).to have_http_status(:not_found)
      expect(main_text).to include('このページはありません')
    end

    # 8. 情報の可視性ルール。403 だと、招待されていない交換会が実在することを
    # URL を試すだけで確かめられてしまう。ステータスだけでなく本文も揃える必要がある
    it '参加していない交換会と存在しない交換会を区別できない' do
      other = create(:exchange)
      log_in_as(user)

      get "/exchanges/#{other.id}"
      not_participating = [response.status, main_text]

      get '/exchanges/0'

      expect([response.status, main_text]).to eq(not_participating)
    end

    # 交換会名も主催者名も出してはいけない。何が見つからなかったかを書くと、
    # 本文そのものが実在を教える
    it '引けなかった交換会の中身を本文に出さない' do
      other = create(:exchange)
      log_in_as(user)

      get "/exchanges/#{other.id}"

      expect(main_text).not_to include(other.name)
      expect(main_text).not_to include(other.owner.display_name)
    end

    it 'ログイン中は共通ヘッダーのログアウトが残る' do
      log_in_as(user)

      get '/exchanges/0'

      expect(response.parsed_body.css('header form[action="/logout"]')).to be_present
    end

    # 共通ヘッダーはログイン中しかログアウトを出さない。未ログインで行き止まりに
    # なると口が1つも無くなるので、本文がログインへの口を持つ
    it '未ログインならログインへの口がある' do
      get '/404'

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.css("main a[href='#{login_path}']")).to be_present
    end
  end

  describe '404 以外' do
    it '422 をこのツールの見た目で返す' do
      get '/422'

      expect(response).to have_http_status(:unprocessable_content)
      expect(main_text).to include('この操作は受け付けられませんでした')
    end

    it '400 をこのツールの見た目で返す' do
      get '/400'

      expect(response).to have_http_status(:bad_request)
      expect(main_text).to include('この URL は読み取れませんでした')
    end
  end

  # 500 だけはアプリのビューを通さない。DB もセッションも読めないことがあり、
  # ビューを通すとエラー画面そのものが描けなくなる
  describe '500' do
    # 既定の :rescuable では、拾う先の決まっていない例外は再送出されて
    # 画面にならない。5xx の経路を見るこの節だけ :all に倒す
    around do |example|
      env_config = Rails.application.env_config
      key = 'action_dispatch.show_exceptions'
      original = env_config[key]
      env_config[key] = :all
      example.run
    ensure
      env_config[key] = original
    end

    before do
      stub_const('BoomController', Class.new(ApplicationController) do
        def show
          raise 'boom'
        end
      end)

      Rails.application.routes.draw { get '/boom' => 'boom#show' }
    end

    after { Rails.application.reload_routes! }

    it 'アプリのビューを通さず、揃えた静的 HTML を返す' do
      get '/boom'

      expect(response).to have_http_status(:internal_server_error)
      expect(main_text).to include('こちらの不具合で表示できませんでした')
      # ビューを通していれば必ず入るもの。入っていたら経路を取り違えている
      expect(response.body).not_to include('csrf-token')
    end

    # 登録した本や希望リストが消えたと読ませない。3. の取得枠の勘定は
    # 登録済みの冊数で決まるので、消えたと思えば登録し直しに来る
    it 'データが失われていないことを書く' do
      get '/boom'

      expect(main_text).to include('失われていません')
    end
  end
end
