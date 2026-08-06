# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BooksController do
  let!(:user) { create(:user) }
  let!(:exchange) { create(:exchange, name: '夏の交換会') }
  let!(:participation) { create(:participation, user:, exchange:) }

  before { log_in_as(user) }

  describe '#index' do
    def open_list
      get exchange_books_path(exchange)
    end

    # 登録者を名前で撒くための入れ物。参加を伴わない本は作れない
    def book_by(display_name, **attributes)
      registrant = create(:participation, exchange:, user: create(:user, display_name:))
      create(:book, participation: registrant, **attributes)
    end

    it '参加者は開ける' do
      open_list

      expect(response).to have_http_status(:ok)
    end

    # 選ぶ材料は全員の本。自分の登録した本だけでは読み比べにならない
    it '全員の本が並ぶ' do
      create(:book, participation:, title: '自分の本')
      book_by('佐藤 花子', title: '他の人の本')

      open_list

      expect(response.body).to include('自分の本')
      expect(response.body).to include('他の人の本')
    end

    it '誰が登録したかが分かる' do
      book_by('佐藤 花子')

      open_list

      expect(response.body).to include('佐藤 花子')
    end

    # 数行のテキストを丸ごと並べると、一覧をざっと眺められなくなる
    it '長いあらすじは冒頭だけ出る' do
      book_by('佐藤 花子', summary: "#{'あ' * 200}ここは切られる")

      open_list

      expect(response.body).to include('あ' * 50)
      expect(response.body).not_to include('ここは切られる')
    end

    it '短いあらすじはそのまま出る' do
      book_by('佐藤 花子', summary: 'ある町に住む青年が、古い書店で一冊の本と出会う。')

      open_list

      expect(response.body).to include('ある町に住む青年が、古い書店で一冊の本と出会う。')
    end

    # 読み比べがこの画面の目的。本の詳細（#23）がまだ無いので、
    # ここで切ると続きを読む先がどこにも無い
    it 'おすすめポイントは全文出る' do
      book_by('佐藤 花子', recommendation: "#{'ぜ' * 200}最後まで読める")

      open_list

      expect(response.body).to include('最後まで読める')
    end

    # 見えるのは登録した本人と、成立後の受取人だけ。一覧はどちらの経路でもない
    it 'ギフトコードが含まれない' do
      create(:book, participation:, gift_code: 'MYOWNGIFTCODE')
      book_by('佐藤 花子', gift_code: 'OTHERGIFTCODE')

      open_list

      expect(response.body).not_to include('MYOWNGIFTCODE')
      expect(response.body).not_to include('OTHERGIFTCODE')
    end

    # 開くたびにカードの位置が入れ替わると、前に見た本を探し直すことになる
    it '登録順に並ぶ' do
      create(:book, participation:, title: '先に登録した本')
      create(:book, participation:, title: 'あとで登録した本')

      open_list

      expect(response.body.index('先に登録した本')).to be < response.body.index('あとで登録した本')
    end

    # 白紙で返すと、壊れているのかまだ誰も登録していないのか区別がつかない
    it '1冊も登録されていなければその旨を出す' do
      open_list

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('まだ本は登録されていません')
    end

    # 403 だと、招待されていない交換会の実在が URL を試すだけで確かめられる
    it '参加していなければ見つからない' do
      log_in_as(create(:user))

      open_list

      expect(response).to have_http_status(:not_found)
    end

    # 主催者は必ず参加者を兼ねるので、自分の交換会の一覧を開ける
    it '主催者も開ける' do
      owned = create(:exchange, owner: user)

      get exchange_books_path(owned)

      expect(response).to have_http_status(:ok)
    end

    it 'ログインしていなければログイン画面へ送る' do
      log_out

      open_list

      expect(response).to redirect_to(login_path)
    end

    # 読み取りは全フェーズで開いている。止めるのは書き込みだけ
    # （docs/spec.md 4. フェーズ）
    [
      ['準備中', '2026-07-25T00:00:00+09:00'],
      ['登録期間', '2026-08-04T00:00:00+09:00'],
      ['希望提出期間', '2026-08-11T00:00:00+09:00'],
      ['マッチング実行待ち', '2026-08-20T00:00:00+09:00'],
    ].each do |phase, now|
      it "#{phase}でも開ける" do
        exchange.update!(registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
                         registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
                         wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)

        travel_to(now) { open_list }

        expect(response).to have_http_status(:ok)
      end
    end

    it '結果公開でも開ける' do
      exchange.update!(matched_at: 1.day.ago)

      open_list

      expect(response).to have_http_status(:ok)
    end

  end

  # フェーズは日時から導出されるため、登録期間の外は日程をずらして作る。
  # 交換会の factory の既定は登録期間中
  def outside_registration
    exchange.update!(registration_starts_at: 3.weeks.from_now,
                     registration_ends_at: 4.weeks.from_now,
                     wish_ends_at: 5.weeks.from_now)
  end

  describe '#new' do
    def open_form
      get new_exchange_book_path(exchange)
    end

    it '登録期間中は開ける' do
      open_form

      expect(response).to have_http_status(:ok)
    end

    # 押しても通らないフォームを開かせない（docs/spec.md 6.4）
    it '登録期間外は開けない' do
      outside_registration

      open_form

      expect(response).to have_http_status(:conflict)
    end

    it '参加していなければ見つからない' do
      log_in_as(create(:user))

      open_form

      expect(response).to have_http_status(:not_found)
    end

    it 'ログインしていなければログイン画面へ送る' do
      log_out

      open_form

      expect(response).to redirect_to(login_path)
    end

    # 伏せ字にしておかないと、肩越しに覗かれるだけでギフトコードが渡る
    it 'ギフトコードの入力欄が伏せ字になっている' do
      open_form

      expect(response.body).to include('type="password"')
    end

    it '他人には見えないことが書かれている' do
      open_form

      expect(response.body).to include('他の参加者には見えません')
    end
  end

  describe '#create' do
    def register(**attributes)
      post exchange_books_path(exchange),
           params: { book: { title: '銀河の果ての本屋', gift_code: 'GIFT-1234' }.merge(attributes) }
    end

    it '本を登録できる' do
      expect { register }.to change { participation.books.count }.by(1)
    end

    it '登録した本人の本になる' do
      register

      expect(Book.last.participation).to eq(participation)
    end

    it 'あらすじ・URL・おすすめポイントも保存される' do
      register(summary: 'ある町の書店の話。', url: 'https://example.com/book',
               recommendation: '読み終わったあとに空が違って見える。')

      book = Book.last
      expect(book.summary).to eq('ある町の書店の話。')
      expect(book.url).to eq('https://example.com/book')
      expect(book.recommendation).to eq('読み終わったあとに空が違って見える。')
    end

    # 続けてもう1冊登録できるよう、着地先は一覧に揃える
    it '登録すると本の一覧へ戻る' do
      register

      expect(response).to redirect_to(exchange_books_path(exchange))
    end

    it 'タイトルが空だと保存されない' do
      expect { register(title: '') }.not_to(change { participation.books.count })
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'ギフトコードが空だと保存されない' do
      expect { register(gift_code: '') }.not_to(change { participation.books.count })
      expect(response).to have_http_status(:unprocessable_content)
    end

    # クライアントの時計ではなくサーバー側で判定する（docs/spec.md 4. フェーズ）
    it '登録期間外は登録できない' do
      outside_registration

      expect { register }.not_to(change { participation.books.count })
      expect(response).to have_http_status(:conflict)
    end

    it '結果公開後は登録できない' do
      exchange.update!(matched_at: 1.day.ago)

      expect { register }.not_to(change { participation.books.count })
      expect(response).to have_http_status(:conflict)
    end

    it '参加していなければ登録できない' do
      log_in_as(create(:user))

      expect { register }.not_to(change(Book, :count))
      expect(response).to have_http_status(:not_found)
    end

    it 'ログインしていなければ登録できない' do
      log_out

      expect { register }.not_to(change(Book, :count))
    end
  end

  # 他人の本。編集も削除も、自分の本にしか届かないことを確かめる入れ物
  def others_book(**attributes)
    create(:book, participation: create(:participation, exchange:), **attributes)
  end

  describe '#edit' do
    let!(:book) { create(:book, participation:, gift_code: 'GIFT-1234') }

    def open_form(target = book)
      get edit_exchange_book_path(exchange, target)
    end

    it '登録期間中は開ける' do
      open_form

      expect(response).to have_http_status(:ok)
    end

    it '登録期間外は開けない' do
      outside_registration

      open_form

      expect(response).to have_http_status(:conflict)
    end

    # 探し直させるのは手間でしかない。登録した本人には常時見えてよい値
    it 'ギフトコードが入力欄に入っている' do
      open_form

      expect(response.body).to include('GIFT-1234')
    end

    # 403 だと、その id の本が実在することを URL を試すだけで確かめられる
    it '他人の本は見つからない' do
      open_form(others_book)

      expect(response).to have_http_status(:not_found)
    end

    it '参加していなければ見つからない' do
      log_in_as(create(:user))

      open_form

      expect(response).to have_http_status(:not_found)
    end

    it 'ログインしていなければログイン画面へ送る' do
      log_out

      open_form

      expect(response).to redirect_to(login_path)
    end
  end

  describe '#update' do
    let!(:book) { create(:book, participation:, title: '前のタイトル') }

    def rename(target = book, **attributes)
      patch exchange_book_path(exchange, target),
            params: { book: { title: '新しいタイトル' }.merge(attributes) }
    end

    it '自分の本を編集できる' do
      rename

      expect(book.reload.title).to eq('新しいタイトル')
    end

    it '編集すると本の一覧へ戻る' do
      rename

      expect(response).to redirect_to(exchange_books_path(exchange))
    end

    it 'タイトルが空だと保存されない' do
      rename(title: '')

      expect(book.reload.title).to eq('前のタイトル')
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'ギフトコードを変更できる' do
      rename(gift_code: 'GIFT-5678')

      expect(book.reload.gift_code_for(user, at: Time.current)).to eq('GIFT-5678')
    end

    it '登録期間外は編集できない' do
      outside_registration

      rename

      expect(book.reload.title).to eq('前のタイトル')
      expect(response).to have_http_status(:conflict)
    end

    it '結果公開後は編集できない' do
      exchange.update!(matched_at: 1.day.ago)

      rename

      expect(book.reload.title).to eq('前のタイトル')
      expect(response).to have_http_status(:conflict)
    end

    it '他人の本は編集できない' do
      target = others_book(title: '他の人の本')

      rename(target)

      expect(target.reload.title).to eq('他の人の本')
      expect(response).to have_http_status(:not_found)
    end

    it 'ログインしていなければ編集できない' do
      log_out

      rename

      expect(book.reload.title).to eq('前のタイトル')
    end
  end

  describe '#destroy' do
    let!(:book) { create(:book, participation:) }

    def remove(target = book)
      delete exchange_book_path(exchange, target)
    end

    it '自分の本を削除できる' do
      expect { remove }.to change { participation.books.count }.by(-1)
    end

    it '削除すると本の一覧へ戻る' do
      remove

      expect(response).to redirect_to(exchange_books_path(exchange))
    end

    it '他人の本は削除できない' do
      target = others_book

      expect { remove(target) }.not_to(change(Book, :count))
      expect(response).to have_http_status(:not_found)
    end

    # 希望提出期間に入ってから消えると、取得枠の計算が壊れる
    it '登録期間外は削除できない' do
      outside_registration

      expect { remove }.not_to(change(Book, :count))
      expect(response).to have_http_status(:conflict)
    end

    it '結果公開後は削除できない' do
      exchange.update!(matched_at: 1.day.ago)

      expect { remove }.not_to(change(Book, :count))
      expect(response).to have_http_status(:conflict)
    end

    it '参加していなければ削除できない' do
      log_in_as(create(:user))

      expect { remove }.not_to(change(Book, :count))
      expect(response).to have_http_status(:not_found)
    end

    it 'ログインしていなければ削除できない' do
      log_out

      expect { remove }.not_to(change(Book, :count))
    end
  end
end
