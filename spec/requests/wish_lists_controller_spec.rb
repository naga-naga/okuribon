# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WishListsController do
  let!(:user) { create(:user) }
  let!(:exchange) do
    create(:exchange,
           registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
           registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
           wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)
  end
  let!(:participation) { create(:participation, user:, exchange:) }

  # 希望提出期間の中の1点。ここを基準にして、外れたフェーズは別に指定する
  let!(:during_wish) { '2026-08-11T00:00:00+09:00'.in_time_zone }

  # 希望に入れた3冊。並べ替えの相手はこれで足りる
  let!(:books) { Array.new(3) { book_by_other } }

  before do
    log_in_as(user)
    travel_to(during_wish) { books.each { participation.add_wish!(it, at: during_wish) } }
  end

  # 他の人が登録した本。自分の本は希望に選べないので、既定はこちらにする
  def book_by_other(**attributes)
    create(:book, participation: create(:participation, exchange:), **attributes)
  end

  def reorder(book_ids, at: during_wish, params: {}, **)
    travel_to(at) do
      patch(exchange_wish_list_path(exchange), params: { book_ids: book_ids.map(&:to_s), **params }, **)
    end
  end

  def wished_books
    participation.wishes.reload.map(&:book)
  end

  # 差し替えの中身を確かめるとき、Turbo Stream で受け取る
  def turbo
    { headers: { 'Accept' => Mime[:turbo_stream].to_s } }
  end

  describe '#update' do
    it '渡された順に並べ替える' do
      reorder([books[2].id, books[0].id, books[1].id])

      expect(wished_books).to eq([books[2], books[0], books[1]])
    end

    # 送られた順序をそのまま順位にはしない。サーバー側で1から振り直す
    it '順位が1からの連番で保存される' do
      reorder(books.reverse.map(&:id))

      expect(participation.wishes.reload.pluck(:position)).to eq([1, 2, 3])
    end

    it '交換会ページへ戻る' do
      reorder(books.reverse.map(&:id))

      expect(response).to redirect_to(exchange_path(exchange))
    end

    # 絞り込みは URL に残る
    it '絞り込みを保ったまま戻る' do
      reorder(books.reverse.map(&:id), params: { filter: 'mine' })

      expect(response).to redirect_to(exchange_path(exchange, filter: 'mine'))
    end

    it '並びを送らなければ受け付けない' do
      travel_to(during_wish) { patch(exchange_wish_list_path(exchange)) }

      expect(response).to have_http_status(:bad_request)
      expect(wished_books).to eq(books)
    end
  end

  # 集合が食い違うのは別のタブで追加・削除したときで、届いた並びを正として
  # 差分を反映すると、そちらの変更が気付かれないまま消える
  describe '希望リストと食い違う並び' do
    it '希望していない本が混じっていればリクエスト全体を拒否する' do
      reorder(books.map(&:id) + [book_by_other.id])

      expect(response).to have_http_status(:conflict)
      expect(wished_books).to eq(books)
    end

    # 自分の本は希望に入れられないので、混ざっていれば必ず食い違う
    it '自分の本が混じっていればリクエスト全体を拒否する' do
      reorder(books.map(&:id) + [create(:book, participation:).id])

      expect(response).to have_http_status(:conflict)
      expect(wished_books).to eq(books)
    end

    it '別の交換会の本が混じっていればリクエスト全体を拒否する' do
      other = create(:book, participation: create(:participation, exchange: create(:exchange)))

      reorder(books.map(&:id) + [other.id])

      expect(response).to have_http_status(:conflict)
      expect(wished_books).to eq(books)
    end

    # 拒否したときに一部だけ書き換わっていると、順位が中途半端に残る。
    # 先頭2冊は入れ替えて送っているので、部分的に反映されれば並びが変わる
    it '拒否したときは順位を書き換えない' do
      reorder([books[1].id, books[0].id])

      expect(response).to have_http_status(:conflict)
      expect(wished_books).to eq(books)
      expect(participation.wishes.reload.pluck(:position)).to eq([1, 2, 3])
    end

    it '同じ本が二度現れれば拒否する' do
      reorder([books[0].id, books[0].id, books[1].id, books[2].id])

      expect(response).to have_http_status(:conflict)
      expect(wished_books).to eq(books)
    end

    # 500 にせず、画面を読み直させる。待てば通るものではないので 409 が近い
    it '読み直しを促すメッセージを返す' do
      reorder(books.map(&:id) + [book_by_other.id])

      expect(response.body).to include(I18n.t('participation.wish_list_mismatch'))
    end
  end

  describe 'フェーズと権限' do
    {
      '準備中' => '2026-07-25T00:00:00+09:00',
      '登録期間' => '2026-08-04T00:00:00+09:00',
      'マッチング実行待ち' => '2026-08-20T00:00:00+09:00',
    }.each do |phase, now|
      it "#{phase}は並べ替えられない" do
        reorder(books.reverse.map(&:id), at: now.in_time_zone)

        expect(response).to have_http_status(:conflict)
        expect(wished_books).to eq(books)
      end
    end

    it '結果公開後は並べ替えられない' do
      exchange.update!(matched_at: 1.day.ago)

      reorder(books.reverse.map(&:id))

      expect(response).to have_http_status(:conflict)
      expect(wished_books).to eq(books)
    end

    # 交換会は自分の参加から引く。他人の参加を id で名指しできるルートは無い
    it '他人の希望リストは書き換えられない' do
      log_in_as(create(:user))

      reorder(books.reverse.map(&:id))

      expect(response).to have_http_status(:not_found)
      expect(wished_books).to eq(books)
    end

    it 'ログインしていなければログイン画面へ送る' do
      log_out

      reorder(books.reverse.map(&:id))

      expect(response).to redirect_to(login_path)
      expect(wished_books).to eq(books)
    end
  end

  describe 'Turbo Stream での応答' do
    # 並べ替えると全部の順位が変わるので、動かした1枚だけでは足りない
    it 'カードの一覧と希望リストの両方を差し替える' do
      reorder(books.reverse.map(&:id), **turbo)

      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body).to include('target="book_list"')
      expect(response.body).to include('target="wish_list"')
    end

    # 開閉の状態を持つシートの外枠は差し替えの外に置く
    it '差し替えるのは希望リストの中身だけで、シートの外枠は含めない' do
      reorder(books.reverse.map(&:id), **turbo)

      expect(response.body).not_to include('wish-sheet')
    end

    # 差し替えも一覧の一経路。見えてよいのは登録した本人と成立後の受取人だけで、
    # ここはどちらでもない
    it 'ギフトコードが含まれない' do
      create(:book, participation:, gift_code: 'MYOWNGIFTCODE')
      books.first.update!(gift_code: 'OTHERGIFTCODE')

      reorder(books.reverse.map(&:id), **turbo)

      expect(response.body).not_to include('MYOWNGIFTCODE')
      expect(response.body).not_to include('OTHERGIFTCODE')
    end
  end
end
