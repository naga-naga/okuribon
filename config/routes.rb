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

  # 一覧（#18）・トップ（#19）は、それぞれの issue で足す
  resources :exchanges, only: [:new, :create, :edit, :update]

  # 招待URL。交換会の id ではなく招待トークンで引く。
  # id で引けると、番号を数えるだけで招待されていない交換会に着地できてしまう
  get '/invitations/:token' => 'invitations#show', as: :invitation

  # 参加も招待トークンで引く。1人が同じ交換会に持てる参加は1つなので単数で置く
  post '/invitations/:token/participation' => 'participations#create',
       as: :invitation_participation

  # 辞退。自分の参加を1つ消すだけなので id は要らない。
  # 副作用のある操作なので GET では受けない
  delete '/invitations/:token/participation' => 'participations#destroy'

  # 交換会一覧（#18）が入るまでの暫定でログイン画面を置く
  root 'sessions#new'
end
