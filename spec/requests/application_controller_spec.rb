# frozen_string_literal: true

require 'rails_helper'

# 全画面が同じ枠組みを共有していることを、ここ1か所で押さえる。
# 画面ごとの spec に散らすと、あとから増えた画面だけ共通ヘッダーを持たない形が通ってしまう
RSpec.describe ApplicationController do
  let!(:user) { create(:user, display_name: '贈本 太郎') }

  # 共通ヘッダーの中だけを見る。ページ全体の文字列を見ると、本文に同じ字があったときに
  # ヘッダーが持っているのかどうかを見分けられない
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

  # タブに並んだときに、どの道具のどの画面かが読めること。静的な 500 / 406 が
  # 同じ形の題を持っているので、アプリ側だけ画面名しか出さないと、
  # エラーへ落ちた瞬間に題の形が変わる
  describe 'ページの題' do
    def title = response.parsed_body.at_css('title').text

    it '画面の名前にサービス名を添える' do
      get login_path

      expect(title).to eq('ログイン — おくりぼん')
    end

    it 'ログイン後の画面にも添える' do
      log_in_as(user)

      get exchanges_path

      expect(title).to eq('交換会一覧 — おくりぼん')
    end
  end

  describe '共通ヘッダー' do
    context 'ログイン済み' do
      before { log_in_as(user) }

      # 根が名乗るのは行き先の名前で、サービス名ではない。パンくずは祖先を
      # 連ねるもので、全段が画面の名前で揃う
      it 'パンくずの根から交換会一覧へ戻れる' do
        exchange = create(:exchange)
        exchange.participations.create!(user:)

        get exchange_path(exchange)

        expect(header.at_css("a[href='#{exchanges_path}']").text).to eq('交換会一覧')
      end

      # 現在地はリンクにしない。押しても同じ画面が返るだけのものを、
      # 行き先があるように見せない
      it '交換会一覧そのものではパンくずの根をリンクにしない' do
        get exchanges_path

        expect(header.at_css("a[href='#{exchanges_path}']")).to be_nil
        expect(header.at_css('[aria-current="page"]').text).to eq('交換会一覧')
      end

      # ログイン後にサービス名を出す場所は持たない。名前が画面に大きく出るのは
      # ログイン画面だけで、その先はどの交換会に居るかのほうが要る
      it 'サービス名を共通ヘッダーに出さない' do
        get exchanges_path

        expect(header.text).not_to include(I18n.t('service.name'))
      end

      # root も交換会一覧を描く。URL が違うだけで同じ画面なので、
      # 現在地の判定を exchanges_path だけで書くと、root で開いたときに
      # 自分自身へのリンクが出る
      it 'root でもパンくずの根をリンクにしない' do
        get root_path

        expect(header.at_css("a[href='#{exchanges_path}']")).to be_nil
      end

      it 'ログイン中の利用者を出す' do
        get exchanges_path

        expect(header.text).to include('贈本 太郎')
      end

      # ログアウトの導線が全画面にあることが、共通ヘッダーを入れる第一の理由。
      # 副作用のある操作なので GET では出さない
      it 'ログアウトできる' do
        get exchanges_path

        form = header.at_css("form[action='#{logout_path}']")

        expect(form.at_css("input[name='_method']")['value']).to eq('delete')
      end
    end

    context '未ログイン' do
      # 招待URLは参加していない人が着地する画面で、共通ヘッダーそのものは出す。
      # 出せないのはアカウントの操作だけ
      it '招待URL着地では共通ヘッダーを出し、アカウントの操作を出さない' do
        exchange = create(:exchange)

        get invitation_path(exchange.invite_token)

        expect(header.at_css("form[action='#{logout_path}']")).to be_nil
      end

      # 未ログインの人にとって交換会一覧は祖先ではない。ログインしないと開けない
      # 画面の名前を置いても行き先にならないので、ここだけはサービス名を名乗る。
      # この画面が、招待された人がこの道具の名前を最初に見る場所にあたる
      it '招待URL着地ではパンくずの根がサービス名になる' do
        exchange = create(:exchange)

        get invitation_path(exchange.invite_token)

        expect(header.text).to include(I18n.t('service.name'))
        expect(header.text).not_to include('交換会一覧')
      end

      # ログイン画面はまだ誰でもなく、行き先もログアウトも無い。加えて、
      # この画面はサービス名を見出しに大きく出すので、重ねると同じ名が2つ並ぶ
      it 'ログイン画面には共通ヘッダーを出さない' do
        get login_path

        expect(header).to be_nil
      end
    end
  end

  # 書き込みを断ったときの画面。ステータスの使い分けと
  # メッセージの中身は phase_guard_spec が押さえる。ここで見るのは画面のほうで、
  # 断られた人がどこへ行けるかを持っているかどうか
  describe '書き込みを拒否したときの画面' do
    let!(:exchange) do
      create(
        :exchange,
        name: '夏の交換会',
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
    end

    let!(:wish_period) { '2026-08-11T00:00:00+09:00'.in_time_zone }

    def main_text
      response.parsed_body.css('main').text.squish
    end

    context 'フェーズが許していないとき（409）' do
      before do
        exchange.participations.create!(user:)
        log_in_as(user)

        travel_to(wish_period) do
          post exchange_books_path(exchange), params: { book: { title: '本' } }
        end
      end

      it '409 を返す' do
        expect(response).to have_http_status(:conflict)
      end

      # 断られた人が、どの交換会の話なのかを画面から読めるようにする。
      # 書き込みの操作は交換会をまたいで同じ形をしているので、
      # メッセージだけだと、どれを操作していたのかが分からない
      it 'どの交換会でのことかを出す' do
        expect(main_text).to include('夏の交換会')
      end

      # 11. の求めるもの。待てば書けるのかどうかが分かる必要がある
      it '現在のフェーズとできなかった操作を出す' do
        expect(main_text).to include('希望提出期間')
        expect(main_text).to include('本の登録・編集はできません')
      end

      # 行き止まりにしない。統合で交換会の中の画面は交換会ページに集まったので、
      # 戻る先は1つでよい
      it '交換会ページへ戻るリンクがある' do
        expect(response.parsed_body.css("main a[href='#{exchange_path(exchange)}']")).to be_present
      end
    end

    # 役割による拒否。待てば通るフェーズの拒否とは別のステータスで、
    # 画面の組み立ては同じにする
    context '主催者が自分の参加を動かそうとしたとき（403）' do
      before do
        log_in_as(exchange.owner)

        travel_to('2026-08-04T00:00:00+09:00'.in_time_zone) do
          delete invitation_participation_path(exchange.invite_token)
        end
      end

      it '403 を返す' do
        expect(response).to have_http_status(:forbidden)
      end

      it '同じ組み立てで、交換会ページへ戻るリンクがある' do
        expect(main_text).to include('夏の交換会')
        expect(response.parsed_body.css("main a[href='#{exchange_path(exchange)}']")).to be_present
      end
    end
  end
end
