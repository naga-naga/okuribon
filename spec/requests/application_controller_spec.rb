# frozen_string_literal: true

require 'rails_helper'

# 全画面が同じ枠組みを共有していることを、ここ1か所で押さえる。
# 画面ごとの spec に散らすと、あとから増えた画面だけ帯を持たない形が通ってしまう
RSpec.describe ApplicationController do
  let!(:user) { create(:user, display_name: '贈本 太郎') }

  # 帯の中だけを見る。ページ全体の文字列を見ると、本文に同じ字があったときに
  # 帯が持っているのかどうかを見分けられない
  def header
    response.parsed_body.at_css('header')
  end

  describe '書体と地の色' do
    it '書体を読み込む' do
      get login_path

      expect(response.body).to include('Zen+Kaku+Gothic+New')
    end

    it '地の色と書体を body に当てる' do
      get login_path

      expect(response.body).to include('bg-surface')
      expect(response.body).to include('font-sans')
    end
  end

  describe '共通ヘッダー' do
    context 'ログイン済み' do
      before { log_in_as(user) }

      it 'サービス名から交換会一覧へ戻れる' do
        exchange = create(:exchange)
        exchange.participations.create!(user:)

        get exchange_path(exchange)

        expect(header.at_css("a[href='#{exchanges_path}']").text).to eq('読書交換会')
      end

      # 現在地はリンクにしない。押しても同じ画面が返るだけのものを、
      # 行き先があるように見せない
      it '交換会一覧そのものではサービス名をリンクにしない' do
        get exchanges_path

        expect(header.at_css("a[href='#{exchanges_path}']")).to be_nil
        expect(header.at_css('[aria-current="page"]').text).to eq('読書交換会')
      end

      # root も交換会一覧を描く。URL が違うだけで同じ画面なので、
      # 現在地の判定を exchanges_path だけで書くと、root で開いたときに
      # 自分自身へのリンクが出る
      it 'root でもサービス名をリンクにしない' do
        get root_path

        expect(header.at_css("a[href='#{exchanges_path}']")).to be_nil
      end

      it 'ログイン中の利用者を出す' do
        get exchanges_path

        expect(header.text).to include('贈本 太郎')
      end

      # ログアウトの口が全画面にあることが、この帯を入れる第一の理由。
      # 副作用のある操作なので GET では出さない
      it 'ログアウトできる' do
        get exchanges_path

        form = header.at_css("form[action='#{logout_path}']")

        expect(form.at_css("input[name='_method']")['value']).to eq('delete')
      end
    end

    context '未ログイン' do
      # 招待URLは参加していない人が着地する画面で、帯そのものは出す。
      # 出せないのはアカウントの口だけ
      it '招待URL着地では帯を出し、アカウントの口を出さない' do
        exchange = create(:exchange)

        get invitation_path(exchange.invite_token)

        expect(header.text).to include('読書交換会')
        expect(header.at_css("form[action='#{logout_path}']")).to be_nil
      end

      # ログイン画面はまだ誰でもなく、行き先もログアウトも無い。
      # サービス名は画面自身が大きく名乗るので、帯を重ねると同じ名が2つ並ぶ
      it 'ログイン画面には帯を出さない' do
        get login_path

        expect(header).to be_nil
      end
    end
  end
end
