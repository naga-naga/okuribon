# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ResultsController do
  let!(:organizer) { create(:user, display_name: 'みずき') }
  let!(:exchange) do
    create(:exchange,
           owner: organizer,
           registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
           registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
           wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)
  end

  # マッチングを実行した時刻。画面に出るので、見に来る時刻とは分けておく
  let!(:published_at) { '2026-08-20T21:04:00+09:00'.in_time_zone }

  let!(:viewer) { create(:user, display_name: 'あなた') }
  let!(:participation) { create(:participation, exchange:, user: viewer) }

  def join(display_name)
    create(:participation, exchange:, user: create(:user, display_name:))
  end

  # 割当はマッチングが作るが、ここで確かめたいのは見え方なので直に組む。
  # 実行そのものは Matching::Execution の spec が受け持つ
  def receive_book(from:, to: participation, **attributes)
    book = create(:book, participation: from, **attributes)
    create(:assignment, book:, participation: to, returned: false)
    book
  end

  # 返却は誰にも渡せなかった本が登録者へ戻ること。割当の受取人は登録者本人になる
  def return_book(of: participation, **attributes)
    book = create(:book, participation: of, **attributes)
    create(:assignment, book:, participation: of, round: nil, returned: true)
    book
  end

  def publish
    exchange.update!(matched_at: published_at)
  end

  # 見に来る時刻。公開そのものは published_at に起きている
  def open_result(target = exchange, at: '2026-08-21T09:00:00+09:00'.in_time_zone)
    travel_to(at) { get exchange_result_path(target) }
  end

  describe '#show' do
    context '結果が公開されているとき' do
      before { log_in_as(viewer) }

      # 取得枠は登録した冊数と同数（docs/spec.md 3.）。
      # 受け取った本がその冊数だけ並ぶ
      it '受け取った本が取得枠の冊数だけ並ぶ' do
        receive_book(from: join('ゆうと'), title: '波打ち際の観測所')
        receive_book(from: join('はるか'), title: '十三番目の便り')
        publish

        open_result

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('波打ち際の観測所', '十三番目の便り')
      end

      # 誰から贈られたかが分かるようにする。お礼を伝えるため（docs/spec.md 6.5）
      it '誰が登録した本かが分かる' do
        receive_book(from: join('ゆうと'), title: '波打ち際の観測所',
                     recommendation: '後半で数字の意味が反転します')
        publish

        open_result

        expect(response.body).to include('ゆうと さんから', '後半で数字の意味が反転します')
      end

      # 一度見えたら取り消せない。既定は伏せ字にする（docs/spec.md 10.）
      it 'ギフトコードは伏せ字で入る' do
        receive_book(from: join('ゆうと'), gift_code: 'MINE-CODE-0001')
        publish

        open_result

        expect(response.body).to include('MINE-CODE-0001')
        expect(response.body).to include('type="password"')
      end

      it '明示的な操作で開ける' do
        receive_book(from: join('ゆうと'))
        publish

        open_result

        expect(response.body).to include('表示', 'data-action="reveal#toggle"')
      end

      # 開かずに済むなら、そのほうが肩越しに覗かれる機会が少ない
      it '伏せ字のままコピーできる' do
        receive_book(from: join('ゆうと'))
        publish

        open_result

        expect(response.body).to include('コピー', 'data-action="clipboard#copy"')
      end

      # ギフトコードが見えるのは登録した本人と、受け取った人だけ（docs/spec.md 8.）
      it '他人が受け取った本のギフトコードは含まれない' do
        others = join('ゆうと')
        receive_book(from: join('はるか'), to: others, gift_code: 'OTHERS-CODE-9999')
        publish

        open_result

        expect(response.body).not_to include('OTHERS-CODE-9999')
      end

      # 主催者に特権はない（docs/spec.md 8.）。参加者を兼ねるので自分の結果は見られるが、
      # 見えるものは他の参加者と同じ
      it '主催者が開いても、自分のぶんしか見えない' do
        # 主催者は必ず参加者を兼ねる（docs/spec.md 6.9）。その参加は factory が作る
        organizer_participation = exchange.participations.find_by!(user: organizer)
        receive_book(from: join('はるか'), to: organizer_participation, gift_code: 'OWN-CODE-1111')
        receive_book(from: join('ゆうと'), to: participation, gift_code: 'OTHERS-CODE-9999')
        publish
        log_in_as(organizer)

        open_result

        expect(response.body).to include('OWN-CODE-1111')
        expect(response.body).not_to include('OTHERS-CODE-9999')
      end

      # 渡った先の人が使うコードなので、この画面には取り出す用がない。
      # 本人には見える値だが（docs/spec.md 8.）、並べる理由が無い
      it '自分が渡した本のギフトコードは含まれない' do
        mine = create(:book, participation:, gift_code: 'GIVEN-CODE-2222')
        create(:assignment, book: mine, participation: join('ゆうと'), returned: false)
        publish

        open_result

        expect(response.body).not_to include('GIVEN-CODE-2222')
      end

      # 数週間ずっと締切を見せてきた画面なので、いつ公開されたのかを添える
      it '公開された日時が出る' do
        receive_book(from: join('ゆうと'))
        publish

        open_result

        expect(response.body).to include('2026年8月20日 21:04 公開')
      end
    end

    # 誰が誰の本を受け取ったかは参加者全員に見える（docs/spec.md 8.）。
    # 自分の受け取りだけでは、交換会全体で何が起きたのかが分からない
    context '全体の成立結果' do
      before { log_in_as(viewer) }

      it '自分が関わっていない成立も、登録した人と受け取った人の名前と共に出る' do
        riku = join('りく')
        sayaka = join('さやか')
        create(:assignment, book: create(:book, participation: riku, title: '石を数える人'),
                            participation: sayaka, returned: false)
        publish

        open_result

        expect(response.body).to include('石を数える人', 'りく', 'さやか')
      end

      # 返却された本を一覧から落とすと、冊数が合わずに数え直すことになる
      it '他人の本の返却も、その旨と共に出る' do
        kanae = join('かなえ')
        create(:assignment, book: create(:book, participation: kanae, title: '金曜日の献立'),
                            participation: kanae, round: nil, returned: true)
        publish

        open_result

        expect(response.body).to include('金曜日の献立', '返却')
      end

      # 一覧系に絶対に含めない（CLAUDE.md「ギフトコードの可視性」）
      it '他人どうしで成立した本のギフトコードは含まれない' do
        riku = join('りく')
        sayaka = join('さやか')
        create(:assignment,
               book: create(:book, participation: riku, gift_code: 'OVERALL-CODE-4444'),
               participation: sayaka, returned: false)
        publish

        open_result

        expect(response.body).not_to include('OVERALL-CODE-4444')
      end

      it '他人の返却された本のギフトコードも含まれない' do
        kanae = join('かなえ')
        create(:assignment,
               book: create(:book, participation: kanae, gift_code: 'RETURNED-OTHERS-5555'),
               participation: kanae, round: nil, returned: true)
        publish

        open_result

        expect(response.body).not_to include('RETURNED-OTHERS-5555')
      end

      # 1冊も登録されないまま実行された交換会（docs/spec.md 9.）。
      # 見出しと列名だけの空の表は、読む側に何も伝えない
      it '本が1冊も登録されていなければ、この節ごと出ない' do
        join('りく')
        publish

        open_result

        expect(response.body).not_to include('全体の結果')
      end

      # 導線も出ないフェーズなので、ここへ来るのは URL を直に打った場合だけ。
      # それでも全体の結果が漏れては、公開前に勝ち負けが分かってしまう
      it '結果公開前には、全体の結果そのものが出ない' do
        riku = join('りく')
        create(:assignment, book: create(:book, participation: riku, title: '石を数える人'),
                            participation: join('さやか'), returned: false)

        open_result(at: '2026-08-16T00:00:00+09:00'.in_time_zone)

        expect(response.body).not_to include('全体の結果', '石を数える人')
      end
    end

    # 自分が出した本がどこへ行ったかは、受け取ったものと同じくらい気になる
    context '自分が出した本の行き先' do
      before { log_in_as(viewer) }

      it '渡った先の名前が出る' do
        mine = create(:book, participation:, title: '灯台守の一年')
        create(:assignment, book: mine, participation: join('ゆうと'), returned: false)
        publish

        open_result

        expect(response.body).to include('あなたが出した本の行き先', '灯台守の一年', 'ゆうと さんへ')
      end

      # 何番目の希望で渡ったかは出さない。受け取った人の希望リストの中身にあたるうえ
      # （docs/spec.md 8.）、順位が低いと渡った事実より順位のほうが目に残る
      it '受け取った人の希望の順位は出さない' do
        mine = create(:book, participation:, title: '灯台守の一年')
        yuto = join('ゆうと')
        create(:wish, participation: yuto, book: mine, position: 3)
        create(:assignment, book: mine, participation: yuto, round: 2, returned: false)
        publish

        open_result

        expect(response.body).not_to include('第3希望', '第1希望')
      end

      it '1冊も登録していなければ、この節ごと出ない' do
        receive_book(from: join('ゆうと'))
        publish

        open_result

        expect(response.body).not_to include('あなたが出した本の行き先')
      end
    end

    # 抽選順は結果公開後に見せてよい（docs/spec.md 8.）。
    # 順序は巡ごとに逆になるので、並びを見せても有利不利の話にはならない
    context 'ドラフトの抽選順' do
      before { log_in_as(viewer) }

      def draft(*participations)
        participations.each_with_index { |part, index| part.update!(draft_position: index + 1) }
      end

      # 参加者の名前は全体の一覧にも出る。畳んだ抽選順の中だけを見る
      def draft_list
        response.body[/#{Regexp.escape(I18n.t('result.draft_order.summary'))}.*/m]
      end

      it '抽選された順に参加者が並ぶ' do
        riku = join('りく')
        sayaka = join('さやか')
        receive_book(from: riku)
        # 参加した順とは逆に抽選されている。並びが id 順に戻っていないことを見る
        draft(sayaka, participation, riku)
        publish

        open_result

        expect(draft_list.index('さやか')).to be < draft_list.index('りく')
      end

      # 抽選順の入っていない交換会は、この機能より前に実行されたもの。
      # 見出しだけを出しても読む側には何も伝わらない
      it '抽選順が記録されていなければ出さない' do
        receive_book(from: join('りく'))
        publish

        open_result

        expect(response.body).to include('全体の結果')
        expect(response.body).not_to include('抽選順')
      end
    end

    context '自分の本が返却されたとき' do
      before { log_in_as(viewer) }

      it '戻ってきた本の題名を挙げて伝える' do
        receive_book(from: join('ゆうと'))
        return_book(title: '砂の図書館')
        publish

        open_result

        expect(response.body).to include('「砂の図書館」は戻ってきました')
      end

      # 事実だけを出すと、選ばれなかったことを本の評価として読んでしまう。
      # 「誰も希望しなかった」で終えず、それが何を意味しないかまで書く
      it '選ばれなかったのが本の評価ではないと書き添える' do
        return_book(title: '砂の図書館')
        publish

        open_result

        expect(response.body).to include('相性の問題で、本の善し悪しではありません')
      end

      # 返却を「失った」と読ませない。何が手元に残るのかを並べる
      it '残るもの（コード・取得枠・次の交換会）を書き添える' do
        return_book(title: '砂の図書館')
        publish

        open_result

        expect(response.body).to include('ギフトコードは未使用のまま、あなたの手元に残っています',
                                         '返却があっても、受け取る冊数（取得枠）は減りません',
                                         '次の交換会に、そのまま出せます')
      end

      # 本の詳細画面を持たないため（docs/spec.md 6.3）、誰にも渡らなかった
      # コードの取り出し口はこの画面以外に無い
      it '返却された本のギフトコードを、受け取った本と同じ形で開ける' do
        return_book(title: '砂の図書館', gift_code: 'RETURNED-CODE-3333')
        publish

        open_result

        expect(response.body).to include('RETURNED-CODE-3333', 'type="password"',
                                         '見えるのはあなただけです')
      end

      it '2冊以上戻ってきたときは、冊数と題名が並ぶ' do
        return_book(title: '砂の図書館')
        return_book(title: '金曜日の献立')
        publish

        open_result

        expect(response.body).to include('出した本のうち2冊が戻ってきました',
                                         '砂の図書館', '金曜日の献立')
      end
    end

    # 取得枠は登録した冊数と同数（docs/spec.md 3.）。
    # 白紙で返すと、壊れているのか受け取れなかったのか区別がつかない
    context '受け取った本が1冊も無いとき' do
      before { log_in_as(viewer) }

      it '1冊も登録していない人には、枠が0だったことを伝える' do
        publish

        open_result

        expect(response.body).to include('今回、受け取る本はありません',
                                         '登録期間に1冊も登録しなかったため0冊でした')
      end

      # 登録はしたのに回ってこないことがある。枠が0だったのと同じ文にすると、
      # 登録し忘れたのかと本人が疑う
      it '登録はしたが回ってこなかった人には、別の事情を伝える' do
        return_book(title: '砂の図書館')
        publish

        open_result

        expect(response.body).to include('今回は本が回ってきませんでした',
                                         '渡せる本が残らないことがあります')
        expect(response.body).not_to include('1冊も登録しなかったため')
      end
    end

    # 結果公開前に開ける画面ではない。導線もこのフェーズには出ないので、
    # ここへ来るのは URL を直に打った場合だけ
    context '結果が公開されていないとき' do
      before { log_in_as(viewer) }

      # 素の 404 だと、URL を間違えたのか時期が早いのかを参加者が区別できない
      it 'まだ公開されていないことと、いま何を待っているのかを添えて 404 を返す' do
        open_result(at: '2026-08-16T00:00:00+09:00'.in_time_zone)

        expect(response).to have_http_status(:not_found)
        expect(response.body).to include('結果はまだ公開されていません',
                                         'いまはマッチング実行待ちです')
      end

      it '受け取る本の中身は出さない' do
        receive_book(from: join('ゆうと'), title: '波打ち際の観測所', gift_code: 'MINE-CODE-0001')

        open_result(at: '2026-08-16T00:00:00+09:00'.in_time_zone)

        expect(response.body).not_to include('波打ち際の観測所')
        expect(response.body).not_to include('MINE-CODE-0001')
      end
    end

    it '参加していない人には 404 を返す' do
      publish
      log_in_as(create(:user))

      open_result

      expect(response).to have_http_status(:not_found)
    end

    it '未ログインならログイン画面へ送る' do
      publish

      open_result

      expect(response).to redirect_to(login_path)
    end

    # 実在する交換会だけがログイン画面へ、存在しない id が 404 へ分かれると、
    # ログインしないまま id を試すだけで実在を確かめられてしまう（docs/spec.md 8.）
    it '未ログインなら、実在しない交換会でも応答が変わらない' do
      publish

      open_result
      existing = [response.status, response.headers['Location']]

      open_result(Exchange.maximum(:id) + 1)

      expect([response.status, response.headers['Location']]).to eq(existing)
    end
  end
end
