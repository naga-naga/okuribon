# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SessionsController do
  let!(:auth) do
    OmniAuth::AuthHash.new(
      provider: 'google_oauth2',
      uid: '100000000000000000001',
      info: { name: '贈本 太郎', image: 'https://example.com/a.png' }
    )
  end

  before { OmniAuth.config.mock_auth[:google_oauth2] = auth }

  describe '#new' do
    it '開ける' do
      get '/login'

      expect(response).to have_http_status(:ok)
    end

    # root は交換会一覧へ渡した。ログインを促すのは require_login の仕事で、
    # 未ログインならそこからこの画面へ戻ってくる
    it '未ログインで root を開くとここへ送られる' do
      get '/'

      expect(response).to redirect_to(login_path)
    end

    # 認証開始は POST に限る。リンクで置くと GET になり、外部サイトから踏ませられる
    it '認証開始への POST を置く' do
      get '/login'

      expect(response.body).to include('action="/auth/google_oauth2"')
      expect(response.body).to include('method="post"')
    end

    # デザインの「01 ログイン」には3つのプロバイダが並ぶが、実装があるのは
    # docs/spec.md 11 が定める Google だけ。デザインに引きずられて、
    # 押しても認証できないボタンが混ざらないようにする。
    # プロバイダを増やすときは、omniauth.rb に足したうえでここにも並べる
    it '実装のあるプロバイダの分だけ認証開始の口を置く' do
      get '/login'

      providers = response.body.scan(%r{action="/auth/([^"]+)"}).flatten

      expect(providers).to contain_exactly('google_oauth2')
    end

    # 「ログインして参加する」から送られてきた人に、何のためのログインかを見せる。
    # 交換会の名前が無いと、押したはずの参加とこの画面が結び付かない
    it '参加しようとしている交換会の名前を出す' do
      target = create(:exchange, name: '夏の交換会')

      post invitation_participation_path(target.invite_token)
      follow_redirect!

      expect(response.body).to include('夏の交換会')
      expect(response.body).to include('参加するには')
    end

    it 'ログイン済みなら表示名とログアウトを出す' do
      get '/auth/google_oauth2/callback'

      get '/login'

      expect(response.body).to include('贈本 太郎')
      expect(response.body).to include('ログアウト')
    end

    # 開発用ログイン（docs/spec.md 11.）は URL を直に打たないと辿り着けない。
    # seed が作った利用者へ入れ替わるたびに打つことになるので、ここに口を置く
    context '開発用ログイン' do
      it '未ログインなら辿れる' do
        get '/login'

        expect(response.body).to include(dev_login_path)
      end

      # ログイン済みでも出す。入れ替わりたいのは、たいていもう誰かで入っているとき
      it 'ログイン済みでも辿れる' do
        get '/auth/google_oauth2/callback'

        get '/login'

        expect(response.body).to include(dev_login_path)
      end

      # 経路の無い環境でリンクだけ残ると、押しても404になる案内が出る
      it 'production では出さない' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))

        get '/login'

        expect(response.body).not_to include('/dev/login')
      end
    end
  end

  describe '#create' do
    it '認証に成功すると利用者ができる' do
      expect { get '/auth/google_oauth2/callback' }.to change(User, :count).by(1)

      expect(User.last).to have_attributes(
        provider: 'google_oauth2',
        uid: '100000000000000000001',
        display_name: '贈本 太郎',
        avatar_url: 'https://example.com/a.png'
      )
    end

    # 再ログインのたびに増えると、参加も本も別人のものとして分かれてしまう
    it '同じ人が再ログインしても利用者は増えない' do
      get '/auth/google_oauth2/callback'

      expect { get '/auth/google_oauth2/callback' }.not_to change(User, :count)
    end

    it '認証に成功するとログイン状態になる' do
      get '/auth/google_oauth2/callback'

      expect(session[:user_id]).to eq(User.last.id)
    end

    it '認証後は画面へ戻す' do
      get '/auth/google_oauth2/callback'

      expect(response).to have_http_status(:redirect)
    end
  end

  describe '#destroy' do
    before { get '/auth/google_oauth2/callback' }

    it 'セッションが破棄される' do
      delete '/logout'

      expect(session[:user_id]).to be_nil
    end

    it 'ログイン画面へ戻す' do
      delete '/logout'

      expect(response).to redirect_to(login_path)
    end
  end
end
