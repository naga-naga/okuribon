# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExchangesController do
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

  # フェーズも次の締切も日時から導出されるため、現在時刻を固定してから撒く
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
    # 並ばないと、作った本人が自分の交換会へ入る口を持てない
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

    # 交換会へ入る口は、参加したあとはこの一覧しかない
    it 'カードから交換会トップへ入れる' do
      exchange = registration_exchange

      travel_to(now) { get exchanges_path }

      expect(response.body).to include(exchange_path(exchange))
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

    # 終わった交換会に締切を出すと、まだ何かできるように読める
    it '結果公開には次の締切を出さない' do
      registration_exchange(matched_at: '2026-08-03T00:00:00+09:00'.in_time_zone)

      travel_to(now) { get exchanges_path }

      expect(response.body).to include('結果公開')
      expect(response.body).not_to include('締切')
      expect(response.body).not_to include('2026年8月8日 00:00')
    end

    # 待っているのは主催者の操作で、日時では動かない
    it 'マッチング実行待ちには次の締切を出さない' do
      participating(registration_starts_at: '2026-07-01T00:00:00+09:00'.in_time_zone,
                    registration_ends_at: '2026-07-10T00:00:00+09:00'.in_time_zone,
                    wish_ends_at: '2026-07-20T00:00:00+09:00'.in_time_zone)

      travel_to(now) { get exchanges_path }

      expect(response.body).to include('マッチング実行待ち')
      expect(response.body).not_to include('締切')
    end

    # 何も無い画面を白紙で返すと、壊れているのか参加していないのか区別がつかない
    it '1つも参加していなければその旨を出す' do
      travel_to(now) { get exchanges_path }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('まだ参加している交換会はありません')
    end

    # 並び順を決めないと、開くたびにカードの位置が入れ替わる
    it '日程の新しいものから並ぶ' do
      registration_exchange(name: '夏の交換会')
      participating(name: '秋の交換会',
                    registration_starts_at: '2026-09-01T00:00:00+09:00'.in_time_zone,
                    registration_ends_at: '2026-09-08T00:00:00+09:00'.in_time_zone,
                    wish_ends_at: '2026-09-15T00:00:00+09:00'.in_time_zone)

      travel_to(now) { get exchanges_path }

      expect(response.body.index('秋の交換会')).to be < response.body.index('夏の交換会')
    end

    it 'ログインしていなければログイン画面へ送る' do
      log_out

      get exchanges_path

      expect(response).to redirect_to(login_path)
    end

    # ログイン済みの着地はここ。招待URLを除けば、交換会へ入る口はこの一覧しかない
    it 'root から開ける' do
      registration_exchange(name: '夏の交換会')

      travel_to(now) { get root_path }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('夏の交換会')
    end
  end

  # フェーズも残り時間も日時から導出されるため、現在時刻を固定してから撒く
  describe '#show' do
    let!(:now) { '2026-08-04T00:00:00+09:00' }

    let!(:exchange) do
      create(:exchange, name: '夏の交換会', description: 'Kindle のみ。1000円前後を目安に。',
                        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
                        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
                        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)
    end

    let!(:participation) { create(:participation, user:, exchange:) }

    def open_top(at: now)
      travel_to(at) { get exchange_path(exchange) }
    end

    it '参加者は開ける' do
      open_top

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('夏の交換会')
    end

    # 対応ストアや価格帯の目安が書かれている。本を選ぶ前に読む必要がある
    it '概要が出る' do
      open_top

      expect(response.body).to include('Kindle のみ。1000円前後を目安に。')
    end

    # 403 だと、招待されていない交換会の実在が URL を試すだけで確かめられる
    it '参加していなければ見つからない' do
      log_in_as(create(:user))

      open_top

      expect(response).to have_http_status(:not_found)
    end

    # 主催者は必ず参加者を兼ねるので、自分の交換会のトップを開ける。
    # 主催者管理画面への導線はこの画面が持つ
    it '主催者も開ける' do
      owned = create(:exchange, owner: user, name: '主催した交換会')

      travel_to(now) { get exchange_path(owned) }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('主催した交換会')
    end

    # 主催者管理画面へ辿り着く経路はここだけ。交換会一覧は主催と参加を
    # 区別せずに並べるので（6.6）、ここに無いと入口を持てない
    it '主催者には主催者管理画面への導線が出る' do
      owned = create(:exchange, owner: user)

      travel_to(now) { get exchange_path(owned) }

      expect(response.body).to include(exchange_management_path(owned))
    end

    # 押しても 404 になるリンクを見せない。主催者以外にはその画面の
    # 存在自体を知らせない（docs/spec.md 8.）
    it '主催者以外には導線が出ない' do
      open_top

      expect(response.body).not_to include(exchange_management_path(exchange))
    end

    it 'ログインしていなければログイン画面へ送る' do
      log_out

      open_top

      expect(response).to redirect_to(login_path)
    end

    it '現在のフェーズが出る' do
      open_top

      expect(response.body).to include('登録期間')
    end

    it '次の締切が出る' do
      open_top

      expect(response.body).to include('登録の締切')
      expect(response.body).to include('2026年8月8日 00:00')
    end

    # 久しぶりに開く人が最初に知りたいのは、日付そのものより残りの長さ
    it '次の締切までの残りが出る' do
      open_top

      expect(response.body).to include('あと4日')
    end

    # 締切当日に「あと0日」と出ても、今日中なのかどうか読み取れない
    it '締切まで残り数時間なら時間で出る' do
      open_top(at: '2026-08-07T19:00:00+09:00')

      expect(response.body).to include('あと5時間')
    end

    # 待っているのは主催者の操作で、日時では動かない
    it 'マッチング実行待ちには締切も残りも出さない' do
      open_top(at: '2026-08-20T00:00:00+09:00')

      expect(response.body).to include('マッチング実行待ち')
      expect(response.body).not_to include('締切')
      expect(response.body).not_to include('あと')
    end

    # 終わった交換会に残りを出すと、まだ何かできるように読める
    it '結果公開には締切も残りも出さない' do
      exchange.update!(matched_at: '2026-08-03T00:00:00+09:00'.in_time_zone)

      open_top

      expect(response.body).to include('結果公開')
      expect(response.body).not_to include('締切')
      expect(response.body).not_to include('あと')
    end

    describe '交換会の規模' do
      before do
        create_list(:participation, 2, exchange:)
        create_list(:book, 2, participation:)
        create(:book, participation: create(:participation, exchange:))
      end

      it '参加者数が出る' do
        open_top

        expect(response.body).to include('参加者')
        expect(response.body).to include('5人')
      end

      it '本の総数が出る' do
        open_top

        expect(response.body).to include('3冊')
      end

      # 登録した冊数がそのまま受け取れる冊数になる。
      # 全体の冊数と並べないと、自分が何冊登録したのか確かめる先が無い
      it '自分の取得枠が出る' do
        open_top

        expect(response.body).to include('取得枠')
        expect(response.body).to include('2冊')
      end
    end

    # 導線が無いと、URL を直打ちしないと開けない画面になる
    it '本の一覧への導線がある' do
      open_top

      expect(response.body).to include(exchange_books_path(exchange))
    end

    # 見えるのは登録した本人と、成立後の受取人だけ。トップはどちらの経路でもない
    it 'ギフトコードが含まれない' do
      create(:book, participation:, gift_code: 'MYOWNGIFTCODE')
      create(:book, participation: create(:participation, exchange:), gift_code: 'OTHERGIFTCODE')

      open_top

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
    # 作れるのは主催者がその場で参加できる2つのフェーズだけ。
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

    # 主催者は各期間の日時を後から変更できる（docs/spec.md 4. フェーズ）
    it '日程を変更できる' do
      patch exchange_path(exchange), params: { exchange: { wish_ends_at: '2026-10-01T10:00' } }

      expect(exchange.reload.wish_ends_at.rfc3339).to eq('2026-10-01T10:00:00+09:00')
    end

    # 登録期間の開始と終了が入れ替わる変更。DB の例外ではなく、
    # フォームに戻せる日本語のエラーとして返す
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

    # 結果公開後も日程は変更できる（docs/spec.md 6.9）。マッチングを実行したかどうかで
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
      # 受け取った人に見えていたギフトコードが見えなくなる（docs/spec.md 8.）
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
