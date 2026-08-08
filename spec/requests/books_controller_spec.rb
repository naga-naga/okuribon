# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BooksController do
  include ActionView::RecordIdentifier

  let!(:user) { create(:user) }
  let!(:exchange) { create(:exchange, name: '夏の交換会') }
  let!(:participation) { create(:participation, user:, exchange:) }

  before { log_in_as(user) }

  describe '#index' do
    def open_list
      get exchange_books_path(exchange)
    end

    # 印や導線はカード単位で確かめる。ページ全体の文字列を見ると、
    # 隣のカードや見出しに同じ字があったときに見分けがつかない
    def card_for(book)
      response.parsed_body.at_css("##{dom_id(book)}")
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

    # 閉じたカードは抜粋だが、折るのは CSS で、全文は最初から入れておく。
    # 開くたびにサーバーへ行くと、読み比べのたびに往復が挟まる
    it '長いあらすじも全文が入る' do
      book_by('佐藤 花子', summary: "#{'あ' * 200}最後まで読める")

      open_list

      expect(response.body).to include('最後まで読める')
    end

    it 'おすすめポイントも全文が入る' do
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

    describe '見出し' do
      # 冊数だけでは、まだ登録していない人がどれだけ残っているかが分からない
      it '冊数と参加人数が出る' do
        create(:book, participation:)
        book_by('佐藤 花子')

        open_list

        expect(response.body).to include('2冊')
        expect(response.body).to include('3人')
      end

      # 数週間かかるツールなので、開くたびに今なにをすべきかが分かるようにする
      it '登録期間中は希望の提出がいつからかを添える' do
        open_list

        expect(response.body).to include('おすすめポイントを読んで')
        expect(response.body).to include(I18n.l(exchange.wish_starts_at, format: :schedule))
      end

      # 一覧は全フェーズで開ける。どのフェーズで来ても、次にすることが書いてある
      {
        '準備中' => ['2026-07-25T00:00:00+09:00', '登録期間はまだ始まっていません'],
        '希望提出期間' => ['2026-08-11T00:00:00+09:00', '欲しい本を希望順に並べましょう'],
        'マッチング実行待ち' => ['2026-08-20T00:00:00+09:00', '希望の受付は終わりました'],
      }.each do |phase, (now, guide)|
        it "#{phase}にはその期間ですることが出る" do
          exchange.update!(registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
                           registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
                           wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)

          travel_to(now) { open_list }

          expect(response.body).to include(guide)
        end
      end

      it '結果公開後は結果が出ていることが分かる' do
        exchange.update!(matched_at: 1.day.ago)

        open_list

        expect(response.body).to include('交換の結果が公開されています')
      end
    end

    describe '絞り込み' do
      def open_mine
        get exchange_books_path(exchange, filter: :mine)
      end

      # 自分がどれを出したかを確かめる用。登録期間の外では編集の導線が消えるので、
      # 印だけでは冊数を数えづらい
      it '自分の本だけに絞れる' do
        create(:book, participation:, title: '自分の本')
        book_by('佐藤 花子', title: '他の人の本')

        open_mine

        expect(response.body).to include('自分の本')
        expect(response.body).not_to include('他の人の本')
      end

      it '絞り込みには自分の冊数が出る' do
        create_list(:book, 2, participation:)

        open_list

        expect(response.body).to include('自分の本 2')
      end

      # 見出しが数えるのは交換会全体。絞り込みで動くと、
      # まだ登録していない人が何人いるかが読めなくなる
      it '絞っても見出しの冊数と人数は全体のまま' do
        create(:book, participation:)
        book_by('佐藤 花子')

        open_mine

        expect(response.body).to include('2冊 ／ 3人')
      end

      it '知らない絞り込みは全件に倒す' do
        book_by('佐藤 花子', title: '他の人の本')

        get exchange_books_path(exchange, filter: 'その他')

        expect(response.body).to include('他の人の本')
      end

      # 取得枠は登録した冊数で決まる。空の一覧をそのまま返すと、
      # まだ受け取る権利が無いことがどこにも出ない
      it '自分が1冊も登録していなければその旨が出る' do
        book_by('佐藤 花子')

        open_mine

        expect(response.body).to include('まだ1冊も登録していません')
      end
    end

    describe 'カード' do
      # 一覧をざっと眺めるための密度で並べる。1列に積むと、
      # 12冊で画面を何度もめくることになる
      it '3カラムで並ぶ' do
        create(:book, participation:)

        open_list

        expect(response.body).to include('lg:grid-cols-3')
      end

      # 交換会の楽しみどころはおすすめポイント。あらすじを先に置くと、
      # どの本にも似た筋書きが並び、読み比べる材料が下に沈む
      it 'おすすめポイントがあらすじより前に出る' do
        book_by('佐藤 花子', summary: 'あらすじの本文', recommendation: 'おすすめの本文')

        open_list

        expect(response.body.index('おすすめの本文')).to be < response.body.index('あらすじの本文')
      end

      # 詳細画面へ飛ばすと列の中の位置を見失う。開いて読んで、また列に戻れるようにする
      it 'その場で開いて閉じられる' do
        create(:book, participation:)

        open_list

        expect(response.body).to include('続きを読む')
        expect(response.body).to include('閉じる')
      end

      # 空白のまま置くと、書き忘れなのか書くところが無いのか分からない
      it 'おすすめポイントが未記入ならその旨が出る' do
        book_by('佐藤 花子', recommendation: nil)

        open_list

        expect(response.body).to include('おすすめポイントが未記入です')
      end

      it '開くとストアへのリンクが出る' do
        book_by('佐藤 花子', url: 'https://example.com/books/1')

        open_list

        expect(response.body).to include('https://example.com/books/1')
        expect(response.body).to include('ストアで見る')
      end

      it 'URL が無ければストアへのリンクは出ない' do
        book_by('佐藤 花子', url: nil)

        open_list

        expect(response.body).not_to include('ストアで見る')
      end

      # 登録者が書いた URL をそのままリンクにすると、読み比べに来た人の
      # ブラウザで javascript: が走る
      it 'http と https 以外はリンクにしない' do
        book_by('佐藤 花子', url: "javascript:alert('x')")

        open_list

        expect(response.body).not_to include('javascript:alert')
      end
    end

    describe '希望リストの編集' do
      # 希望提出期間の中の1点。この画面でだけ希望リストが出る
      let!(:during_wish) { '2026-08-11T00:00:00+09:00'.in_time_zone }

      before do
        exchange.update!(registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
                         registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
                         wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)
      end

      def open_list_while_wishing
        travel_to(during_wish) { open_list }
      end

      def open_list_while_registering
        travel_to('2026-08-04T00:00:00+09:00'.in_time_zone) { open_list }
      end

      it '希望提出期間中は希望リストが常時出る' do
        book_by('佐藤 花子')

        open_list_while_wishing

        expect(response.body).to include('あなたの希望リスト')
      end

      it '希望提出期間中は各カードから希望に追加できる' do
        book = book_by('佐藤 花子')

        open_list_while_wishing

        expect(card_for(book).text).to include('希望に追加')
      end

      it '希望に入れた本には順位が出る' do
        book = book_by('佐藤 花子')
        create(:wish, participation:, book:, position: 1)

        open_list_while_wishing

        expect(card_for(book).text).to include('希望 1位')
        expect(card_for(book).text).to include('希望から外す')
      end

      # 一覧を読んでいる間ずっと、いま何冊・何位まで選んだかが見えている
      it '希望リストに順位と本が並ぶ' do
        book = book_by('佐藤 花子', title: '選んだ本')
        create(:wish, participation:, book:, position: 1)

        open_list_while_wishing

        expect(response.parsed_body.at_css('#wish_list').text).to include('選んだ本')
      end

      it '1冊も選んでいなければその旨が出る' do
        book_by('佐藤 花子')

        open_list_while_wishing

        expect(response.parsed_body.at_css('#wish_list').text).to include('まだ1冊も選んでいません')
      end

      it '取得枠と希望冊数が並ぶ' do
        register_own(2)
        wish_for_others(3)

        open_list_while_wishing

        expect(wish_list.text).to include('取得枠2冊に対して希望3冊')
      end

      # 取得枠は登録した冊数で決まる。何と同じ数なのかを書かないと、
      # 増やせる数なのか決まった数なのかが読み取れない
      it '取得枠が何で決まるかを添える' do
        register_own(2)

        open_list_while_wishing

        expect(response.parsed_body.at_css('aside').text).to include('2冊（登録した本と同じ）')
      end

      # 希望リストは長いほうが有利。上位が取られると下位へ降りていく
      it '取得枠の2倍に満たなければ増やすことを促す' do
        register_own(2)
        wish_for_others(3)

        open_list_while_wishing

        expect(wish_list.text).to include('もう少し増やすことを推奨します')
        expect(wish_list.text).to include('4冊以上')
      end

      it '取得枠の2倍以上あれば促さない' do
        register_own(2)
        wish_for_others(4)

        open_list_while_wishing

        expect(wish_list.text).not_to include('もう少し増やすことを推奨します')
      end

      # 登録期間はもう終わっている。増やすことを促しても、その人には届かない
      it '1冊も登録していなければ受け取れないことを伝える' do
        wish_for_others(3)

        open_list_while_wishing

        expect(wish_list.text).to include('受け取れる本はありません')
        expect(wish_list.text).not_to include('もう少し増やすことを推奨します')
      end

      # 狭い画面ではシートを畳んだままでも一覧を読み進められる。
      # 案内を開いた側だけに置くと、既定の状態では冊数がどこにも出ない
      it '畳んだシートにも冊数が出る' do
        register_own(2)
        wish_for_others(3)

        open_list_while_wishing

        expect(wish_summary.text).to include('枠2冊／希望3冊')
        expect(wish_summary.text).to include('あと1冊推奨')
      end

      it '畳んだシートでも足りていれば推奨を出さない' do
        register_own(2)
        wish_for_others(4)

        open_list_while_wishing

        expect(wish_summary.text).to include('枠2冊／希望4冊')
        expect(wish_summary.text).not_to include('推奨')
      end

      # 何人がその本を希望しているかは誰にも見えない（docs/spec.md 8.）。
      # 案内が数えるのは自分の希望だけで、他の人の希望では動かない
      it '他の人の希望は冊数に混ざらない' do
        register_own(1)
        wanted = book_by('佐藤 花子')
        create(:wish, participation:, book: wanted, position: 1)
        3.times { create(:wish, participation: create(:participation, exchange:), book: wanted, position: 1) }

        open_list_while_wishing

        expect(wish_list.text).to include('取得枠1冊に対して希望1冊')
      end

      def wish_list
        response.parsed_body.at_css('#wish_list')
      end

      # 畳んでいる間に出る1行。開いた側の案内と同じ文字が並ぶので、
      # 出し分けを確かめるにはここだけを見る
      def wish_summary
        wish_list.at_css('#wish_summary')
      end

      # 希望リストの末尾に1冊足す。順位は足した順の連番になる
      def wish_for(title)
        book = book_by('佐藤 花子', title:)
        create(:wish, participation:, book:, position: participation.wishes.count + 1)
        book
      end

      # 取得枠は自分が登録した冊数と同じ（docs/spec.md 3.）
      def register_own(count)
        count.times { create(:book, participation:) }
      end

      def wish_for_others(count)
        count.times { |index| wish_for("希望#{index + 1}") }
      end

      def rows
        wish_list.css('ol li')
      end

      def move_button(row, label)
        row.at_css(%(button[aria-label="#{label}"]))
      end

      # 並べ替えは順序だけをまとめて送る（docs/spec.md 6.2）。
      # ここで確かめるのは送る材料が画面に揃っていることまで。
      # つまんで動かす操作そのものはブラウザでしか確かめられない
      it '希望リストの並びをそのまま送れる' do
        first = wish_for('1冊目')
        second = wish_for('2冊目')

        open_list_while_wishing

        expect(wish_list.css('input[name="book_ids[]"]').pluck('value'))
          .to eq([first.id.to_s, second.id.to_s])
      end

      it '送り先は希望リストの更新' do
        wish_for('1冊目')

        open_list_while_wishing

        expect(wish_list.at_css('form')['action']).to eq(exchange_wish_list_path(exchange))
      end

      # ドラッグはつまめる人にしか使えない。順位を1つずつ動かす口を別に置く
      it '各行に順位を上げ下げする口がある' do
        wish_for('1冊目')
        wish_for('2冊目')

        open_list_while_wishing

        expect(wish_list.css('button[aria-label="順位を上げる"]').size).to eq(2)
        expect(wish_list.css('button[aria-label="順位を下げる"]').size).to eq(2)
      end

      # 端の行に行き先は無い。押せるように見えて何も起きないボタンを置かない
      it '先頭は上げられず、末尾は下げられない' do
        wish_for('1冊目')
        wish_for('2冊目')

        open_list_while_wishing

        expect(move_button(rows.first, '順位を上げる')[:disabled]).to be_present
        expect(move_button(rows.first, '順位を下げる')[:disabled]).to be_nil
        expect(move_button(rows.last, '順位を上げる')[:disabled]).to be_nil
        expect(move_button(rows.last, '順位を下げる')[:disabled]).to be_present
      end

      # 並べ替えは JavaScript でしか動かない。動かない環境に押せる口を残すと、
      # 押しても何も起きないボタンになる。カードからの追加・削除はそのまま通る
      it '並べ替えの口は JavaScript が動くまで出さない' do
        wish_for('1冊目')
        wish_for('2冊目')

        open_list_while_wishing

        expect(wish_list.css('li [hidden] button[aria-label="順位を上げる"]').size).to eq(2)
      end

      # 絞り込みは URL に残る（docs/spec.md 6.2）
      it '絞り込みを保ったまま並べ替えられる' do
        wish_for('1冊目')

        travel_to(during_wish) { get exchange_books_path(exchange, filter: 'mine') }

        expect(wish_list.at_css('input[name="filter"]')['value']).to eq('mine')
      end

      it '1冊も選んでいなければ並べ替えるものが無い' do
        book_by('佐藤 花子')

        open_list_while_wishing

        expect(wish_list.at_css('form')).to be_nil
      end

      # 自分の本は受け取れない（docs/spec.md 3.）。押しても通らないボタンを
      # 出しておいて断るのではなく、選べないことをその場で示す
      it '自分の本は選べないことが分かる' do
        book = create(:book, participation:)

        open_list_while_wishing

        expect(card_for(book).text).to include('自分の本は希望に選べません')
        expect(card_for(book).text).not_to include('希望に追加')
      end

      # 何人がその本を希望しているかは誰にも見せない（docs/spec.md 8.）。
      # 中身まで揃えた2冊を並べ、希望された側とされていない側で
      # カードが1文字も変わらないことを見る
      it '何人がその本を希望しているかは出ない' do
        registrant = create(:participation, exchange:, user: create(:user, display_name: '佐藤 花子'))
        same = { title: '同じ題の本', summary: '同じあらすじ', recommendation: '同じおすすめ' }
        wanted = create(:book, participation: registrant, **same)
        ignored = create(:book, participation: registrant, **same)
        3.times { create(:wish, participation: create(:participation, exchange:), book: wanted) }

        open_list_while_wishing

        expect(card_for(wanted).text).to eq(card_for(ignored).text)
      end

      # 登録期間はまだ選ぶ対象が揃っていない。出しても押せば断られる
      it '登録期間中は出ない' do
        book_by('佐藤 花子')

        open_list_while_registering

        expect(response.body).not_to include('あなたの希望リスト')
        expect(response.body).not_to include('希望に追加')
      end

      it 'マッチング実行待ちには出ない' do
        book_by('佐藤 花子')

        travel_to('2026-08-20T00:00:00+09:00'.in_time_zone) { open_list }

        expect(response.body).not_to include('あなたの希望リスト')
      end
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
        mine = create(:book, participation:, title: '灯台守の一年')
        outside_registration

        open_list

        expect(card_for(mine).text).to include('自分の本')
      end

      it '他人の本には印が付かない' do
        theirs = create(:book, participation: create(:participation, exchange:), title: '十三番目の便り')

        open_list

        expect(card_for(theirs).text).not_to include('自分の本')
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
