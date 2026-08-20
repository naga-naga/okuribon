# frozen_string_literal: true

require 'rails_helper'

# 参加から交換会を引く入口を、仕組み単体で確かめる。
# 実際のコントローラは5つあり、そのうち1つだけルートのキーが :id で違う。
# ここでは concern を載せた最小のものを2つ立て、キーの違いを跨いで同じ入口を通ることを見る
RSpec.describe ParticipatingExchange do
  let!(:user) { create(:user) }
  let!(:exchange) { create(:exchange) }
  let!(:participation) { create(:participation, user:, exchange:) }

  # ネストされた口（:exchange_id）と、単独の口（:id）の2つを立てる。
  # 引いたものを本文に出し、どちらの口でも同じ参加に辿り着くことを見る
  before do
    log_in_as(user)

    nested = Class.new(ApplicationController) do
      include ParticipatingExchange

      before_action :require_login
      before_action :set_participation

      def show
        render plain: [@participation.id, @exchange.id].join(',')
      end
    end

    singular = Class.new(ApplicationController) do
      include ParticipatingExchange

      before_action :require_login

      def show
        set_participation(params.expect(:id))

        render plain: [@participation.id, @exchange.id].join(',')
      end
    end

    stub_const('NestedParticipatingTestController', nested)
    stub_const('SingularParticipatingTestController', singular)

    Rails.application.routes.draw do
      get '/participating_test/exchanges/:exchange_id/nested' => 'nested_participating_test#show'
      get '/participating_test/exchanges/:id' => 'singular_participating_test#show'

      # ログインしていない人の行き先（Authentication が引く）
      root 'exchanges#index'
    end
  end

  after { Rails.application.reload_routes! }

  it '参加している交換会は、その参加とともに引ける' do
    get "/participating_test/exchanges/#{exchange.id}/nested"

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("#{participation.id},#{exchange.id}")
  end

  # 参加していない人に 403 を返すと、その交換会が実在することが URL を試すだけで分かる
  it '参加していない交換会は見つからない' do
    other = create(:exchange)

    get "/participating_test/exchanges/#{other.id}/nested"

    expect(response).to have_http_status(:not_found)
  end

  # 実在しない id と、実在するが参加していない交換会の応答が同じであること。
  # 分かれると、参加していない交換会の実在が応答の違いから読める
  it '存在しない交換会も見つからない' do
    get '/participating_test/exchanges/0/nested'

    expect(response).to have_http_status(:not_found)
  end

  # 交換会そのものを開く口だけルートのキーが :id になる。
  # 口ごとに条件を手書きしないために、キーだけを呼ぶ側から渡す
  it '交換会 id を渡す口も同じ入口を通る' do
    get "/participating_test/exchanges/#{exchange.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("#{participation.id},#{exchange.id}")
  end

  it '交換会 id を渡す口でも、参加していなければ見つからない' do
    other = create(:exchange)

    get "/participating_test/exchanges/#{other.id}"

    expect(response).to have_http_status(:not_found)
  end
end
