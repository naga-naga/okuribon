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

    # 登録・編集・削除のすべてに、この画面から入れるようにする。
    # リンクは行き先ができてから足す（#22 の時点では行き先が無かった）
    describe '登録・編集・削除の導線' do
      it '登録期間中は登録ボタンが出る' do
        open_list

        expect(response.body).to include(new_exchange_book_path(exchange))
      end

      it '1冊も登録されていなくても登録ボタンが出る' do
        open_list

        expect(response.body).to include('まだ本は登録されていません')
        expect(response.body).to include(new_exchange_book_path(exchange))
      end

      it '登録期間外は登録ボタンが出ない' do
        outside_registration

        open_list

        expect(response.body).not_to include(new_exchange_book_path(exchange))
      end

      it '自分の本には編集と削除が出る' do
        mine = create(:book, participation:)

        open_list

        expect(response.body).to include(edit_exchange_book_path(exchange, mine))
        expect(response.body).to include('登録を取り消します')
      end

      # 消えるのは本だけではない。取得枠が1つ減り、その本への他の人の希望も消える
      it '削除の確認で取得枠が減ることを伝える' do
        create_list(:book, 2, participation:)

        open_list

        expect(response.body).to include('取得枠が2冊から1冊に減り')
      end

      # 自分の本は取得枠の数でもある。導線の有無だけで見分けさせると、
      # 登録期間を過ぎたとたんにどれが自分の本か分からなくなる
      it '自分の本には印が付く' do
        create(:book, participation:, title: '灯台守の一年')
        outside_registration

        open_list

        expect(response.body).to include('自分の本')
      end

      it '他人の本には印が付かない' do
        create(:book, participation: create(:participation, exchange:), title: '十三番目の便り')

        open_list

        expect(response.body).not_to include('自分の本')
      end

      it '他人の本には編集も削除も出ない' do
        theirs = create(:book, participation: create(:participation, exchange:))

        open_list

        expect(response.body).not_to include(edit_exchange_book_path(exchange, theirs))
      end

      # 押しても通らない導線を残さない
      it '登録期間外は自分の本にも編集と削除が出ない' do
        mine = create(:book, participation:)
        outside_registration

        open_list

        expect(response.body).not_to include(edit_exchange_book_path(exchange, mine))
        expect(response.body).not_to include('登録を取り消します')
      end
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

    # 主催者に特権はない（docs/spec.md 8.）。ここを書かないと、
    # 主催者には見えるのだろうと思ったまま入力することになる
    it '主催者にも見えないことが書かれている' do
      open_form

      expect(response.body).to include('主催者にも見えません')
    end

    # 必須は2項目だけ。印が無いと、任意の欄まで埋めないと進めないように見える
    it '必須の項目に印が付く' do
      open_form

      expect(response.body.scan('必須').size).to eq(2)
    end

    it '任意の項目にも印が付く' do
      open_form

      expect(response.body).to include('任意')
    end

    # 仕様の順ではなく書く気になる順に並べる。おすすめポイントが主役で、
    # 任意のあらすじは書けなくても先に進める位置に置く
    it 'タイトル・おすすめポイント・あらすじ・ギフトコードの順に並ぶ' do
      open_form

      order = ['タイトル', 'おすすめポイント', 'あらすじ', 'ギフトコード'].map { response.body.index(it) }
      expect(order).to eq(order.compact.sort)
    end

    # みんながいちばん読むところなので、書き出しの取っかかりを添える
    it 'おすすめポイントに書き出しの手がかりが出る' do
      open_form

      expect(response.body).to include('どこで手が止まった？')
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

    it '登録すると本の一覧へ戻る' do
      register

      expect(response).to redirect_to(exchange_books_path(exchange))
    end

    # 何冊でも登録できる。一覧を経由させると、1冊ごとに2画面を往復することになる
    it '続けて登録するときは登録フォームへ戻る' do
      post exchange_books_path(exchange),
           params: { book: { title: '銀河の果ての本屋', gift_code: 'GIFT-1234' },
                     continue: '登録して、続けてもう1冊' }

      expect(response).to redirect_to(new_exchange_book_path(exchange))
    end

    # 登録した冊数がそのまま取得枠になる。増えたことをその場で伝える
    it '登録したタイトルと取得枠を知らせる' do
      register

      expect(flash[:notice]).to include('銀河の果ての本屋')
      expect(flash[:notice]).to include('1冊')
    end

    # 何が足りないのかを入力欄まで返す。422 で止めるだけでは、
    # 保存されなかったことしか分からない
    it 'タイトルが空だと保存されず、理由が画面に出る' do
      expect { register(title: '') }.not_to(change { participation.books.count })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('タイトルを入力してください')
    end

    it 'ギフトコードが空だと保存されず、理由が画面に出る' do
      expect { register(gift_code: '') }.not_to(change { participation.books.count })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('ギフトコードを入力してください')
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

    # 直しに来て、やはり取り下げると決めることがある。一覧へ戻らせない
    it '編集画面からも削除できる' do
      open_form

      expect(response.body).to include('登録を取り消します')
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
