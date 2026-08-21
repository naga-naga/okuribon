# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WishesController do
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

  before { log_in_as(user) }

  # 他の人が登録した本。自分の本は希望に選べないので、既定はこちらにする
  def book_by_other(**attributes)
    create(:book, participation: create(:participation, exchange:), **attributes)
  end

  def add(book, at: during_wish, **)
    travel_to(at) { post(exchange_book_wish_path(exchange, book), **) }
  end

  def remove(book, at: during_wish, **)
    travel_to(at) { delete(exchange_book_wish_path(exchange, book), **) }
  end

  def wished_books
    participation.wishes.reload.map(&:book)
  end

  describe '#create' do
    it '希望提出期間中は希望に追加できる' do
      book = book_by_other

      add(book)

      expect(wished_books).to eq([book])
    end

    # 順位は追加した順に伸びる。あとから並べ替える（#26 / #27）ための初期値
    it '続けて追加すると末尾に付く' do
      first = book_by_other
      second = book_by_other

      add(first)
      add(second)

      expect(participation.wishes.reload.pluck(:position)).to eq([1, 2])
      expect(wished_books).to eq([first, second])
    end

    # 二度押しや再送信で落とすようなことではない
    it '同じ本を二度追加しても増えない' do
      book = book_by_other

      add(book)
      add(book)

      expect(wished_books).to eq([book])
    end

    it '交換会ページへ戻る' do
      add(book_by_other)

      expect(response).to redirect_to(exchange_path(exchange))
    end

    # 絞り込みは URL に残る。追加のたびに全件へ戻されると、
    # 絞り込んだ状態で選び続けられない
    it '絞り込みを保ったまま戻る' do
      add(book_by_other, params: { filter: 'mine' })

      expect(response).to redirect_to(exchange_path(exchange, filter: 'mine'))
    end

    # 自分の本は受け取れない。ボタンは出さないが、
    # 直に叩かれたときに 500 で落とさない
    it '自分の本は追加できない' do
      add(create(:book, participation:))

      expect(response).to have_http_status(:unprocessable_content)
      expect(wished_books).to be_empty
    end

    {
      '準備中' => '2026-07-25T00:00:00+09:00',
      '登録期間' => '2026-08-04T00:00:00+09:00',
      'マッチング実行待ち' => '2026-08-20T00:00:00+09:00',
    }.each do |phase, now|
      it "#{phase}は追加できない" do
        book = book_by_other

        add(book, at: now.in_time_zone)

        expect(response).to have_http_status(:conflict)
        expect(wished_books).to be_empty
      end
    end

    it '結果公開後は追加できない' do
      book = book_by_other
      exchange.update!(matched_at: 1.day.ago)

      add(book)

      expect(response).to have_http_status(:conflict)
      expect(wished_books).to be_empty
    end

    it '参加していなければ見つからない' do
      book = book_by_other
      log_in_as(create(:user))

      add(book)

      expect(response).to have_http_status(:not_found)
    end

    # 本は交換会から引く。別の交換会の本を混ぜられると、希望リストが交換会をまたぐ
    it '別の交換会の本は見つからない' do
      other = create(:book, participation: create(:participation, exchange: create(:exchange)))

      add(other)

      expect(response).to have_http_status(:not_found)
    end

    it 'ログインしていなければログイン画面へ送る' do
      book = book_by_other
      log_out

      add(book)

      expect(response).to redirect_to(login_path)
    end
  end

  describe '#destroy' do
    it '希望から外せる' do
      book = book_by_other
      add(book)

      remove(book)

      expect(wished_books).to be_empty
    end

    # 穴が空いたままだと、次に足した1冊の順位が飛ぶ
    it '外した分だけ順位が詰まる' do
      books = Array.new(3) { book_by_other }
      books.each { add(it) }

      remove(books.first)

      expect(participation.wishes.reload.pluck(:position)).to eq([1, 2])
      expect(wished_books).to eq(books.drop(1))
    end

    # 別のタブで消したあとの再送信で落とすようなことではない
    it '希望していない本を外しても落ちない' do
      remove(book_by_other)

      expect(response).to redirect_to(exchange_path(exchange))
    end

    it '登録期間は外せない' do
      book = book_by_other
      add(book)

      remove(book, at: '2026-08-04T00:00:00+09:00'.in_time_zone)

      expect(response).to have_http_status(:conflict)
      expect(wished_books).to eq([book])
    end

    it '参加していなければ見つからない' do
      book = book_by_other
      log_in_as(create(:user))

      remove(book)

      expect(response).to have_http_status(:not_found)
    end
  end

  # 1冊外すと後ろの順位がすべて繰り上がる。カード1枚だけを差し替えると、
  # 繰り上がった他のカードの順位が古いまま残る
  describe 'Turbo Stream での応答' do
    let!(:turbo) { { headers: { 'Accept' => Mime[:turbo_stream].to_s } } }

    it '追加ではカードの一覧と希望リストの両方を差し替える' do
      add(book_by_other, **turbo)

      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body).to include('target="book_list"')
      expect(response.body).to include('target="wish_list"')
    end

    it '削除でもカードの一覧と希望リストの両方を差し替える' do
      book = book_by_other
      add(book)

      remove(book, **turbo)

      expect(response.body).to include('target="book_list"')
      expect(response.body).to include('target="wish_list"')
    end

    # 案内は希望の冊数で変わる。中身と一緒に差し替えないと、
    # 1冊足した直後だけ古い冊数が残る
    it '冊数の案内も新しい冊数で描き直す' do
      create(:book, participation:)

      add(book_by_other, **turbo)

      expect(response.body).to include('取得枠1冊に対して希望1冊')
    end

    # 開閉の状態を持つシートの外枠は差し替えの外に置く。中身ごと入れ替えると、
    # シートを開いて中の「希望から外す」を押した瞬間にシートが閉じる
    it '差し替えるのは希望リストの中身だけで、シートの外枠は含めない' do
      add(book_by_other, **turbo)

      expect(response.body).not_to include('wish-sheet')
    end

    # 差し替えも一覧の一経路。見えてよいのは登録した本人と成立後の受取人だけで、
    # ここはどちらでもない
    it 'ギフトコードが含まれない' do
      create(:book, participation:, gift_code: 'MYOWNGIFTCODE')

      add(book_by_other(gift_code: 'OTHERGIFTCODE'), **turbo)

      expect(response.body).not_to include('MYOWNGIFTCODE')
      expect(response.body).not_to include('OTHERGIFTCODE')
    end
  end
end
