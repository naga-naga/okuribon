# frozen_string_literal: true

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # OAuth のコールバック。プロバイダからのリダイレクトで来るため GET で受ける。
  # 認証開始（POST /auth/google_oauth2）は OmniAuth のミドルウェアが横取りするので、ここには書かない
  get '/auth/google_oauth2/callback' => 'sessions#create', as: :oauth_callback

  get '/login' => 'sessions#new', as: :login

  # 副作用のある操作なので GET では受けない。
  # 外部サイトに置いたリンクや画像だけでログアウトさせられてしまう
  delete '/logout' => 'sessions#destroy', as: :logout

  # 本は必ずどれか1つの交換会に属し、単独では意味を持たない。
  # 交換会の下に置くと、参加しているかどうかの判定を親から引ける
  resources :exchanges, only: [:index, :show, :new, :create, :edit, :update] do
    # 1冊だけを開く画面は持たない（docs/spec.md 6.3）。
    # 読むための情報は一覧のカードが全部持っていて、ギフトコードは結果画面が受け持つ。
    # 一覧そのものも交換会ページに畳んだので index も持たない（6.1）。
    # 本に残るのは書き込みの口だけになる
    resources :books, except: [:show, :index] do
      # 1冊に対する自分の希望は1つしかないので単数で置く。参加と同じ理由。
      # 順位はここでは受け取らない。並べ替えは希望リスト全体を1度に送る（#27）
      resource :wish, only: [:create, :destroy]
    end

    # 並べ替えは希望リスト全体を1度に送る。本を特定しない操作なので、
    # 本の下ではなく交換会の直下に置く。1人が持つ希望リストは1つなので単数
    resource :wish_list, only: [:update]

    # 結果画面。1つの交換会が出す結果は1つなので単数で置く。
    # 見えるものは開いた人によって変わるが、それは結果の切り口であって別のリソースではない
    resource :result, only: [:show]

    # 主催者管理画面。1つの交換会に管理画面は1つなので単数で置く
    resource :management, only: [:show] do
      # 招待トークンの再発行。1つの交換会が持つトークンは1つなので単数で置く。
      # 作り直すのではなく差し替えなので create ではなく update で受ける。
      # 管理画面の下に置くのは、主催者以外に触らせない経路だから
      resource :invite_token, only: [:update]

      # 主催者による参加者の除外。外す相手を選ぶので複数形で置き、id で特定する。
      # 自分の参加を消す辞退（/invitations/:token/participation）とは
      # 経路を分ける。押せる人も、対象を選べるかどうかも違う
      resources :participants, only: [:destroy]

      # マッチングの実行。一度しか実行できないので単数で置く。
      # new は実行前の確認画面。取り返しがつかない操作なので、ブラウザの
      # ダイアログではなく画面を1枚挟む（docs/spec.md 6.8）。
      # 管理画面の下に置くのは、招待トークンの再発行と同じく主催者しか触らないため
      resource :matching, only: [:new, :create]
    end
  end

  # 招待URL。交換会の id ではなく招待トークンで引く。
  # id で引けると、番号を数えるだけで招待されていない交換会に着地できてしまう
  get '/invitations/:token' => 'invitations#show', as: :invitation

  # 参加も招待トークンで引く。1人が同じ交換会に持てる参加は1つなので単数で置く
  post '/invitations/:token/participation' => 'participations#create',
       as: :invitation_participation

  # 辞退。自分の参加を1つ消すだけなので id は要らない。
  # 副作用のある操作なので GET では受けない
  delete '/invitations/:token/participation' => 'participations#destroy'

  # 開発用の裏口ログイン。seed が作った利用者は Google のアカウントを持たないため、
  # OAuth の経路では入れない。本番には経路そのものを描かない。
  # ログイン画面のリンクも同じ条件で出し分けている（app/views/sessions/new.html.erb）
  if Rails.env.local?
    get '/dev/login' => 'dev/sessions#new', as: :dev_login
    post '/dev/login/:user_id' => 'dev/sessions#create', as: :dev_login_as
  end

  # エラー画面。例外を拾った exceptions_app がここへ流す（config/application.rb）。
  # 直に開ける経路としても残す。development と test は
  # consider_all_requests_local が真で例外の詳細ページが先に出るため、
  # この経路を持たないと手元で見た目を確かめられない
  # exceptions_app は元のリクエストの種別を問わず GET に書き換えて渡すため、
  # ここも GET だけを受ければよい
  Okuribon::RENDERED_ERROR_PATHS.each do |path|
    get path => 'errors#show'
  end

  # ログイン済みの着地は交換会一覧。未ログインなら require_login が
  # ログイン画面へ送り、認証を終えるとここへ戻ってくる
  root 'exchanges#index'
end
