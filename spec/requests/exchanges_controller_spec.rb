# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExchangesController do
  include ActionView::RecordIdentifier

  let!(:user) { create(:user) }

  let!(:attributes) do
    {
      name: '夏の交換会',
      description: 'Kindle のみ。1000円前後を目安に。',
      webhook_url: 'https://discord.com/api/webhooks/1/abc',
      registration_starts_at: '2026-08-10T10:00',
      registration_ends_at: '2026-08-24T10:00',
      wish_ends_at: '2026-09-07T10:00',
    }
  end

  before { log_in_as(user) }

  # フェーズも次の締切も日時から導出されるため、現在時刻を固定してから作る
  describe '#index' do
    let!(:now) { '2026-08-04T00:00:00+09:00' }

    # 一覧に並ぶ条件は参加していること。招待されただけでは並ばない。
    # 主催者の参加は factory が作るので、自分が主催のときは重ねて作らない
    def participating(**attributes)
      exchange = create(:exchange, **attributes)
      exchange.participations.create_or_find_by!(user:)
      exchange
    end

    def registration_exchange(**attributes)
      participating(registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
                    registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
                    wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone,
                    **attributes)
    end

    # 主催をはじめる道はこの画面にしかない。共通ヘッダーに置いていた頃は、
    # 並ぶものが1件でもあると本文から消え、いちばん小さい字だけが残っていた
    it '参加している交換会があっても本文から交換会をつくれる' do
      registration_exchange(name: '夏の交換会')

      travel_to(now) { get exchanges_path }

      expect(response.parsed_body.at_css("main a[href='#{new_exchange_path}']").text)
        .to eq('交換会をつくる')
    end

    # 同じ行き先を1画面に2つ置くと、どちらが正しいのかを押す前に考えることになる
    it 'つくるボタンが1画面に1つしか無い' do
      registration_exchange(name: '夏の交換会')

      travel_to(now) { get exchanges_path }

      expect(response.parsed_body.css("a[href='#{new_exchange_path}']").size).to eq(1)
    end

    it '参加している交換会が並ぶ' do
      registration_exchange(name: '夏の交換会')

      travel_to(now) { get exchanges_path }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('夏の交換会')
    end

    # 招待されていない交換会が漏れると、名前と日程だけで実在が知れてしまう
    it '参加していない交換会は並ばない' do
      create(:exchange, name: 'よその交換会')

      travel_to(now) { get exchanges_path }

      expect(response.body).not_to include('よその交換会')
    end

    # 主催者は必ず参加者を兼ねるので、主催した交換会もここに並ぶ。
    # 並ばないと、作った本人が自分の交換会へ入る導線を持てない
    it '主催した交換会も並ぶ' do
      registration_exchange(owner: user, name: '主催した交換会')

      travel_to(now) { get exchanges_path }

      expect(response.body).to include('主催した交換会')
    end

    it '現在のフェーズが出る' do
      registration_exchange

      travel_to(now) { get exchanges_path }

      expect(response.body).to include('登録期間')
    end

    # 交換会へ入る導線は、参加したあとはこの一覧しかない
    it 'カードから交換会トップへ入れる' do
      exchange = registration_exchange

      travel_to(now) { get exchanges_path }

      expect(response.body).to include(exchange_path(exchange))
    end

    # 誰が仕切っている会なのかが分からないと、いくつも参加したときに
    # どれがどれだか見分けられない
    it '主催者名と参加人数が出る' do
      exchange = registration_exchange(owner: create(:user, display_name: 'みずき'))
      create(:participation, exchange:)

      travel_to(now) { get exchanges_path }

      expect(response.body).to include('主催 みずき')
      # 主催者・自分・足した1人で3人
      expect(response.body).to include('3人')
    end

    # 自分の名前を「主催」の横に出しても、誰のことか読み替える手間が増えるだけ
    it '自分が主催なら「あなた」と出る' do
      registration_exchange(owner: user)

      travel_to(now) { get exchanges_path }

      expect(response.body).to include('主催 あなた')
    end

    # フェーズと締切だけでは、この会で自分が何をすればよいかまでは分からない。
    # 文言は交換会トップと同じ置き場所（Exchanges::Todo）から引く
    it '自分の状態に応じた「すべきこと」の1行が出る' do
      exchange = registration_exchange
      create(:book, participation: exchange.participations.find_by!(user:))

      travel_to(now) { get exchanges_path }

      expect(response.body).to include('本を登録する')
    end

    it '次の締切が出る' do
      registration_exchange

      travel_to(now) { get exchanges_path }

      expect(response.body).to include('登録の締切')
      expect(response.body).to include('2026年8月8日 00:00')
    end

    # 準備中に待っているのは締切ではなく開始。「締切」と出すと、
    # まだ始まってもいない登録がもう終わるように読める
    it '準備中には登録期間の開始を出す' do
      participating(registration_starts_at: '2026-08-20T00:00:00+09:00'.in_time_zone,
                    registration_ends_at: '2026-08-27T00:00:00+09:00'.in_time_zone,
                    wish_ends_at: '2026-09-03T00:00:00+09:00'.in_time_zone)

      travel_to(now) { get exchanges_path }

      expect(response.body).to include('登録期間の開始')
      expect(response.body).to include('2026年8月20日 00:00')
    end

    # 日付だけでは、それが今日中なのか来週なのかを毎回読み解くことになる
    it '締切までの残りが出る' do
      registration_exchange(registration_ends_at: '2026-08-04T04:00:00+09:00'.in_time_zone)

      travel_to(now) { get exchanges_path }

      expect(response.body).to include('あと4時間')
    end

    # 終わった交換会に締切を出すと、まだ何かできるように読める
    it '結果公開には次の締切を出さない' do
      registration_exchange(matched_at: '2026-08-03T00:00:00+09:00'.in_time_zone)

      travel_to(now) { get exchanges_path }

      expect(response.body).to include('結果公開')
      # 見出しの下の一文が並び順の説明で「締切」に触れるので、カードの中だけを見る
      expect(response.parsed_body.at_css('li').text).not_to include('締切')
      expect(response.body).not_to include('2026年8月8日 00:00')
    end

    # 結果公開はもう終わっている。締切の欄が空くので、その日の行き先を代わりに置く
    it '結果公開には結果画面への導線と公開日時が出る' do
      exchange = registration_exchange(matched_at: '2026-08-03T00:00:00+09:00'.in_time_zone)

      travel_to(now) { get exchanges_path }

      expect(response.body).to include(exchange_result_path(exchange))
      expect(response.body).to include('2026年8月3日 00:00')
    end

    # 待っているのは主催者の操作で、日時では動かない。欄ごと消すと、
    # 締切を見落としたのか、そもそも無いのかが読み取れない
    it 'マッチング実行待ちには締切の代わりに「なし」を出す' do
      participating(registration_starts_at: '2026-07-01T00:00:00+09:00'.in_time_zone,
                    registration_ends_at: '2026-07-10T00:00:00+09:00'.in_time_zone,
                    wish_ends_at: '2026-07-20T00:00:00+09:00'.in_time_zone)

      travel_to(now) { get exchanges_path }

      expect(response.body).to include('マッチング実行待ち')
      expect(response.body).to include('することはありません')
      expect(response.body).not_to include('2026年7月20日 00:00')
    end

    # 並びが日時の1本の軸であることは、カードを見ても分からない
    it '見出しの下に並び順の説明が出る' do
      registration_exchange

      travel_to(now) { get exchanges_path }

      expect(response.body).to include('あなたの交換会')
      expect(response.body).to include('締切の近いものから並びます')
    end

    # 朱になるカードの枚数と一致する数字で、目で数えられるものを文字でも数えていた
    it '動いている件数は出さない' do
      registration_exchange
      participating(registration_starts_at: '2026-08-20T00:00:00+09:00'.in_time_zone,
                    registration_ends_at: '2026-08-27T00:00:00+09:00'.in_time_zone,
                    wish_ends_at: '2026-09-03T00:00:00+09:00'.in_time_zone)

      travel_to(now) { get exchanges_path }

      # 件数は等幅の span で包んでいたので、地の文とつなげて読む
      expect(response.parsed_body.text).not_to include('いま動いているのは')
    end

    # 件数を出さないなら、0を出す場面も無い
    it '動いているものが無くても、その言い分けを出さない' do
      participating(registration_starts_at: '2026-08-20T00:00:00+09:00'.in_time_zone,
                    registration_ends_at: '2026-08-27T00:00:00+09:00'.in_time_zone,
                    wish_ends_at: '2026-09-03T00:00:00+09:00'.in_time_zone)

      travel_to(now) { get exchanges_path }

      expect(response.body).not_to include('いま動いている交換会はありません')
      expect(response.body).to include('締切の近いものから並びます')
    end

    # 何も無い画面を白紙で返すと、壊れているのか参加していないのか区別がつかない
    describe '1つも参加していないとき' do
      before { travel_to(now) { get exchanges_path } }

      it '参加していないことを見出しで言う' do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('まだどこにも参加していません')
      end

      # 参加の入口は招待URLしかない
      it '招待URLから参加できることを書く' do
        expect(response.body).to include('招待URL')
      end

      # 本文が真っ白なこの画面でこそ、押してよいものだと分かる大きさが要る
      it '本文からも交換会をつくれる' do
        expect(response.parsed_body.at_css("main a[href='#{new_exchange_path}']")).to be_present
      end

      # 並ぶものが有るときと同じく、ボタンは1つ
      it 'つくるボタンが1画面に1つしか無い' do
        expect(response.parsed_body.css("a[href='#{new_exchange_path}']").size).to eq(1)
      end

      # 何人でどれくらいの期間かの見当が付かないと、つくる側は日時を決められない
      it '主催するときの目安を出す' do
        expect(response.body).to include('3人から十数人')
        expect(response.body).to include('登録に2週間')
      end
    end

    # 並び順を決めないと、開くたびにカードの位置が入れ替わる。
    # 細かい規則は Exchanges::Listing の spec が持つ
    it '次の締切が近いものから並ぶ' do
      registration_exchange(name: '夏の交換会')
      participating(name: '秋の交換会',
                    registration_starts_at: '2026-09-01T00:00:00+09:00'.in_time_zone,
                    registration_ends_at: '2026-09-08T00:00:00+09:00'.in_time_zone,
                    wish_ends_at: '2026-09-15T00:00:00+09:00'.in_time_zone)

      travel_to(now) { get exchanges_path }

      expect(response.body.index('夏の交換会')).to be < response.body.index('秋の交換会')
    end

    it 'ログインしていなければログイン画面へ送る' do
      log_out

      get exchanges_path

      expect(response).to redirect_to(login_path)
    end

    # ログイン済みの着地はここ。招待URLを除けば、交換会へ入る導線はこの一覧しかない
    it 'root から開ける' do
      registration_exchange(name: '夏の交換会')

      travel_to(now) { get root_path }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('夏の交換会')
    end

    # 登録した本人と、成立後の受取人だけに見える。一覧はどちらの経路でもない。
    # 自分が登録した本と受け取った本を並べて、gift_code_for が値を返す状態で確かめる。
    # 結果公開にするのは matched_at で、日時に関わらずフェーズが決まる
    it 'ギフトコードが含まれない' do
      exchange = registration_exchange(matched_at: '2026-08-03T00:00:00+09:00'.in_time_zone)
      participation = exchange.participations.find_by!(user:)
      create(:book, participation:, gift_code: 'MYOWNGIFTCODE')
      received = create(:book, participation: create(:participation, exchange:),
                               gift_code: 'RECEIVEDGIFTCODE')
      create(:assignment, book: received, participation:)

      travel_to(now) { get exchanges_path }

      expect(response.body).not_to include('MYOWNGIFTCODE')
      expect(response.body).not_to include('RECEIVEDGIFTCODE')
    end
  end

  # フェーズも残り時間も日時から導出されるため、現在時刻を固定してから作る。
  # 交換会ページは状態ヘッダーと本の一覧を1枚で出す
  describe '#show' do
    let!(:now) { '2026-08-04T00:00:00+09:00' }

    let!(:exchange) do
      create(:exchange, name: '夏の交換会', description: 'Kindle のみ。1000円前後を目安に。',
                        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
                        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
                        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)
    end

    let!(:participation) { create(:participation, user:, exchange:) }

    # 5つのフェーズの中の1点ずつ。フェーズは日時から導出されるので時刻で作る。
    # 結果公開だけは matched_at が入っているかどうかで決まる（publish!）。
    # 覚えさせる値ではないので let! ではなくメソッドで持つ
    def preparing_at
      '2026-07-25T00:00:00+09:00'
    end

    def wishing_at
      '2026-08-10T00:00:00+09:00'
    end

    def awaiting_at
      '2026-08-20T00:00:00+09:00'
    end

    def open_page(at: now)
      travel_to(at) { get exchange_path(exchange) }
    end

    def open_mine(at: now)
      travel_to(at) { get exchange_path(exchange, filter: :mine) }
    end

    # 公開は matched_at で決まる。日時カラムを戻しても公開済みであることは変わらない
    def publish!
      exchange.update!(matched_at: '2026-08-03T00:00:00+09:00'.in_time_zone)
    end

    # 印や導線はカード単位で確かめる。ページ全体の文字列を見ると、
    # 隣のカードや見出しに同じ字があったときに見分けがつかない
    def card_for(book)
      response.parsed_body.at_css("##{dom_id(book)}")
    end

    # カードを積む器。並べ方はここの class にしか現れない
    def card_stack
      response.parsed_body.at_css('#book_list > ul')
    end

    # 本文を束ねる段。開いた形はここの class で決まる
    def card_body(book)
      card_for(book).at_css('div')
    end

    # まだ開いていないカードで見えているもの。伏せてあるものは hidden か invisible を
    # 持つ。開閉で見た目がどれだけ動くかは、この差でしか見られない
    def closed_card(book)
      card_for(book).dup.tap { |card| card.css('.hidden, .invisible, [hidden]').each(&:remove) }
    end

    # 登録者を名前で作るための入れ物。参加を伴わない本は作れない
    def book_by(display_name, **attributes)
      registrant = create(:participation, exchange:, user: create(:user, display_name:))
      create(:book, participation: registrant, **attributes)
    end

    # 状況の3つの数字。枠の位置は動かさず中身だけがフェーズで入れ替わるので、
    # ラベルと値を組で読む。値だけを見ると、入れ替わったのか数が変わったのかが分からない
    def stats
      response.parsed_body.css('dl[aria-label="状況"] > div')
              .map { |cell| cell.css('dt, dd').map { it.text.strip } }
    end

    # 希望リストは選んでいる間と、提出したものを読み返す間の両方に出る。
    # 同じ場所を指すので、読む先も1つにしておく
    def wish_list
      response.parsed_body.at_css('#wish_list')
    end

    def rows
      wish_list.css('ol li')
    end

    # つまんでいる間だけの描き分け。落とせば消えるように、行と中身の
    # どちらも data-dragging の変種で書く
    def dragging_styles(row)
      [row, *row.css('*')].flat_map { it['class'].to_s.split }.grep(/dragging/)
    end

    # 希望リストの末尾に1冊足す。順位は足した順の連番になる
    def wish_for(title)
      book = book_by('佐藤 花子', title:)
      create(:wish, participation:, book:, position: participation.wishes.count + 1)
      book
    end

    def wish_for_others(count)
      count.times { |index| wish_for("希望#{index + 1}") }
    end

    # 希望を出し入れするボタン。追加も削除も同じパスを持ち、button_to なので form になる。
    # ボタンが外れたことをラベルの文字で確かめると、言い方を変えただけで通ってしまう
    def wish_form(book)
      card_for(book).at_css(%(form[action="#{exchange_book_wish_path(exchange, book)}"]))
    end

    def register_own(count)
      count.times { create(:book, participation:) }
    end

    it '参加者は開ける' do
      open_page

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('夏の交換会')
    end

    # 403 だと、招待されていない交換会の実在が URL を試すだけで確かめられる
    it '参加していなければ見つからない' do
      log_in_as(create(:user))

      open_page

      expect(response).to have_http_status(:not_found)
    end

    # 主催者は必ず参加者を兼ねるので、自分の交換会を開ける
    it '主催者も開ける' do
      owned = create(:exchange, owner: user, name: '主催した交換会')

      travel_to(now) { get exchange_path(owned) }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('主催した交換会')
    end

    it 'ログインしていなければログイン画面へ送る' do
      log_out

      open_page

      expect(response).to redirect_to(login_path)
    end

    # 読み取りは5フェーズすべてで開いている。止めるのは書き込みだけ
    it '結果公開でも開ける' do
      publish!

      open_page

      expect(response).to have_http_status(:ok)
    end

    # 主催者管理画面へ辿り着く経路はこのページだけ。交換会一覧は主催と参加を
    # 区別せずに並べるので、ここに無いと入口を持てない
    it '主催者には主催者管理画面への導線が出る' do
      owned = create(:exchange, owner: user)

      travel_to(now) { get exchange_path(owned) }

      expect(response.body).to include(exchange_management_path(owned))
    end

    # 押しても 404 になるリンクを見せない。主催者以外にはその画面の
    # 存在自体を知らせない
    it '主催者以外には導線が出ない' do
      open_page

      expect(response.body).not_to include(exchange_management_path(exchange))
    end

    # 交換会名と主催者名はこの画面が持つ。共通ヘッダーは画面をまたいで
    # 中身を変えないので、現在地の名前はパンくずに入らない
    it 'パンくずは交換会一覧までで、この画面は入らない' do
      open_page

      expect(breadcrumb).to eq('交換会一覧' => exchanges_path)
    end

    it '主催者名が出る' do
      exchange.owner.update!(display_name: '佐藤 花子')

      open_page

      expect(response.body).to include('主催 佐藤 花子')
    end

    # 自分の名前を出しても、誰のことか読み替える手間が増えるだけ
    it '自分が主催なら「あなた」と書く' do
      owned = create(:exchange, owner: user)

      travel_to(now) { get exchange_path(owned) }

      expect(response.body).to include('主催 あなた')
    end

    # 現在のフェーズ名だけを出すと、それが5つのうちのどこで、次に何が来るのかが
    # 読み取れない。数週間かかるツールで、道のりを覚えている前提は置けない
    describe 'フェーズ帯' do
      def band
        response.parsed_body.css('ol[aria-label="フェーズ"] li')
      end

      it '5つのフェーズが順に並ぶ' do
        open_page

        expect(band.map { it.text.strip })
          .to eq(['準備中', '登録期間', '希望提出期間', 'マッチング実行待ち', '結果公開'])
      end

      {
        '2026-07-25T00:00:00+09:00' => '準備中',
        '2026-08-04T00:00:00+09:00' => '登録期間',
        '2026-08-10T00:00:00+09:00' => '希望提出期間',
        '2026-08-20T00:00:00+09:00' => 'マッチング実行待ち',
      }.each do |at, phase_name|
        it "#{at} には「#{phase_name}」に印が付く" do
          open_page(at:)

          expect(band.select { it['aria-current'] == 'step' }.map { it.text.strip }).to eq([phase_name])
        end
      end

      it '結果公開にも印が付く' do
        publish!

        open_page

        expect(band.select { it['aria-current'] == 'step' }.map { it.text.strip }).to eq(['結果公開'])
      end

      # フェーズは日時から導出されるもので、選べる先ではない。
      # タブの形に寄せると押せると読まれる
      it 'リンクにも button にもならない' do
        open_page

        expect(response.parsed_body.css('ol[aria-label="フェーズ"] a, ol[aria-label="フェーズ"] button')).to be_empty
      end
    end

    # 数週間ぶりに開いた人が、その日なにをすればよいかをここだけで掴む。
    # 文言そのものは spec/services/exchanges/todo_spec.rb が押さえる。
    # ここで見るのは、5つのフェーズすべてで出ることと、並びが動かないこと
    describe 'あなたがすること' do
      # 準備中・登録期間・希望提出期間・マッチング実行待ちの4つは日時で決まる。
      # 結果公開だけは matched_at が入っているかどうかで決まる
      {
        '2026-07-25T00:00:00+09:00' => 'いまは待つだけです',
        '2026-08-04T00:00:00+09:00' => '本を登録する',
        '2026-08-10T00:00:00+09:00' => '希望リスト',
        '2026-08-20T00:00:00+09:00' => '結果を待ちます',
      }.each do |at, headline|
        it "#{at} には「#{headline}」が出る" do
          open_page(at:)

          expect(response.body).to include('あなたがすること')
          expect(response.body).to include(headline)
        end
      end

      it '結果公開には受け取った冊数が出る' do
        publish!
        create(:assignment, participation:, book: create(:book, participation: create(:participation, exchange:)))

        open_page

        expect(response.body).to include('あなたに1冊届いています')
      end

      # 1冊も登録していない人は受け取る権利が無い。
      # 締切を過ぎてからでは取り返せないので、期間中に伝える
      it '1冊も登録していなければ、受け取れる本が0冊になることが分かる' do
        open_page

        expect(response.body).to include('受け取れる本が0冊になります')
      end

      # 希望を出さなくても受け取る権利は失わないが、選べるものが余り物だけになる
      it '希望リストが空なら、そのことが分かる' do
        create(:book, participation:)

        open_page(at: wishing_at)

        expect(response.body).to include('希望リストがまだ空です')
      end

      # 導線は「あなたがすること」の直下に置き、独立した段を作らない。
      # 押せる期間は writable? から引く。フェーズ名で条件を書き直すと、
      # 押しても断られるボタンがどこかのフェーズに残る
      it '登録期間には本を登録する導線が出る' do
        open_page

        expect(response.body).to include(new_exchange_book_path(exchange))
      end

      [['準備中', '2026-07-25T00:00:00+09:00'],
       ['希望提出期間', '2026-08-10T00:00:00+09:00'],
       ['マッチング実行待ち', '2026-08-20T00:00:00+09:00']].each do |phase_name, at|
        it "#{phase_name}には本を登録する導線が出ない" do
          open_page(at:)

          expect(response.body).not_to include(new_exchange_book_path(exchange))
        end
      end

      # 主催者だけが、実行待ちに待つ以外の道を持つ。ほかの参加者が待っているのは
      # その人の操作で、日時では動かない
      it 'マッチング実行待ちの参加者には実行の導線が出ない' do
        open_page(at: awaiting_at)

        expect(response.body).to include('結果を待ちます')
        expect(response.body).not_to include(new_exchange_management_matching_path(exchange))
      end
    end

    # 主催者だけが、実行待ちに待つ以外の道を持つ。この画面の交換会は既定では
    # 別の人が主催しているので、日程はそのまま使い、主催者だけを自分に付け替える。
    # 参加はもう成立しているので、主催が移っても影響を受けない
    describe '主催者のマッチング実行' do
      before { exchange.update!(owner: user) }

      # 待つだけと書くと、自分が押すまで結果が出ないことがどこにも出ない
      it 'マッチング実行待ちにはマッチングの実行がすることになる' do
        open_page(at: awaiting_at)

        expect(response.body).to include('マッチングを実行する')
        expect(response.body).not_to include('結果を待ちます')
      end

      it '実行へ向かう導線が出る' do
        open_page(at: awaiting_at)

        expect(response.body).to include(new_exchange_management_matching_path(exchange))
      end

      # マッチングは一度だけ実行できる。残すと、押しても断られる導線になる
      it '実行済みなら実行の導線が出ない' do
        publish!

        open_page(at: awaiting_at)

        expect(response.body).not_to include(new_exchange_management_matching_path(exchange))
      end

      it '締切前には実行の導線が出ない' do
        open_page(at: wishing_at)

        expect(response.body).not_to include(new_exchange_management_matching_path(exchange))
      end
    end

    describe '締切' do
      it '次の締切が出る' do
        open_page

        expect(response.body).to include('登録の締切')
        expect(response.body).to include('2026年8月8日 00:00')
      end

      # 久しぶりに開く人が最初に知りたいのは、日付そのものより残りの長さ
      it '次の締切までの残りが出る' do
        open_page

        expect(response.body).to include('あと4日')
      end

      # 締切当日に「あと0日」と出ても、今日中なのかどうか読み取れない
      it '締切まで残り数時間なら時間で出る' do
        open_page(at: '2026-08-07T19:00:00+09:00')

        expect(response.body).to include('あと5時間')
      end

      # 待っているのは主催者の操作で、日時では動かない。枠を空けると、
      # 締切を見落としたのか、そもそも無いのかが読み取れない
      it 'マッチング実行待ちは締切が無いことを書く' do
        open_page(at: awaiting_at)

        expect(response.body).to include('ありません')
        expect(response.body).to include('することはもうありません')
        expect(response.body).not_to include('あと')
      end

      # 結果公開は締切の枠を、公開日時と結果画面への入口に差し替える
      it '結果公開には公開日時と結果への入口が出る' do
        publish!

        open_page

        expect(response.body).to include('2026年8月3日 00:00')
        expect(response.body).to include('結果を見る')
        expect(response.body).to include(exchange_result_path(exchange))
      end

      # 押しても 404 になるリンクは見せない
      it '結果公開前には結果への入口が出ない' do
        open_page

        expect(response.body).not_to include(exchange_result_path(exchange))
      end
    end

    # 枠の位置は動かさず、中身だけをフェーズで入れ替える
    describe '状況の数字' do
      before do
        create_list(:participation, 2, exchange:)
        create_list(:book, 2, participation:)
        create(:book, participation: create(:participation, exchange:))
      end

      {
        '2026-07-25T00:00:00+09:00' => ['参加者', '本', '取得枠'],
        '2026-08-04T00:00:00+09:00' => ['参加者', '本', '取得枠'],
        '2026-08-10T00:00:00+09:00' => ['本', '取得枠', '希望'],
        '2026-08-20T00:00:00+09:00' => ['本', '取得枠', '提出した希望'],
      }.each do |at, labels|
        it "#{at} には #{labels.join(' ／ ')} が並ぶ" do
          open_page(at:)

          expect(stats.map(&:first)).to eq(labels)
        end
      end

      # 登録した冊数がそのまま受け取れる冊数になる。全体の冊数と並べておかないと、
      # 自分が何冊登録したのかを確かめる先がどこにも無い
      it '登録期間には参加者数・冊数・取得枠が入る' do
        open_page

        expect(stats).to eq([['参加者', '5人'], ['本', '3冊'], ['取得枠', '2冊']])
      end

      # まだ登録が始まっていないだけで、受け取れないわけではない。
      # 0冊と書くと、締め出されているようにも読める
      it '準備中の取得枠は0冊ではなく — と書く' do
        open_page(at: preparing_at)

        expect(stats.last).to eq(['取得枠', '—'])
      end

      # 登録の締切を過ぎたら、まだ登録していない人が何人残っているかを数える用が無い。
      # 代わりに、取得枠に対して足りているかを確かめられる数を出す
      it '希望提出期間には自分の希望冊数が入る' do
        create(:wish, participation:, book: book_by('佐藤 花子'), position: 1)

        open_page(at: wishing_at)

        expect(stats).to eq([['本', '4冊'], ['取得枠', '2冊'], ['希望', '1冊']])
      end

      # 結果が出たあとに数えるのは、何冊が渡って何冊が戻ったか
      it '結果公開は成立と返却の内訳になる' do
        received = book_by('佐藤 花子')
        create(:assignment, book: received, participation:)
        publish!

        open_page

        expect(stats).to eq([['本', '4冊'], ['成立', '1冊'], ['返却', '3冊']])
      end

      # 絞り込みで動かすと、登録がどこまで進んだのかが読めなくなる
      it '自分の本に絞っても交換会全体のまま' do
        open_mine

        expect(stats).to eq([['参加者', '5人'], ['本', '3冊'], ['取得枠', '2冊']])
      end
    end

    # 状態ヘッダーの下には十数枚のカードが続く。読み進めた先で 6.1 の3点が
    # 視界から消えないよう、畳んだ帯を上部に残す
    describe '畳んだ帯' do
      def bar
        response.parsed_body.at_css('[data-state-header-target="bar"]')
      end

      it '交換会名・フェーズ・すべきこと・締切までの残りが並ぶ' do
        open_page

        expect(bar.text).to include('夏の交換会')
        expect(bar.text).to include('登録期間')
        expect(bar.text).to include('本を登録する')
        expect(bar.text).to include('あと4日')
      end

      # 畳みは JavaScript が動いてから効く。動かない環境では帯が出ないだけで、
      # 状態ヘッダーはそのまま読める
      it '既定では隠れている' do
        open_page

        expect(bar).to be_key('hidden')
      end

      it 'JavaScript が無くても状態ヘッダーは読める' do
        open_page

        expect(response.parsed_body.at_css('dl[aria-label="状況"]')).to be_present
        expect(response.parsed_body.at_css('ol[aria-label="フェーズ"]')).to be_present
      end

      # 帯に出す残りは状態ヘッダーと同じ数を指す。別々に組むと、片方だけが
      # 古い数え方で残る
      it '締切を持たないフェーズには残りを出さない' do
        open_page(at: awaiting_at)

        expect(bar.text).to include('マッチング実行待ち')
        expect(bar.text).not_to include('締切まで')
      end

      # 取得枠に対して希望が足りているかは、その期間にいちばん確かめたい数になる
      it '希望提出期間には希望の冊数と取得枠が入る' do
        register_own(2)
        wish_for_others(3)

        open_page(at: wishing_at)

        expect(bar.text).to include('希望 3冊')
        expect(bar.text).to include('枠 2冊')
      end

      # 数を出すのは希望提出期間に限る。ほかの期間は取得枠に対して足りているかを
      # 確かめる用が無く、帯の1行を埋めるだけになる
      it '希望提出期間のほかには冊数を入れない' do
        register_own(2)

        open_page

        expect(bar.text).not_to include('枠 2冊')
      end
    end

    # 読むのは本を登録する直前なので、畳まずに出したままにする
    describe '概要と日程' do
      def overview
        response.parsed_body.at_css('section[aria-label="概要と日程"]')
      end

      # 押す直前に1クリック挟ませない。畳むボタンそのものを持たない
      it '畳まずに出す' do
        open_page

        expect(overview).to be_present
        expect(overview.at_css('details, summary')).to be_nil
      end

      # 対応ストアや価格帯の目安が書かれている。本を選ぶ前に読む必要がある
      it '概要が入る' do
        open_page

        expect(overview.text).to include('Kindle のみ。1000円前後を目安に。')
      end

      # 概要は自由記述で長さに上限が無い。状態ヘッダーの中に入れると、
      # 概要の長さで締切と状況の数字の位置が動く
      it '状態ヘッダーの外に置く' do
        open_page

        expect(overview.at_css('dl[aria-label="状況"]')).to be_nil
      end

      # 動かせる期間だけを並べる。結果公開は主催者の実行で起きて日時では決まらない
      it '各期間の範囲が入る' do
        open_page

        schedule = overview.text
        expect(schedule).to include('2026年8月1日 00:00 — 2026年8月8日 00:00')
        expect(schedule).to include('2026年8月8日 00:00 — 2026年8月15日 00:00')
      end
    end

    # 資料が狙っているのは、フェーズが変わっても目の置き場所が動かないこと。
    # 左は「あなたがすること」と操作、右は締切と状況の数字。
    # 締切だけは次の節目が無いフェーズで言い方が変わるので、位置ではなく前後関係で見る
    describe '画面の並び' do
      def positions(body, phase_name)
        { phase: body.index(phase_name), todo: body.index('あなたがすること'),
          stats: body.index('取得枠'), books: body.index('みんなの本') }
      end

      {
        '2026-07-25T00:00:00+09:00' => '準備中',
        '2026-08-04T00:00:00+09:00' => '登録期間',
        '2026-08-10T00:00:00+09:00' => '希望提出期間',
        '2026-08-20T00:00:00+09:00' => 'マッチング実行待ち',
      }.each do |at, phase_name|
        it "#{at} でも フェーズ帯 → あなたがすること → 状況の数字 → 本の一覧 の順に並ぶ" do
          open_page(at:)

          found = positions(response.body, phase_name)
          expect(found.values).to all(be_present)
          expect(found.values).to eq(found.values.sort)
        end
      end

      # 締切は「あなたがすること」と状況の数字のあいだに入る。
      # 数字より上に置くと、まず読むべき行動から目が離れる
      it '締切は「あなたがすること」と状況の数字のあいだに出る' do
        open_page

        found = positions(response.body, '登録期間')
        deadline = response.body.index('登録の締切')
        expect(deadline).to be_between(found[:todo], found[:stats])
      end
    end

    # 交換会を開くと本が並んでいる。
    # 読み取りは5フェーズすべてで開いており、フェーズで変わるのは書き込みの操作だけ
    describe '本の一覧' do
      # 選ぶ材料は全員の本。自分の登録した本だけでは読み比べにならない
      it '全員の本が並ぶ' do
        create(:book, participation:, title: '自分の本')
        book_by('佐藤 花子', title: '他の人の本')

        open_page

        expect(response.body).to include('自分の本')
        expect(response.body).to include('他の人の本')
      end

      it '誰が登録したかが分かる' do
        book_by('佐藤 花子')

        open_page

        expect(response.body).to include('佐藤 花子')
      end

      # 閉じたカードは抜粋だが、折るのは CSS で、全文は最初から入れておく。
      # 開くたびにサーバーへ行くと、読み比べのたびに往復が挟まる
      it '長いあらすじも全文が入る' do
        book_by('佐藤 花子', summary: "#{'あ' * 200}最後まで読める")

        open_page

        expect(response.body).to include('最後まで読める')
      end

      it 'おすすめポイントも全文が入る' do
        book_by('佐藤 花子', recommendation: "#{'ぜ' * 200}最後まで読める")

        open_page

        expect(response.body).to include('最後まで読める')
      end

      # 開くたびにカードの位置が入れ替わると、前に見た本を探し直すことになる
      it '登録順に並ぶ' do
        create(:book, participation:, title: '先に登録した本')
        create(:book, participation:, title: 'あとで登録した本')

        open_page

        expect(response.body.index('先に登録した本')).to be < response.body.index('あとで登録した本')
      end

      # 白紙で返すと、壊れているのかまだ誰も登録していないのか区別がつかない
      it '1冊も登録されていなければその旨を出す' do
        open_page

        expect(response.body).to include('まだ本は登録されていません')
      end

      [['準備中', '2026-07-25T00:00:00+09:00'],
       ['希望提出期間', '2026-08-10T00:00:00+09:00'],
       ['マッチング実行待ち', '2026-08-20T00:00:00+09:00']].each do |phase_name, at|
        it "#{phase_name}でも本が並ぶ" do
          book_by('佐藤 花子', title: '十三番目の便り')

          open_page(at:)

          expect(response.body).to include('十三番目の便り')
        end
      end
    end

    # 並ぶ本がまだ無いフェーズ。空白のまま落とすと、
    # 読み込みに失敗したのか、まだ誰も登録していないのかが読み取れない
    describe '準備中' do
      def open_preparing
        open_page(at: preparing_at)
      end

      def book_list
        response.parsed_body.at_css('#book_list')
      end

      # 空なのは、まだ誰も登録していないからではなく、登録できる人がまだ居ないため。
      # 登録期間と同じ文にすると、誰かの登録を待っているように読める
      it '登録が始まれば並ぶことを書く' do
        open_preparing

        expect(book_list.text).to include('まだ本は登録されていません')
        expect(book_list.text).to include('登録期間が始まると、ここに並びます')
      end

      it '登録期間に入ったら誰かの登録を待つ言い方に変わる' do
        open_page

        expect(book_list.text).to include('誰かが登録すると、ここに並びます')
        expect(book_list.text).not_to include('登録期間が始まると')
      end

      # 取得枠に0冊と書くと受け取れないと読めるが、まだ登録が始まっていないだけ
      it '状況の数字は参加者と0冊と — になる' do
        create_list(:participation, 2, exchange:)

        open_preparing

        expect(stats).to eq([['参加者', '4人'], ['本', '0冊'], ['取得枠', '—']])
      end
    end

    describe '一覧の見出し' do
      # 参加人数も取得枠も状態ヘッダーが上で出している。
      # 同じページに2つ載せると、同じ数字が縦に2度並ぶ
      it '並んでいる冊数だけを添える' do
        create(:book, participation:)
        book_by('佐藤 花子')

        open_page

        expect(response.parsed_body.at_css('h2').parent.text).to include('2冊')
      end

      # ギフトコードが一覧に並ばないことは、期待して探しに来る人がいるので毎回書く
      it '結果公開後は誰に渡ったかを読む並びだと断る' do
        publish!

        open_page

        expect(response.parsed_body.at_css('h2').parent.text).to include('誰に渡ったか')
      end
    end

    describe '絞り込み' do
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

        open_page

        expect(response.body).to include('自分の本 2')
      end

      # 見出しの冊数はいま並んでいる数。交換会全体の数は状態ヘッダーが出す
      it '絞ると見出しの冊数も絞った数になる' do
        create(:book, participation:)
        book_by('佐藤 花子')

        open_mine

        expect(response.parsed_body.at_css('h2').parent.text).to include('1冊')
      end

      it '知らない絞り込みは全件に倒す' do
        book_by('佐藤 花子', title: '他の人の本')

        travel_to(now) { get exchange_path(exchange, filter: 'その他') }

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
      # カードは縦1列に積む。横に並べると、1枚開いたときに以降のカードが
      # マスの中で総入れ替えになり、読み比べの途中でどこまで見たかを見失う
      it '1列に積まれる' do
        create(:book, participation:)

        open_page

        expect(card_stack['class'].split).not_to include(a_string_matching(/grid-cols/))
      end

      # 開いた1枚が他のカードの居場所に触れると、読み比べの列がその場で崩れる。
      # 開いても伸びるのは自分の高さだけにする
      it '開いてもカードの居場所が変わらない' do
        book = create(:book, participation:)

        open_page

        expect(card_for(book)['class'].split).not_to include(a_string_matching(/col-span/))
      end

      # 本文の脇に段を作ると、その段は幅を譲らないので狭い画面で本文が削られる。
      # 開いても本文の置き場所は動かさない
      it '開いても本文の脇に段が出ない' do
        book = create(:book, participation:)

        open_page

        expect(card_body(book)['class'].split).not_to include(a_string_matching(/flex-row/))
      end

      # 開くボタンが消えて別の場所に閉じるボタンが現れると、押した指の先でボタンが入れ替わる。
      # 同じ1つのボタンの文字だけを差し替える
      it '開くボタンと閉じるボタンが同じ場所にある' do
        book = create(:book, participation:)

        open_page

        toggle = card_for(book).css('[data-book-card-target="toggle"]')
        expect(toggle.size).to eq(1)
        expect(toggle.text).to include('続きを読む').and include('閉じる')
      end

      # 折って隠れている本文が無ければ、押しても何も起きないボタンになる。
      # 何行に折れるかはブラウザでしか測れないので、伏せて出しておき、
      # 測ってから出す。JavaScript が無ければ出ないままにする
      it '開くボタンは伏せて出し、折られているかを測ってから出す' do
        book = create(:book, participation:)

        open_page

        expect(closed_card(book).text).not_to include('続きを読む')
        expect(card_for(book).at_css('[data-book-card-target~="toggle"]')).to be_present
      end

      # 開く前と後で、増えるのは折りたたまれていた本文だけにする。
      # 見出しやボタンがそのとき初めて現れると、同じカードが別の顔で出てくる
      it 'おすすめポイントとあらすじの見出しが開く前から出ている' do
        book = book_by('佐藤 花子', summary: 'あらすじの本文', recommendation: 'おすすめの本文')

        open_page

        expect(closed_card(book).text).to include('おすすめポイント').and include('あらすじ')
      end

      # 題が大きくなると折り返しの位置まで変わり、同じ本を読み直すことになる
      it '開いても文字の大きさが変わらない' do
        book = book_by('佐藤 花子')

        open_page

        resized = card_for(book).css('*').select { it['class'].to_s.include?('group-data-open:text-') }
        expect(resized).to be_empty
      end

      # 交換会の楽しみどころはおすすめポイント。あらすじを先に置くと、
      # どの本にも似た筋書きが並び、読み比べる材料が下に沈む
      it 'おすすめポイントがあらすじより前に出る' do
        book_by('佐藤 花子', summary: 'あらすじの本文', recommendation: 'おすすめの本文')

        open_page

        expect(response.body.index('おすすめの本文')).to be < response.body.index('あらすじの本文')
      end

      # 詳細画面へ飛ばすと列の中の位置を見失う。開いて読んで、また列に戻れるようにする
      it 'その場で開いて閉じられる' do
        create(:book, participation:)

        open_page

        expect(response.body).to include('続きを読む')
        expect(response.body).to include('閉じる')
      end

      # 空白のまま置くと、書き忘れなのか書くところが無いのか分からない
      it 'おすすめポイントが未記入ならその旨が出る' do
        book_by('佐藤 花子', recommendation: nil)

        open_page

        expect(response.body).to include('おすすめポイントが未記入です')
      end

      # 買う先を見るのに、まず本文を開かせる理由が無い。
      # 開いて初めて出てくると、閉じたカードを眺めている側からはボタンが無いように見える
      it 'ストアへのリンクは開く前から出ている' do
        book = book_by('佐藤 花子', url: 'https://example.com/books/1')

        open_page

        expect(closed_card(book).to_html).to include('https://example.com/books/1')
        expect(closed_card(book).text).to include('ストアで見る')
      end

      # 下段に置くと、折られていない本のカードでは開くボタンが消えるぶん左へ寄る。
      # 本文より上なら、下段に何が出ていようと同じ場所にある
      it 'ストアへのリンクが本文より上に出る' do
        book = book_by('佐藤 花子', url: 'https://example.com/books/1', recommendation: 'おすすめの本文')

        open_page

        html = card_for(book).to_html
        expect(html.index('ストアで見る')).to be < html.index('おすすめの本文')
      end

      it 'URL が無ければストアへのリンクは出ない' do
        book_by('佐藤 花子', url: nil)

        open_page

        expect(response.body).not_to include('ストアで見る')
      end

      # 登録者が書いた URL をそのままリンクにすると、読み比べに来た人の
      # ブラウザで javascript: が走る
      it 'http と https 以外はリンクにしない' do
        book_by('佐藤 花子', url: "javascript:alert('x')")

        open_page

        expect(response.body).not_to include('javascript:alert')
      end
    end

    describe '希望リストの編集' do
      def open_page_while_wishing
        open_page(at: wishing_at)
      end

      it '希望提出期間中は希望リストが常時出る' do
        book_by('佐藤 花子')

        open_page_while_wishing

        expect(response.body).to include('あなたの希望リスト')
      end

      it '希望提出期間中は各カードから希望に追加できる' do
        book = book_by('佐藤 花子')

        open_page_while_wishing

        expect(wish_form(book)).to be_present
        expect(card_for(book).text).to include('希望に追加')
      end

      it '希望に入れた本には順位が出る' do
        book = book_by('佐藤 花子')
        create(:wish, participation:, book:, position: 1)

        open_page_while_wishing

        expect(card_for(book).text).to include('希望 1位')
        expect(card_for(book).text).to include('希望から外す')
      end

      # 一覧を読んでいる間ずっと、いま何冊・何位まで選んだかが見えている
      it '希望リストに順位と本が並ぶ' do
        book = book_by('佐藤 花子', title: '選んだ本')
        create(:wish, participation:, book:, position: 1)

        open_page_while_wishing

        expect(wish_list.text).to include('選んだ本')
      end

      it '1冊も選んでいなければその旨が出る' do
        book_by('佐藤 花子')

        open_page_while_wishing

        expect(wish_list.text).to include('まだ1冊も選んでいません')
      end

      it '取得枠と希望冊数が並ぶ' do
        register_own(2)
        wish_for_others(3)

        open_page_while_wishing

        expect(wish_list.text).to include('取得枠2冊に対して希望3冊')
      end

      # 取得枠は登録した冊数で決まる。何と同じ数なのかを書かないと、
      # 増やせる数なのか決まった数なのかが読み取れない
      it '取得枠が何で決まるかを添える' do
        register_own(2)

        open_page_while_wishing

        expect(response.parsed_body.at_css('aside').text).to include('2冊（登録した本と同じ）')
      end

      # 希望リストは長いほうが有利。上位が取られると下位へ降りていく
      it '取得枠の2倍に満たなければ増やすことを促す' do
        register_own(2)
        wish_for_others(3)

        open_page_while_wishing

        expect(wish_list.text).to include('もう少し増やすことを推奨します')
        expect(wish_list.text).to include('4冊以上')
      end

      it '取得枠の2倍以上あれば促さない' do
        register_own(2)
        wish_for_others(4)

        open_page_while_wishing

        expect(wish_list.text).not_to include('もう少し増やすことを推奨します')
      end

      # 登録期間はもう終わっている。増やすことを促しても、その人には届かない
      it '1冊も登録していなければ受け取れないことを伝える' do
        wish_for_others(3)

        open_page_while_wishing

        expect(wish_list.text).to include('受け取れる本はありません')
        expect(wish_list.text).not_to include('もう少し増やすことを推奨します')
      end

      # 狭い画面ではシートを畳んだままでも一覧を読み進められる。
      # 案内を開いた側だけに置くと、既定の状態では冊数がどこにも出ない
      it '畳んだシートにも冊数が出る' do
        register_own(2)
        wish_for_others(3)

        open_page_while_wishing

        expect(wish_summary.text).to include('枠2冊／希望3冊')
        expect(wish_summary.text).to include('あと1冊推奨')
      end

      it '畳んだシートでも足りていれば推奨を出さない' do
        register_own(2)
        wish_for_others(4)

        open_page_while_wishing

        expect(wish_summary.text).to include('枠2冊／希望4冊')
        expect(wish_summary.text).not_to include('推奨')
      end

      # 何人がその本を希望しているかは誰にも見えない。
      # 案内が数えるのは自分の希望だけで、他の人の希望では動かない
      it '他の人の希望は冊数に混ざらない' do
        register_own(1)
        wanted = book_by('佐藤 花子')
        create(:wish, participation:, book: wanted, position: 1)
        3.times { create(:wish, participation: create(:participation, exchange:), book: wanted, position: 1) }

        open_page_while_wishing

        expect(wish_list.text).to include('取得枠1冊に対して希望1冊')
      end

      # 畳んでいる間に出る1行。開いた側の案内と同じ文字が並ぶので、
      # 出し分けを確かめるにはここだけを見る
      def wish_summary
        wish_list.at_css('#wish_summary')
      end

      def handle(row)
        row.at_css('[data-wish-reorder-target~="handle"]')
      end

      # 順位が変わったことを読み上げる区画。差し替えの外にあるので、
      # 希望リストの中身ではなくページ全体から引く
      def reorder_status
        response.parsed_body.at_css('#wish_reorder_status')
      end

      # 並べ替えの送り先。行を包まないので、行の中の form とは別のものになる
      def reorder_form
        wish_list.at_css('#wish_reorder')
      end

      # 行から希望を外すボタン。行の中にある form はこれだけ
      def removal_form(row)
        row.at_css('form')
      end

      # 畳んでいる間に出る側。ここに並ぶのは順位付きのチップだけ
      def collapsed_sheet
        wish_summary.parent
      end

      # 並べ替えは順序だけをまとめて送る。
      # ここで確かめるのは送る材料が画面に揃っていることまで。
      # つまんで動かす操作そのものはブラウザでしか確かめられない
      it '希望リストの並びをそのまま送れる' do
        first = wish_for('1冊目')
        second = wish_for('2冊目')

        open_page_while_wishing

        expect(wish_list.css('input[name="book_ids[]"]').pluck('value'))
          .to eq([first.id.to_s, second.id.to_s])
      end

      it '送り先は希望リストの更新' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(reorder_form['action']).to eq(exchange_wish_list_path(exchange))
      end

      # 行にボタンが4つ並ぶと、広い画面の340pxのリストでは題に92pxしか残らず、
      # 6文字で切れる。並べ替えはハンドル1つに寄せる
      it '行の操作は並べ替えと外すの2つだけ' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(rows.first.css('button').size).to eq(2)
        expect(wish_list.css('button[aria-label="順位を上げる"]')).to be_empty
        expect(wish_list.css('button[aria-label="順位を下げる"]')).to be_empty
      end

      # つまむハンドルは順位そのもの。⠿ と × が隣り合っていた間は、44pxの的が4pxの
      # 隙間で並び、並べ替えようとして希望から外す取り違えが起こりえた。
      # 順位へ移すと、押すものが行の両端に離れる
      it 'つまむハンドルが順位そのものである' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(handle(rows.first).text).to include('1')
      end

      it '専用のハンドルを別に置かない' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(rows.first.text).not_to include('⠿')
      end

      # 順位は数字なので、⠿ のように形だけでつまめることを言えない。字はもとから
      # 朱なので合図を色で足す道も無い。止まっている間から輪郭を持たせて、
      # 押せるものであることを見て分かるようにする
      it 'つまめることが押す前に分かる' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(handle(rows.first)['class']).to include('border-line')
      end

      # ドラッグはつまめる人にしか使えない。↑↓ を落とした以上、キーボードと
      # 読み上げに渡る道はハンドル自身が持つほかない
      it 'ハンドルがキーボードから届く' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(handle(rows.first).name).to eq('button')
        expect(handle(rows.first)['aria-hidden']).to be_nil
      end

      # 十数行が同じ名前で並ぶと、読み上げたときにどの行のボタンなのかが分からない。
      # 名前は見えている数字と続けて組む。aria-label で上書きすると、動かすたびに
      # 振り直す先が数字と名前の2か所になり、片方だけ古くなる
      it 'ハンドルの名前がどの本の何位かを言う' do
        wish_for('動かしたい本')

        open_page_while_wishing

        expect(handle(rows.first).text.squish).to include('1').and include('動かしたい本')
        expect(handle(rows.first)['aria-label']).to be_nil
      end

      # ↑↓ のボタンを落としたので、押して動かす道はキーへ移る
      it 'ハンドルがキー入力を受ける' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(handle(rows.first)['data-action']).to include('keydown->wish-reorder#key')
      end

      # つまむのもキーで動かすのも、画面には何も書かれていない操作にあたる。
      # 説明を1か所に置き、行のハンドルからそこへ繋ぐ
      it 'ハンドルから操作の説明へ繋がる' do
        wish_for('1冊目')

        open_page_while_wishing

        help = wish_list.at_css("##{handle(rows.first)['aria-describedby']}")
        expect(help.text).to include('順位').and include('↑↓').and include('Home')
        expect(help.text).not_to include('⠿')
      end

      # 並べ替えは JavaScript でしか動かない。動かない環境に押せるハンドルを残すと、
      # 押しても何も起きないボタンになる。説明も同じで、できない操作を書くことになる。
      # カードからの追加・削除はそのまま通る
      it '並べ替えのハンドルと説明は JavaScript が動くまで押せない' do
        wish_for('1冊目')
        wish_for('2冊目')

        open_page_while_wishing

        expect(wish_list.css('li [disabled][data-wish-reorder-target~="handle"]').size).to eq(2)
        expect(handle(rows.first)['class']).to include('disabled:border-transparent')
        expect(wish_list.at_css('#wish_reorder_help[hidden]')).to be_present
      end

      # 順位はボタンである前に読むもの。⠿ のように伏せると、JavaScript が動かない間は
      # 何位なのかがどこにも出なくなる
      it '順位は JavaScript が動かなくても読める' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(wish_list.css('li [hidden][data-wish-reorder-target~="handle"]')).to be_empty
        expect(rows.first.text).to include('1')
      end

      # 動かした結果は、画面では順位が振り直されて見えるが、読み上げには何も届かない
      it '順位が変わったことを読み上げる区画がある' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(reorder_status['aria-live']).to eq('polite')
      end

      # 中身と一緒に入れ替わると、読み上げる先が保存のたびに作り直される
      it '読み上げる区画は差し替えの外にある' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(reorder_status).to be_present
        expect(wish_list.at_css('#wish_reorder_status')).to be_nil
      end

      # つまむ前と後で行の輪郭の線種しか変わらないと、ハンドルを捉えられたのかが
      # 読み取れない。指には cursor が無いので、つかめた合図は色で持つ。
      # 順位の字はもとから朱なので、変えるのは輪郭のほうにあたる
      it 'つかんだことがハンドルで分かる' do
        wish_for('1冊目')

        open_page_while_wishing

        held = handle(rows.first)['class'].split.grep(/dragging/)
        expect(held).to include(a_string_matching(/:border-accent/)).and include(a_string_matching(/cursor-grabbing/))
      end

      # ハンドルだけが変わっても、動かしているのがどの行かは分からない。
      # 行そのものの面と輪郭で示す
      it 'つまんでいる行が面と輪郭で分かる' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(dragging_styles(rows.first))
          .to include(a_string_matching(/:bg-/)).and include(a_string_matching(/:border-dashed/))
      end

      # 描き分けは data-dragging が付いている間だけのもので、落とせば
      # controller が外す。サーバーはつまんでいる状態を描かない
      it '落とせば元の見た目へ戻る' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(rows.first['data-dragging']).to be_nil
        expect(dragging_styles(rows.first)).to be_present
      end

      # つまんだ行はポインタに追従するので、隣の行と重なる。重ね順を上げないと
      # 持ち上げた行が隣の下へ潜る
      it 'つまんでいる行が隣の行の上に出る' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(dragging_styles(rows.first))
          .to include(a_string_matching(/:relative/)).and include(a_string_matching(/:z-/))
      end

      # 階層は文字と色と輪郭で作る
      it 'つまんでも影は落とさない' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(dragging_styles(rows.first)).not_to include(a_string_matching(/shadow/))
      end

      # つまむのは狭い画面のほうが多い。広い画面にだけ合図を出すと、
      # ドラッグを主に使う側に何も残らない
      it 'つかんだ合図は画面の幅で変わらない' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(dragging_styles(rows.first)).not_to include(a_string_matching(/\b(sm|md|lg|xl):/))
      end

      # 絞り込みは URL に残る
      it '絞り込みを保ったまま並べ替えられる' do
        wish_for('1冊目')

        open_mine(at: wishing_at)

        expect(reorder_form.at_css('input[name="filter"]')['value']).to eq('mine')
      end

      # 外すボタンをカードの側にしか置かないと、リストを見て「これを消したい」と
      # 思った人が、同じ本のカードを一覧から探し直すことになる
      it '各行から希望を外せる' do
        first = wish_for('1冊目')
        second = wish_for('2冊目')

        open_page_while_wishing

        expect(rows.map { removal_form(it)['action'] })
          .to eq([exchange_book_wish_path(exchange, first), exchange_book_wish_path(exchange, second)])
      end

      it '外すボタンの送り方は希望の削除' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(removal_form(rows.first).at_css('input[name="_method"]')['value']).to eq('delete')
        expect(removal_form(rows.first).at_css('button')['aria-label']).to eq('希望から外す')
      end

      # form は入れ子にできない。並べ替えの form が行を包んだままだと、
      # 行の中の外すボタンはブラウザに落とされ、押しても何も起きない
      it '外すボタンの form が並べ替えの form に入れ子にならない' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(wish_list.css('form form')).to be_empty
      end

      # 送る並びは行の並びそのもの。form の外へ出しても、送られる順は
      # DOM の並び順なので、hidden は行の中に置いたまま form 属性で結ぶ
      it '並べ替えの hidden は form の外から結ぶ' do
        wish_for('1冊目')
        wish_for('2冊目')

        open_page_while_wishing

        expect(wish_list.css('input[name="book_ids[]"]').pluck('form')).to eq(['wish_reorder', 'wish_reorder'])
      end

      # 並べ替えと違い、外すほうにはカードの側と同じ JavaScript の無い経路がある
      it '外すボタンは JavaScript が動くまで伏せない' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(rows.first.at_css('[hidden] form')).to be_nil
      end

      it '絞り込みを保ったまま外せる' do
        wish_for('1冊目')

        open_mine(at: wishing_at)

        expect(removal_form(rows.first).at_css('input[name="filter"]')['value']).to eq('mine')
      end

      # 畳んだ側のチップは横に流れる要約。44px のボタンを並べると、
      # 一覧を読む間ずっと見えているはずの並びが1画面に2冊ぶんしか入らない
      it '畳んだシートのチップには外すボタンを置かない' do
        wish_for('1冊目')

        open_page_while_wishing

        expect(collapsed_sheet.css('form')).to be_empty
      end

      it '1冊も選んでいなければ並べ替えるものが無い' do
        book_by('佐藤 花子')

        open_page_while_wishing

        expect(wish_list.at_css('form')).to be_nil
      end

      # 自分の本は受け取れない。押しても通らないボタンを
      # 出しておいて断るのではなく、選べないことをその場で示す
      it '自分の本は選べないことが分かる' do
        book = create(:book, participation:)

        open_page_while_wishing

        expect(card_for(book).text).to include('自分の本は希望に選べません')
        expect(wish_form(book)).to be_nil
      end

      # 何人がその本を希望しているかは誰にも見せない。
      # 中身まで揃えた2冊を並べ、希望された側とされていない側で
      # カードが1文字も変わらないことを見る
      it '何人がその本を希望しているかは出ない' do
        registrant = create(:participation, exchange:, user: create(:user, display_name: '佐藤 花子'))
        same = { title: '同じ題の本', summary: '同じあらすじ', recommendation: '同じおすすめ' }
        wanted = create(:book, participation: registrant, **same)
        ignored = create(:book, participation: registrant, **same)
        3.times { create(:wish, participation: create(:participation, exchange:), book: wanted) }

        open_page_while_wishing

        expect(card_for(wanted).text).to eq(card_for(ignored).text)
      end

      # 登録期間はまだ選ぶ対象が揃っていない。出しても押せば断られる
      it '登録期間中は出ない' do
        book = book_by('佐藤 花子')

        open_page

        expect(response.body).not_to include('あなたの希望リスト')
        expect(wish_form(book)).to be_nil
      end
    end

    describe '登録・編集・削除の導線' do
      it '1冊も登録されていなくても登録ボタンが出る' do
        open_page

        expect(response.body).to include('まだ本は登録されていません')
        expect(response.body).to include(new_exchange_book_path(exchange))
      end

      it '自分の本には編集と削除が出る' do
        mine = create(:book, participation:)

        open_page

        expect(response.body).to include(edit_exchange_book_path(exchange, mine))
        expect(response.body).to include('登録を取り消します')
      end

      # 消えるのは本だけではない。取得枠が1つ減り、その本への他の人の希望も消える
      it '削除の確認で取得枠が減ることを伝える' do
        create_list(:book, 2, participation:)

        open_page

        expect(response.body).to include('取得枠が2冊から1冊に減り')
      end

      # 自分の本は取得枠の数でもある。導線の有無だけで見分けさせると、
      # 登録期間を過ぎたとたんにどれが自分の本か分からなくなる
      it '自分の本には印が付く' do
        mine = create(:book, participation:, title: '灯台守の一年')

        open_page(at: wishing_at)

        expect(card_for(mine).text).to include('自分の本')
      end

      it '他人の本には印が付かない' do
        theirs = book_by('佐藤 花子', title: '十三番目の便り')

        open_page

        expect(card_for(theirs).text).not_to include('自分の本')
      end

      it '他人の本には編集も削除も出ない' do
        theirs = book_by('佐藤 花子')

        open_page

        expect(response.body).not_to include(edit_exchange_book_path(exchange, theirs))
      end

      # 押しても通らない導線を残さない
      it '登録期間外は自分の本にも編集と削除が出ない' do
        mine = create(:book, participation:)

        open_page(at: wishing_at)

        expect(response.body).not_to include(edit_exchange_book_path(exchange, mine))
        expect(response.body).not_to include('登録を取り消します')
      end
    end

    # 希望の受付が終わってから結果が出るまでの間。
    # 締め切られた事実だけを消して並びも消すと、自分が何を出したのかを
    # 確かめる先がどこにも無くなる
    describe 'マッチング実行待ち' do
      def open_awaiting
        open_page(at: awaiting_at)
      end

      it '提出した希望リストが並びを保ったまま残る' do
        wish_for('1番目に欲しい本')
        wish_for('2番目に欲しい本')

        open_awaiting

        expect(rows.map { it.text.squish })
          .to eq(['1 1番目に欲しい本 佐藤 花子', '2 2番目に欲しい本 佐藤 花子'])
      end

      # 締め切られたことは見出しで言う。並びが残っているだけだと、
      # まだ動かせるものなのか、もう出したものなのかが読み取れない
      it '見出しが提出したものであることを言う' do
        wish_for('欲しい本')

        open_awaiting

        expect(response.body).to include('提出した希望リスト')
        expect(response.body).not_to include('あなたの希望リスト')
      end

      it '並べ替えるハンドルが外れる' do
        wish_for_others(2)

        open_awaiting

        expect(wish_list.at_css('form')).to be_nil
        expect(wish_list.at_css('[data-wish-reorder-target~="handle"]')).to be_nil
      end

      # つまむハンドルが順位そのものなので、押せない順位と押せる順位が同じ数字で並ぶ。
      # 締め切られた側は button ごと外し、輪郭も持たせない
      it '順位が押せる見た目にならない' do
        wish_for_others(2)

        open_awaiting

        expect(rows.first.at_css('button')).to be_nil
        expect(rows.first.text).to include('1')
      end

      # 動かせない並びで読み上げる区画だけを残しても、伝えるものが無い
      it '順位を読み上げる区画も外れる' do
        wish_for_others(2)

        open_awaiting

        expect(response.parsed_body.at_css('#wish_reorder_status')).to be_nil
      end

      it '外すボタンも外れる' do
        wish_for_others(2)

        open_awaiting

        expect(wish_list.css('button[aria-label="希望から外す"]')).to be_empty
      end

      # 動かせない並びにつまんだときの描き分けが残っていると、
      # 押せば動くように読める
      it 'つまんだときの描き分けも残らない' do
        wish_for_others(2)

        open_awaiting

        expect(dragging_styles(rows.first)).to be_empty
      end

      it 'カードから希望を出し入れするボタンが外れる' do
        wanted = wish_for('選んだ本')
        ignored = book_by('佐藤 花子', title: '選ばなかった本')

        open_awaiting

        expect(wish_form(wanted)).to be_nil
        expect(wish_form(ignored)).to be_nil
      end

      # 増やす道はもう残っていない。促す代わりに、いま何が起きるのかだけを書く
      it '取得枠と繰り上がりの説明を添える' do
        register_own(2)
        wish_for_others(3)

        open_awaiting

        expect(response.body).to include('繰り上がります')
        expect(response.body).not_to include('もう少し増やすことを推奨します')
      end

      # 締切はもう過ぎている。次に来る日時として出すと、まだ間に合うように読める
      it '希望提出の締切は出さない' do
        wish_for('欲しい本')

        open_awaiting

        expect(response.body).not_to include('希望提出の締切')
      end

      it '1冊も出していなければその旨が出る' do
        book_by('佐藤 花子')

        open_awaiting

        expect(wish_list.text).to include('希望を1冊も出しませんでした')
      end

      # 十数枚並ぶ中から自分が何を出したのかを、リストと見比べずに読めるようにする
      it 'カードに自分が何位で出したかが出る' do
        book = wish_for('選んだ本')

        open_awaiting

        expect(card_for(book).text).to include('希望に入れた 1位')
      end

      # 順位が出ている本が同じ画面に並んでいるので、出ていないことがそのまま
      # 入れなかったことにあたる。入れなかった側にも書くと、十数枚のうち
      # 大半が否定の一文を持つことになる
      it '希望に入れなかった本には何も書かない' do
        book = book_by('佐藤 花子', title: '選ばなかった本')

        open_awaiting

        expect(card_for(book).text).not_to include('希望には入れていません')
        expect(card_for(book).text).not_to include('希望に入れた')
      end

      # 自分の本は希望に入れようがない。入れなかった本と同じ扱いで足りる
      it '自分の本にも希望の状態を書かない' do
        mine = create(:book, participation:, title: '自分の本')

        open_awaiting

        expect(card_for(mine).text).not_to include('希望に入れた')
      end

      # 何人がその本を希望しているかは誰にも見せない。
      # 中身まで揃えた2冊を並べ、他の人に希望された側とされていない側で
      # カードが1文字も変わらないことを見る
      it '他人の希望も、その本を何人が希望したかも出ない' do
        registrant = create(:participation, exchange:, user: create(:user, display_name: '佐藤 花子'))
        same = { title: '同じ題の本', summary: '同じあらすじ', recommendation: '同じおすすめ' }
        wanted = create(:book, participation: registrant, **same)
        ignored = create(:book, participation: registrant, **same)
        3.times { create(:wish, participation: create(:participation, exchange:), book: wanted) }

        open_awaiting

        expect(card_for(wanted).text).to eq(card_for(ignored).text)
      end

      # 希望リストが同じ幅を取り続けるので、カードの並べ方も変わらない。
      # 締切をまたいだ瞬間に大きさが変わると、読み比べていた並びを覚え直すことになる
      it '希望提出期間と同じ並べ方でカードが並ぶ' do
        book_by('佐藤 花子')

        open_awaiting

        expect(card_stack['class'].split).not_to include(a_string_matching(/grid-cols/))
      end
    end

    describe '結果公開後' do
      # 成立した割当。受け取る人は本の登録者とは別の参加になる
      def matched(book, recipient_name)
        recipient = create(:participation, exchange:, user: create(:user, display_name: recipient_name))
        create(:assignment, book:, participation: recipient)
      end

      # 返却は誰にも渡せなかった本が登録者へ戻ること。割当は登録者の参加に付く
      def returned(book)
        create(:assignment, book:, participation: book.participation, round: nil, returned: true)
      end

      it '成立した本に誰から誰へ渡ったかが出る' do
        book = book_by('佐藤 花子', title: '十三番目の便り')
        matched(book, '鈴木 一郎')
        publish!

        open_page

        expect(card_for(book).text).to include('佐藤 花子 さん → 鈴木 一郎 さん')
      end

      # 十数枚並ぶ中から自分の名前を探し直さずに済むようにする（結果画面と同じ扱い）
      it '自分が出した本は自分の側が「あなた」になる' do
        book = create(:book, participation:, title: '灯台守の一年')
        matched(book, '鈴木 一郎')
        publish!

        open_page

        expect(card_for(book).text).to include('あなた → 鈴木 一郎 さん')
      end

      it '自分が受け取った本は受け取る側が「あなた」になる' do
        book = book_by('佐藤 花子', title: '波打ち際の観測所')
        create(:assignment, book:, participation:)
        publish!

        open_page

        expect(card_for(book).text).to include('佐藤 花子 さん → あなた')
      end

      # 渡った先は松葉で示す。返却と同じ色で並べると、成立を数え直すことになる
      it '自分が受け取った本には印が付く' do
        book = book_by('佐藤 花子', title: '波打ち際の観測所')
        create(:assignment, book:, participation:)
        publish!

        open_page

        expect(card_for(book).text).to include('あなたへ')
      end

      it '成立していても他人が受け取った本には印が付かない' do
        book = book_by('佐藤 花子', title: '十三番目の便り')
        matched(book, '鈴木 一郎')
        publish!

        open_page

        expect(card_for(book).text).not_to include('あなたへ')
      end

      it '返却された自分の本には戻ってきたことが出る' do
        book = create(:book, participation:, title: '砂の図書館')
        returned(book)
        publish!

        open_page

        expect(card_for(book).text).to include('あなたに返却されました')
      end

      it '返却された他人の本には登録者へ戻ったことが出る' do
        book = book_by('佐藤 花子', title: '金曜日の献立')
        returned(book)
        publish!

        open_page

        expect(card_for(book).text).to include('佐藤 花子 さんに返却')
      end

      # 選ばれなかったことを本の評価として読ませない。
      # 戻った理由は結果画面が引き受ける
      it '返却の理由は書かない' do
        book = book_by('佐藤 花子', title: '金曜日の献立')
        returned(book)
        publish!

        open_page

        expect(card_for(book).text).not_to include('希望した人がいませんでした')
      end

      # 希望を出す期間は終わっている。押しても通らないボタンを残さない
      it '希望に追加するボタンが消える' do
        book = book_by('佐藤 花子', title: '十三番目の便り')
        matched(book, '鈴木 一郎')
        publish!

        open_page

        expect(response.body).not_to include('希望に追加')
        expect(response.body).not_to include(exchange_book_wish_path(exchange, book))
      end

      # 公開前は割当が無い。フェーズを見ずに割当の有無だけで出すと、
      # 主催者が実行した瞬間に、まだ公開の合図を受けていない画面へ結果が出る
      it '結果公開前には渡った先が出ない' do
        book = book_by('佐藤 花子', title: '十三番目の便り')
        matched(book, '鈴木 一郎')

        open_page

        expect(card_for(book).text).not_to include('鈴木 一郎 さん')
      end
    end

    # 登録した本人と、成立後の受取人だけに見える。
    # この画面はどちらの経路でもない
    it 'ギフトコードが含まれない' do
      mine = create(:book, participation:, gift_code: 'MYOWNGIFTCODE')
      theirs = book_by('佐藤 花子', gift_code: 'OTHERGIFTCODE')
      create(:assignment, book: theirs, participation:)
      create(:assignment, book: mine, participation:, round: nil, returned: true)
      publish!

      open_page

      expect(response.body).not_to include('MYOWNGIFTCODE')
      expect(response.body).not_to include('OTHERGIFTCODE')
    end
  end

  describe '#new' do
    it '開ける' do
      get '/exchanges/new'

      expect(response).to have_http_status(:ok)
    end

    it 'ログインしていなければログイン画面へ送る' do
      log_out

      get '/exchanges/new'

      expect(response).to redirect_to(login_path)
    end

    describe '日時の入力欄' do
      before { get '/exchanges/new' }

      it '3つある' do
        expect(response.body.scan('type="datetime-local"').size).to eq(3)
      end

      # 希望提出期間の開始はカラムが無く registration_ends_at から導出する。
      # 入力欄を置くと、送られた値で上書きできるように見えてしまう
      it '希望提出期間の開始を送らせない' do
        expect(response.body).not_to include('wish_starts_at')
      end

      it '登録の締切が希望提出期間の開始も兼ねることが分かる' do
        expect(response.body).to include('登録の締切が、そのまま希望提出期間の始まりになります')
      end
    end
  end

  describe '#create' do
    it '交換会ができる' do
      expect { post '/exchanges', params: { exchange: attributes } }.to change(Exchange, :count).by(1)

      expect(Exchange.last).to have_attributes(
        name: '夏の交換会',
        description: 'Kindle のみ。1000円前後を目安に。',
        webhook_url: 'https://discord.com/api/webhooks/1/abc'
      )
    end

    it '作成した人が主催者になる' do
      post '/exchanges', params: { exchange: attributes }

      expect(Exchange.last.owner).to eq(user)
    end

    # 主催者を送れると、他人の名前で交換会を作れてしまう
    it '主催者を送りつけても無視する' do
      other = create(:user)

      post '/exchanges', params: { exchange: attributes.merge(owner_id: other.id) }

      expect(Exchange.last.owner).to eq(user)
    end

    # 期待値はオフセット付きの直値で置く。Time.zone.parse で組み立てると
    # 読み出しと期待値が同じ Time.zone に依存し、設定を UTC に変えても
    # 両辺が揃って動いて通ってしまう。JST であることを固定できない
    it '日時を JST として受け取る' do
      post '/exchanges', params: { exchange: attributes }

      expect(Exchange.last.registration_starts_at.rfc3339).to eq('2026-08-10T10:00:00+09:00')
    end

    # 参加していない人には交換会が見えない。主催者だけが参加者でないまま残ると、
    # どの画面も「主催者が来たらどうするか」を個別に答えることになる
    it '主催者の参加も同時にできる' do
      expect { post '/exchanges', params: { exchange: attributes } }
        .to change(Participation, :count).by(1)

      expect(Exchange.last.participant?(user)).to be(true)
    end

    # 作った本人がそのまま参加者として入れる。編集画面は設定を直す画面で、
    # 作り終えた人を最初に置く場所ではない
    it '交換会トップへ送る' do
      post '/exchanges', params: { exchange: attributes }

      expect(response).to redirect_to(exchange_path(Exchange.last))
    end

    it '作成できたことを知らせる' do
      post '/exchanges', params: { exchange: attributes }

      follow_redirect!

      expect(response.body).to include('交換会を作成しました')
    end

    it 'ログインしていなければ作成できない' do
      log_out

      expect { post '/exchanges', params: { exchange: attributes } }.not_to change(Exchange, :count)

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(login_path)
    end

    describe '入力の不備' do
      it '登録の締切が開始より前だと作られない' do
        invalid = attributes.merge(registration_ends_at: '2026-08-01T10:00')

        expect { post '/exchanges', params: { exchange: invalid } }.not_to change(Exchange, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('登録期間の終了日時は開始日時より後にしてください')
      end

      # 希望提出期間の開始は登録の締切そのもの。同時刻だと期間の幅が無くなる
      it '希望提出の締切が登録の締切と同時刻だと作られない' do
        invalid = attributes.merge(wish_ends_at: attributes[:registration_ends_at])

        expect { post '/exchanges', params: { exchange: invalid } }.not_to change(Exchange, :count)

        expect(response.body).to include('希望提出期間の終了日時は開始日時より後にしてください')
      end

      it '交換会名が空だと作られない' do
        expect { post '/exchanges', params: { exchange: attributes.merge(name: '') } }
          .not_to change(Exchange, :count)

        expect(response.body).to include('交換会名を入力してください')
      end

      # 差し戻したフォームに入力が残らないと、全部打ち直しになる
      it '差し戻したフォームに入力が残る' do
        post '/exchanges', params: { exchange: attributes.merge(registration_ends_at: '2026-08-01T10:00') }

        expect(response.body).to include('夏の交換会')
      end

      # 締切を過ぎた日程では主催者の参加を作れない。
      # 判定はサーバーが受けた時刻で行い、送られてきた値は見ない
      it '登録の締切が過ぎていると作られない' do
        travel_to '2026-08-25T00:00:00+09:00' do
          expect { post '/exchanges', params: { exchange: attributes } }
            .not_to change(Exchange, :count)
        end

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('登録期間の終了日時は現在より後にしてください')
      end
    end
  end

  # 状態カラムを持たないので、作った日時がそのままフェーズになる。
  # 送った日時を JST として読み違えると、作った直後から1つずれる
  describe '作成直後のフェーズ' do
    # 現在時刻はオフセット付きの直値で置く。travel_to は文字列を Time.zone.parse
    # に通すので、オフセットを書いておけばゾーン設定に依存しない。
    # 境界そのものは spec/models/exchange_spec.rb が持つ
    # 主催者がその場で参加できる2つのフェーズでしか作れない。
    # 残りの3つで作れないことは #create の「入力の不備」が押さえている
    [
      ['登録期間の開始前なら準備中', '2026-08-09T23:59:00+09:00', :preparing],
      ['登録期間の開始ちょうどなら登録期間', '2026-08-10T10:00:00+09:00', :registration],
    ].each do |description, now, phase|
      it description do
        travel_to now do
          post '/exchanges', params: { exchange: attributes }

          expect(Exchange.last.phase(at: Time.current)).to eq(phase)
        end
      end
    end

    it '交換会トップに現在のフェーズを出す' do
      travel_to '2026-08-15T10:00:00+09:00' do
        post '/exchanges', params: { exchange: attributes }

        follow_redirect!

        expect(response.body).to include('登録期間')
      end
    end
  end

  describe '#edit' do
    let!(:exchange) { create(:exchange, owner: user, name: '春の交換会') }

    it '主催者は開ける' do
      get edit_exchange_path(exchange)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('春の交換会')
    end

    # この画面へ来る入口は主催者管理だけなので、そこまでを祖先として並べる
    it 'パンくずから交換会トップと主催者管理へ戻れる' do
      get edit_exchange_path(exchange)

      expect(breadcrumb).to eq('交換会一覧' => exchanges_path,
                               '春の交換会' => exchange_path(exchange),
                               '主催者管理' => exchange_management_path(exchange))
    end

    # UTC で描かれると9時間ずれた値が既定で入り、開くたびに日程が巻き戻る
    it '日時の入力欄に JST の値が入る' do
      dated = create(:exchange, owner: user,
                                registration_starts_at: '2026-08-10T10:00:00+09:00'.in_time_zone,
                                registration_ends_at: '2026-08-24T10:00:00+09:00'.in_time_zone,
                                wish_ends_at: '2026-09-07T10:00:00+09:00'.in_time_zone)

      get edit_exchange_path(dated)

      expect(response.body).to include('value="2026-08-10T10:00:00"')
    end

    # 403 だと、招待されていない交換会の実在が漏れる
    it '主催者以外には見つからない' do
      log_in_as(create(:user))

      get edit_exchange_path(exchange)

      expect(response).to have_http_status(:not_found)
    end

    it 'ログインしていなければログイン画面へ送る' do
      log_out

      get edit_exchange_path(exchange)

      expect(response).to redirect_to(login_path)
    end
  end

  describe '#update' do
    let!(:exchange) { create(:exchange, owner: user, name: '春の交換会') }

    it '主催者は変更できる' do
      patch exchange_path(exchange), params: { exchange: { name: '初夏の交換会' } }

      expect(exchange.reload.name).to eq('初夏の交換会')
    end

    # 主催者は各期間の日時を後から変更できる
    it '日程を変更できる' do
      patch exchange_path(exchange), params: { exchange: { wish_ends_at: '2026-10-01T10:00' } }

      expect(exchange.reload.wish_ends_at.rfc3339).to eq('2026-10-01T10:00:00+09:00')
    end

    it '登録期間の開始が終了より後になる変更は拒否される' do
      patch exchange_path(exchange),
            params: { exchange: { registration_starts_at: '2026-09-01T10:00',
                                  registration_ends_at: '2026-08-01T10:00' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('登録期間の終了日時は開始日時より後にしてください')
    end

    # 希望提出期間の開始は registration_ends_at から導出されるので、
    # 登録の締切を希望提出の締切より後ろへ動かすと、この期間が潰れる
    it '希望提出期間の開始が終了より後になる変更は拒否される' do
      patch exchange_path(exchange),
            params: { exchange: { registration_ends_at: '2026-09-01T10:00',
                                  wish_ends_at: '2026-08-25T10:00' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('希望提出期間の終了日時は開始日時より後にしてください')
    end

    # 開始と終了が同時刻。各期間は終了時刻を含まないので、
    # 幅が0の期間はどのフェーズにも属さない時間を生む
    it '開始と終了が同時刻になる変更は拒否される' do
      patch exchange_path(exchange),
            params: { exchange: { registration_starts_at: '2026-08-01T10:00',
                                  registration_ends_at: '2026-08-01T10:00' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(exchange.reload.registration_ends_at.rfc3339).not_to eq('2026-08-01T10:00:00+09:00')
    end

    # フェーズは状態カラムを持たず日時から導出する。締切を延ばした瞬間に
    # 希望提出期間へ戻り、参加者の書き込みがその場で開き直す
    it '締切を延ばすとフェーズがその場で切り替わる' do
      exchange.update!(registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
                       registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
                       wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)
      at = '2026-08-20T00:00:00+09:00'.in_time_zone
      expect(exchange.phase(at:)).to eq(:awaiting_matching)

      travel_to(at) do
        patch exchange_path(exchange), params: { exchange: { wish_ends_at: '2026-08-25T00:00' } }
      end

      expect(exchange.reload.phase(at:)).to eq(:wish)
      expect(exchange.writable?(:wish, at:)).to be(true)
    end

    # 結果公開後も日程は変更できる。マッチングを実行したかどうかで
    # フェーズが決まるので、日時を動かしても結果公開のままになる（4.）
    context 'マッチングの実行後' do
      let!(:at) { '2026-08-20T00:00:00+09:00'.in_time_zone }

      before { exchange.update!(matched_at: at) }

      it '日程を変更できる' do
        travel_to(at) do
          patch exchange_path(exchange), params: { exchange: { wish_ends_at: '2026-10-01T10:00' } }
        end

        expect(exchange.reload.wish_ends_at.rfc3339).to eq('2026-10-01T10:00:00+09:00')
      end

      # 日時を過去へ戻しても結果公開のまま。ここが崩れると、
      # 受け取った人に見えていたギフトコードが見えなくなる
      it '日程を過去へ戻しても結果公開のままになる' do
        travel_to(at) do
          patch exchange_path(exchange),
                params: { exchange: { registration_starts_at: '2026-09-01T00:00',
                                      registration_ends_at: '2026-09-08T00:00',
                                      wish_ends_at: '2026-09-15T00:00' } }
        end

        expect(exchange.reload.phase(at:)).to eq(:published)
      end

      # 結果公開はどの操作も許さない。日時を書き込みができる期間へ動かしても、
      # phase が :published を返すので開き直さない
      it '日程を動かしても書き込みは開き直さない' do
        travel_to(at) do
          patch exchange_path(exchange),
                params: { exchange: { registration_starts_at: '2026-08-19T00:00',
                                      registration_ends_at: '2026-08-26T00:00',
                                      wish_ends_at: '2026-09-02T00:00' } }
        end

        exchange.reload
        expect(Exchange::WRITABLE_PHASES.keys).to all(satisfy { |op| !exchange.writable?(op, at:) })
      end
    end

    it '変更できたことを知らせる' do
      patch exchange_path(exchange), params: { exchange: { name: '初夏の交換会' } }

      follow_redirect!

      expect(response.body).to include('交換会を更新しました')
    end

    it '不備があれば差し戻す' do
      patch exchange_path(exchange), params: { exchange: { name: '' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(exchange.reload.name).to eq('春の交換会')
    end

    it '主催者以外は更新できない' do
      log_in_as(create(:user))

      patch exchange_path(exchange), params: { exchange: { name: '乗っ取り' } }

      expect(response).to have_http_status(:not_found)
      expect(exchange.reload.name).to eq('春の交換会')
    end

    it 'ログインしていなければ更新できない' do
      log_out

      patch exchange_path(exchange), params: { exchange: { name: '乗っ取り' } }

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(login_path)
      expect(exchange.reload.name).to eq('春の交換会')
    end

    # 書き込みは戻り先に覚えない。ログインしたとたんに
    # 乗っ取りの patch がやり直されては困る
    it '未ログインの更新はログイン後にやり直されない' do
      log_out

      patch exchange_path(exchange), params: { exchange: { name: '乗っ取り' } }
      log_in_as(user)

      expect(response).to redirect_to(root_path)
      expect(exchange.reload.name).to eq('春の交換会')
    end

    # 差し替えられると、実行前に結果を引き直せてしまう
    it '乱数シードは変えられない' do
      seed = exchange.random_seed

      patch exchange_path(exchange), params: { exchange: { random_seed: 1 } }

      expect(exchange.reload.random_seed).to eq(seed)
    end
  end
end
