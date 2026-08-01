# frozen_string_literal: true

require 'rails_helper'

# 保護された画面はまだ1つも無いため、仕組み単体で確かめる。
# require_login を載せた最小のコントローラを立てて回す
RSpec.describe 'ログインの要求' do
  let!(:auth) do
    OmniAuth::AuthHash.new(
      provider: 'google_oauth2',
      uid: '100000000000000000001',
      info: { name: '贈本 太郎', image: 'https://example.com/a.png' }
    )
  end

  before do
    OmniAuth.config.mock_auth[:google_oauth2] = auth

    stub_const('ProtectedTestController', Class.new(ApplicationController) do
      before_action :require_login

      def show
        render plain: 'protected'
      end

      def create
        head :created
      end
    end)

    # 戻り先の検証は pop_return_to に閉じている。
    # そこへ辿り着く値を直に置くために、session へ書くだけの経路を立てる
    stub_const('ReturnToSeedTestController', Class.new(ApplicationController) do
      def create
        session[:return_to] = params[:to]
        head :created
      end
    end)

    # ログイン画面とコールバックは実物を通すため、消さずに足す。
    # 経路は遅延読み込みなので、先に読ませてから追記しないと実物ごと消える
    Rails.application.reload_routes_unless_loaded
    Rails.application.routes.disable_clear_and_finalize = true
    Rails.application.routes.draw do
      get '/require_login_test/protected' => 'protected_test#show'
      post '/require_login_test/protected' => 'protected_test#create'
      post '/require_login_test/return_to' => 'return_to_seed_test#create'
    end
  end

  after do
    Rails.application.routes.disable_clear_and_finalize = false
    Rails.application.reload_routes!
  end

  it 'ログイン済みならそのまま開ける' do
    get '/auth/google_oauth2/callback'

    get '/require_login_test/protected'

    expect(response.body).to eq('protected')
  end

  it '未認証ならログイン画面へ誘導する' do
    get '/require_login_test/protected'

    expect(response).to redirect_to(login_path)
  end

  describe '認証後の復帰' do
    it '元の URL へ戻る' do
      get '/require_login_test/protected?page=2'

      get '/auth/google_oauth2/callback'

      expect(response).to redirect_to('/require_login_test/protected?page=2')
    end

    it '誘導を挟まずにログインしたときは root へ戻す' do
      get '/auth/google_oauth2/callback'

      expect(response).to redirect_to(root_path)
    end

    # 戻り先を残すと、次にログインしたときに関係のない画面へ飛ぶ
    it '一度使った戻り先は残らない' do
      get '/require_login_test/protected'
      get '/auth/google_oauth2/callback'

      delete '/logout'
      get '/auth/google_oauth2/callback'

      expect(response).to redirect_to(root_path)
    end

    # HEAD は GET と同じ経路に流れるのに request.get? は false になる。
    # 読み取りとして扱わないと、同じ URL でも戻り先が覚えられたり覚えられなかったりする
    it 'HEAD も戻り先として覚える' do
      head '/require_login_test/protected'

      get '/auth/google_oauth2/callback'

      expect(response).to redirect_to('/require_login_test/protected')
    end

    # 書き込みを戻り先にすると、ログインしただけで送信をやり直させてしまう
    it '書き込みの経路は戻り先にしない' do
      post '/require_login_test/protected'

      get '/auth/google_oauth2/callback'

      expect(response).to redirect_to(root_path)
    end
  end

  # 戻り先を外部サイトにできると、本物のログイン画面を経由した
  # もっともらしいリンクで、認証直後に偽サイトへ落とせる
  describe '戻り先の限定' do
    # OmniAuth は ?origin= と Referer から omniauth.origin を組み立てる。
    # どちらも攻撃者が仕込めるため、戻り先としては読まない
    it 'origin パラメータでは外部サイトへ飛ばない' do
      get '/auth/google_oauth2/callback?origin=https://evil.example.com'

      expect(response).to redirect_to(root_path)
    end

    it 'Referer では外部サイトへ飛ばない' do
      get '/auth/google_oauth2/callback',
          headers: { 'HTTP_REFERER' => 'https://evil.example.com/login' }

      expect(response).to redirect_to(root_path)
    end

    # 保存の側が緩んでも外へ出さない。判定は取り出す1か所に置く
    ['https://evil.example.com', 'http://evil.example.com/x', '//evil.example.com',
     '/\\evil.example.com', 'javascript:alert(1)',].each do |hostile|
      it "戻り先が #{hostile} でも root へ戻す" do
        post '/require_login_test/return_to', params: { to: hostile }

        get '/auth/google_oauth2/callback'

        expect(response).to redirect_to(root_path)
      end
    end

    it '自サイト内のパスはそのまま使う' do
      post '/require_login_test/return_to', params: { to: '/exchanges/1?tab=books' }

      get '/auth/google_oauth2/callback'

      expect(response).to redirect_to('/exchanges/1?tab=books')
    end
  end

  # セッション固定攻撃を防ぐ。攻撃者が事前に踏ませたセッション ID が
  # ログイン後もそのまま通ると、その ID で本人になりすませる
  it 'ログイン前のセッションを引き継がない' do
    get '/require_login_test/protected'
    before_login = session.id
    expect(before_login).to be_present

    get '/auth/google_oauth2/callback'

    expect(session.id).not_to eq(before_login)
  end
end
