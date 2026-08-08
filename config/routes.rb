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
    # 詳細（#23）だけがまだ無い。それ以外は揃っている
    resources :books, except: [:show]
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

  # 開発用の裏口ログイン。seed が撒いた利用者は Google のアカウントを持たないため、
  # OAuth の経路では入れない。本番には経路そのものを描かない。
  # ログイン画面のリンクも同じ条件で出し分けている（app/views/sessions/new.html.erb）
  if Rails.env.local?
    get '/dev/login' => 'dev/sessions#new', as: :dev_login
    post '/dev/login/:user_id' => 'dev/sessions#create', as: :dev_login_as
  end

  # ログイン済みの着地は交換会一覧。未ログインなら require_login が
  # ログイン画面へ送り、認証を終えるとここへ戻ってくる
  root 'exchanges#index'
end
