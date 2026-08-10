# frozen_string_literal: true

require 'rails_helper'

# ギフトコードの可視性を、画面と経路をまたいで確かめる（docs/spec.md 8. 情報の可視性ルール）。
# 画面1枚ずつの検証は各コントローラの spec が持っている。ここが受け持つのは
# 「どこにも漏れていない」の側で、読み取りで開ける画面を1つの表に集めて全部掃く。
# 画面が増えたら screens に1行足す。足し忘れれば、その画面は誰にも掃かれない。
#
# コードの持ち主は Book なので、リクエストをまたぐ検証でも describe はこのモデルに置く
RSpec.describe Book do
  describe 'ギフトコードの可視性' do
    # 交換会は1つ。登録者・受取人・主催者・割当を持たない参加者が揃っていて、
    # 成立した本と返却された本の両方がある。1つの状態を4人の目から見る
    let!(:organizer) { create(:user, display_name: 'みずき') }
    let!(:viewer) { create(:user, display_name: 'あなた') }

    let!(:exchange) do
      create(:exchange,
             owner: organizer,
             registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
             registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
             wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)
    end

    # 主催者の参加は factory が作る。主催者は必ず参加者を兼ねる（docs/spec.md 6.9）
    let!(:participants) do
      { organizer: exchange.participations.find_by!(user: organizer),
        viewer: create(:participation, exchange:, user: viewer),
        other: create(:participation, exchange:, user: create(:user, display_name: 'ゆうと')),
        # 1冊も登録せず、割当も持たない参加者。取得枠が無いまま結果を開く
        bystander: create(:participation, exchange:, user: create(:user, display_name: 'かなえ')) }
    end

    # 4冊で、あなたから見た本の立場を出し尽くす。
    # 受け取った本・渡した本・返ってきた本・関わりのない本
    let!(:books) do
      { received: create(:book, participation: participants[:other],
                                title: '波打ち際の観測所', gift_code: codes[:received]),
        given: create(:book, participation: participants[:viewer],
                             title: '十三番目の便り', gift_code: codes[:given]),
        returned: create(:book, participation: participants[:viewer],
                                title: '砂の図書館', gift_code: codes[:returned]),
        others: create(:book, participation: participants[:organizer],
                              title: '夜行の記録', gift_code: codes[:others]) }
    end

    # 交換会に出てくるギフトコードの全部。固定値なので let! にしない。
    # 名前を付けておくと、漏れたときにどの立場の本かがそのまま失敗の文に出る
    def codes
      { received: 'RECEIVED-CODE-0001', given: 'GIVEN-CODE-0002',
        returned: 'RETURNED-CODE-0003', others: 'OTHERS-CODE-0004' }
    end

    def codes_in(body)
      codes.select { |_name, code| body.include?(code) }.keys
    end

    # 掃く目。参加者・主催者・受取人・割当を持たない参加者をひととおり通す
    def viewers
      participants.values.map(&:user)
    end

    # 掃く先。読み取りで開ける画面を全部並べる。開けない人には 404 や 409 が返るが、
    # そのぶんも掃く対象に残す。フェーズや権限で閉じている画面が、条件を1つ変えた
    # だけで開いたときに、掃かれていない画面にならないため。
    #
    # 結果画面と自分の本の編集フォームはここに入れない。平文が出てよい2面で、
    # 出るべきものが出ていることも確かめる必要があるので、下で個別に見る
    def screens
      { '交換会一覧' => root_path,
        '交換会トップ' => exchange_path(exchange),
        '本の一覧' => exchange_books_path(exchange),
        '自分の本だけに絞った一覧' => exchange_books_path(exchange, filter: 'mine'),
        '本の登録フォーム' => new_exchange_book_path(exchange),
        '交換会の編集' => edit_exchange_path(exchange),
        '主催者管理画面' => exchange_management_path(exchange),
        'マッチングの確認' => new_exchange_management_matching_path(exchange),
        '招待URL着地画面' => invitation_path(exchange.invite_token) }
    end

    # 1人の目で全画面を掃き、漏れたコードを画面の名前とともに返す
    def leaks_for(user, at:)
      log_in_as(user)

      screens.filter_map do |name, path|
        travel_to(at) { get path }

        found = codes_in(response.body)
        "#{name}（#{found.join('・')}）" if found.any?
      end
    end

    def expect_no_leak(at:)
      viewers.each do |user|
        leaks = leaks_for(user, at:)

        expect(leaks).to be_empty, "#{user.display_name} に漏れている → #{leaks.join(' / ')}"
      end
    end

    # 割当を作る。公開はしない。結果公開前に受取人へ見えないことを確かめるため、
    # 割当と公開を分けて呼べるようにしてある
    def assign!
      create(:assignment, book: books[:received], participation: participants[:viewer], round: 1)
      create(:assignment, book: books[:given], participation: participants[:other], round: 1)
      create(:assignment, book: books[:others], participation: participants[:other], round: 2)
      # 返却は誰にも渡せなかった本が登録者へ戻ること。受取人は登録者本人になる
      create(:assignment, book: books[:returned], participation: participants[:viewer],
                          round: nil, returned: true)
    end

    def publish!
      assign!
      exchange.update!(matched_at: '2026-08-20T21:04:00+09:00'.in_time_zone)
    end

    # 見に来る時刻。公開は publish! の時刻に起きている
    def published_at
      '2026-08-21T09:00:00+09:00'.in_time_zone
    end

    def registration_at
      '2026-08-04T00:00:00+09:00'.in_time_zone
    end

    # 割当はできているのに公開されていない状態を見る時刻
    def awaiting_matching_at
      '2026-08-16T09:00:00+09:00'.in_time_zone
    end

    def open_result(user, at:)
      log_in_as(user)
      travel_to(at) { get exchange_result_path(exchange) }
    end

    context '結果公開のとき' do
      it 'どの画面にもギフトコードが出ない' do
        publish!

        expect_no_leak(at: published_at)
      end

      # 掃いた結果が空になるのは、そもそも本が描かれていないからではない
      it '掃く先の一覧に4冊すべてが並んでいる' do
        publish!
        log_in_as(viewer)

        travel_to(published_at) { get exchange_books_path(exchange) }

        expect(response.body).to include(*books.values.map(&:title))
      end

      # 結果画面は平文が出る面。出てよいのは受け取った本と、
      # 誰にも渡らずに戻ってきた自分の本だけ。渡した本のコードは並べない
      it '結果画面に出るのは受け取った本と返ってきた自分の本だけ' do
        publish!

        open_result(viewer, at: published_at)

        expect(response).to have_http_status(:ok)
        expect(codes_in(response.body)).to contain_exactly(:received, :returned)
      end

      # 返却された本のコードは登録者にしか見えない。
      # ゆうとは2冊受け取っているので、そのぶんだけが出る
      it '受取人の結果画面に、他人へ返却された本のコードは出ない' do
        publish!

        open_result(participants[:other].user, at: published_at)

        expect(response).to have_http_status(:ok)
        expect(codes_in(response.body)).to contain_exactly(:given, :others)
      end

      # 主催者に特権はない（docs/spec.md 8.）。自分が登録した本は渡ってしまっていて、
      # 受け取った本は無いので、結果画面に出るコードは1つも無い
      it '主催者の結果画面にギフトコードは出ない' do
        publish!

        open_result(organizer, at: published_at)

        expect(response).to have_http_status(:ok)
        expect(codes_in(response.body)).to be_empty
      end

      it '割当を持たない参加者の結果画面にギフトコードは出ない' do
        publish!

        open_result(participants[:bystander].user, at: published_at)

        expect(response).to have_http_status(:ok)
        expect(codes_in(response.body)).to be_empty
      end
    end

    context '登録期間のとき' do
      it 'どの画面にもギフトコードが出ない' do
        expect_no_leak(at: registration_at)
      end

      # 自分の本のコードはフォームに出る。伏せ字だが平文が本文に入るので、
      # 出るのが自分の1冊だけであることをここで固定する
      it '自分の本の編集フォームには自分のコードだけが出る' do
        log_in_as(viewer)

        travel_to(registration_at) { get edit_exchange_book_path(exchange, books[:given]) }

        expect(response).to have_http_status(:ok)
        expect(codes_in(response.body)).to contain_exactly(:given)
      end

      # 他人の本は引けないことにしてある（BooksController#own_book）。
      # 主催者から引いても同じで、フォームからの取得経路は本人だけに閉じている
      it '他人の本の編集フォームは主催者にも開けない' do
        log_in_as(organizer)

        travel_to(registration_at) { get edit_exchange_book_path(exchange, books[:given]) }

        expect(response).to have_http_status(:not_found)
        expect(codes_in(response.body)).to be_empty
      end
    end

    # 割当と公開はマッチングの実行が同じトランザクションで書く（Matching::Execution）ため、
    # 通常は現れない状態。公開の判定が抜けたときに、受取人へ先に見えることを防ぐ
    context '割当ができているのに結果が公開されていないとき' do
      it '受取人でも結果画面からギフトコードを取れない' do
        assign!

        open_result(viewer, at: awaiting_matching_at)

        expect(response).to have_http_status(:not_found)
        expect(codes_in(response.body)).to be_empty
      end

      it 'どの画面にもギフトコードが出ない' do
        assign!

        expect_no_leak(at: awaiting_matching_at)
      end
    end

    # 平文を読める口を Book#gift_code_for 1つに保つ（CLAUDE.md「ギフトコードの可視性」）。
    # 権限判定はそのメソッドに集めてあるので、素のリーダーを別の場所から読み始めた時点で
    # 判定を迂回できる。上の掃き出しは「いまの画面」しか見ないため、経路そのものも見る
    context '取得経路' do
      it '平文を読む経路は Book#gift_code_for だけである' do
        reads = sources.flat_map do |path|
          path.read.lines.each_with_index.filter_map do |line, index|
            "#{path.relative_path_from(Rails.root)}:#{index + 1}" if bare_read?(line)
          end
        end

        expect(reads).to be_empty
      end

      # 違反が無いあいだ上の example は通り続けるので、見落とす正規表現になっていても
      # 気付けない。素のリーダーを見つけられること自体を確かめる
      it '素のリーダーを見つけられる' do
        expect(bare_read?('  <%= book.gift_code %>')).to be(true)
        expect(bare_read?('  book.send(:gift_code)')).to be(true)
        expect(bare_read?('  book.read_attribute(:gift_code)')).to be(true)
        expect(bare_read?('  book[:gift_code]')).to be(true)
      end

      it '権限判定を通る読み取りと書き込みは見逃す' do
        expect(bare_read?('  code: book.gift_code_for(current_user, at: requested_at)')).to be(false)
        expect(bare_read?('  book.gift_code_visible_to?(current_user, at: requested_at)')).to be(false)
        expect(bare_read?("  book.gift_code = format('OKURIBON-%<index>04d-DEV', index:)")).to be(false)
        expect(bare_read?("  <%= t('result.gift_code.copy') %>")).to be(false)
      end
    end

    # 走査の対象。素のリーダーを読めるのは、コードの持ち主である Book だけ
    def sources
      Rails.root.glob('{app,lib}/**/*.{rb,erb}') - [Rails.root.join('app/models/book.rb')]
    end

    # 権限判定を通らない読み取り。属性の別名（添字・read_attribute・send）も数える。
    # 翻訳キーとパーシャル名に gift_code が出てくるので、引用符の中身は先に落とす
    def bare_read?(line)
      code = line.gsub(%r{(['"])[a-z0-9_./]+\1}, 'STRING')

      code.match?(/\.gift_code\b(?!\s*=[^=])/) ||
        code.match?(/read_attribute\(\s*:gift_code/) ||
        code.match?(/\[\s*:gift_code\s*\]/) ||
        code.match?(/send\(\s*:gift_code/)
    end
  end
end
