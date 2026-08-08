# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dev::SessionsController do
  let!(:user) { create(:user, display_name: '持田さくら') }

  # 本番を偽装する。ルーティングは起動時に描かれるので production には経路そのものが
  # 無いが、環境の取り違えで描かれてしまったときのために、コントローラ側でも塞いである。
  # spec で突けるのはこちらの歯止めだけなので、ここを固定する
  def as_production
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
  end

  describe '#new' do
    it '入れ替われる利用者が並ぶ' do
      get dev_login_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('持田さくら')
    end

    it 'production では見つからない' do
      as_production

      get dev_login_path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe '#create' do
    it 'OAuth を通さずにログイン状態になる' do
      post dev_login_as_path(user)

      expect(session[:user_id]).to eq(user.id)
      expect(response).to redirect_to(root_path)
    end

    # 経路が残っていても、本番では絶対にログイン状態を作らせない
    it 'production ではログイン状態にならない' do
      as_production

      post dev_login_as_path(user)

      expect(response).to have_http_status(:not_found)
      expect(session[:user_id]).to be_nil
    end
  end
end
