# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvitationsController do
  let!(:owner) { create(:user, display_name: '主催 太郎') }
  let!(:exchange) do
    create(:exchange, owner:,
                      name: '夏の交換会',
                      description: 'Kindle のみ。1000円前後を目安に。',
                      registration_starts_at: '2026-08-10T10:00:00+09:00'.in_time_zone,
                      registration_ends_at: '2026-08-24T10:00:00+09:00'.in_time_zone,
                      wish_ends_at: '2026-09-07T10:00:00+09:00'.in_time_zone)
  end

  describe '#show' do
    # 交換会の日時は絶対値なので、開く時刻を固定しないと登録期間が過ぎ、
    # 参加できる前提で書いた例が時期によって落ちる。
    # travel_to は入れ子にできないため、自前の時刻を持つ例はこの入口を通さない
    let!(:during_registration) { '2026-08-20T10:00:00+09:00' }

    def open_invitation
      travel_to(during_registration) { get invitation_path(exchange.invite_token) }
    end

    # 存在しない交換会と、招待されていない交換会を見分けられないようにする
    it '無効なトークンでは見つからない' do
      get invitation_path('deadbeefdeadbeef')

      expect(response).to have_http_status(:not_found)
    end

    # 招待された人はまだログインしていない。何の集まりかを見てから決められるようにする
    describe '交換会の概要' do
      before { open_invitation }

      it '未ログインでも開ける' do
        expect(response).to have_http_status(:ok)
      end

      it '交換会名と概要が出る' do
        expect(response.body).to include('夏の交換会')
        expect(response.body).to include('Kindle のみ。1000円前後を目安に。')
      end

      it '主催者名が出る' do
        expect(response.body).to include('主催 太郎')
      end

      # 誰から誘われたのかが交換会名より先に目に入るようにする。本文に混ぜると、
      # 知らない集まりの名前だけが大きく出て、心当たりに辿り着けない
      it '差出人が「○○ さんからの招待」で出る' do
        expect(response.body).to include('主催 太郎 さんからの招待')
      end

      # 主催者も参加者に数える。招待された人が見るのは交換会の規模で、
      # 主催者だけを別枠に置く理由が無い
      it '参加者数が出る' do
        create_list(:participation, 2, exchange:)

        open_invitation

        expect(response.body).to include('3人')
      end

      # UTC で描かれると9時間ずれた日程が出て、参加を決める判断そのものが狂う
      it '各期間の日程が JST で出る' do
        expect(response.body).to include('2026年8月10日 10:00')
        expect(response.body).to include('2026年8月24日 10:00')
        expect(response.body).to include('2026年9月7日 10:00')
      end
    end

    # 参加は必ずこのボタンを押してから。押した事実がサーバーに残らないと、
    # 招待URLを開いただけで立ち去った人まで、後のログインで参加させてしまう
    describe 'ログイン済みで未参加のとき' do
      before do
        log_in_as(create(:user))

        open_invitation
      end

      it '「参加する」で参加できる' do
        expect(response.body).to include('参加する')
        expect(response.body).to include(
          %(action="#{invitation_participation_path(exchange.invite_token)}")
        )
      end
    end

    describe '未ログインのとき' do
      before { open_invitation }

      # 押した先が Google なので、押す前にそう分かるようにする
      it '「ログインして参加する」で参加の意図を伝える' do
        expect(response.body).to include('ログインして参加する')
        expect(response.body).to include(
          %(action="#{invitation_participation_path(exchange.invite_token)}")
        )
      end

      # 戻り先はサーバーが見たパスだけを覚える。パラメータや Referer から
      # 受け取ると、もっともらしい招待リンクで認証直後に外部サイトへ落とせる
      it 'ログインしたら招待URLへ戻す' do
        log_in_as(create(:user))

        expect(response).to redirect_to(invitation_path(exchange.invite_token))
      end
    end

    describe '参加済みのとき' do
      let!(:participant) { create(:user) }

      before do
        create(:participation, exchange:, user: participant)
        log_in_as(participant)

        open_invitation
      end

      it '参加済みであることが分かる' do
        expect(response.body).to include('すでに参加しています')
      end

      it '参加のボタンを出さない' do
        expect(response.body).not_to include('参加する')
      end

      # この画面は未参加の人のためのもの。辞退の導線があるので追い返しはしないが、
      # 行き先を示さないと、参加したあと何をすればよいのか分からない
      it '交換会トップへの導線が出る' do
        expect(response.body).to include(exchange_path(exchange))
      end

      # 取り消すと登録した本も消える。押し間違いで戻せなくなるため確認を挟む
      it '確認つきの辞退ボタンが出る' do
        expect(response.body).to include('参加を取り消す')
        expect(response.body).to include('data-turbo-confirm')
      end

      # 希望提出期間に入ってから抜けられると、取得枠の計算が壊れる。
      it '登録の締切ちょうどからは辞退ボタンを出さない' do
        travel_to '2026-08-24T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response.body).not_to include('参加を取り消す')
        end
      end
    end

    # 主催者はこの経路を通らない。交換会を作る操作がそのまま参加の意思表示にあたる
    describe '主催者が開いたとき' do
      before do
        exchange.join!(owner, at: '2026-08-15T10:00:00+09:00'.in_time_zone)
        log_in_as(owner)

        open_invitation
      end

      it '参加済みとして扱う' do
        expect(response.body).to include('すでに参加しています')
      end

      # 主催者は抜けられない
      it '辞退ボタンを出さない' do
        expect(response.body).not_to include('参加を取り消す')
      end

      it '交換会トップへの導線が出る' do
        expect(response.body).to include(exchange_path(exchange))
      end
    end

    # 参加できるのは登録期間の締切まで。判定はサーバーが受けた時刻で行い、
    # 可否の条件は Exchange::WRITABLE_PHASES に集約する
    describe '参加を受け付ける期間' do
      it '準備中でも参加できる' do
        travel_to '2026-08-01T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response.body).to include('参加する')
        end
      end

      # 各期間は終了時刻を含まない。締切ちょうどはもう登録期間の外になる
      it '登録の締切ちょうどからは参加できない' do
        travel_to '2026-08-24T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response.body).to include('この交換会には参加できません')
          expect(response.body).not_to include('参加する')
        end
      end

      it '締切を過ぎていても交換会の概要は見える' do
        travel_to '2026-09-01T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response).to have_http_status(:ok)
          expect(response.body).to include('夏の交換会')
        end
      end

      # 締め出されたのではなく、途中参加ができない仕組みなのだと伝える。
      # 理由が無いと、主催者に掛け合えば入れてもらえるようにも読める
      it '参加できない理由が出る' do
        travel_to '2026-09-01T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response.body).to include('登録冊数と取得枠の釣り合い')
        end
      end

      # 概要と日程だけは見せたままにする。何の集まりだったのかも分からずに
      # 追い返されると、次に誘ってもらう相談もできない
      it '日程が終了・進行中・予定で見える' do
        travel_to '2026-09-01T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response.body).to include('終了')
          expect(response.body).to include('進行中')
          expect(response.body).to include('予定')
        end
      end

      # 行き先を示さないと、この画面で行き止まりになる
      it 'ログイン済みなら交換会一覧への導線が出る' do
        log_in_as(create(:user))

        travel_to '2026-09-01T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response.body).to include(exchanges_path)
        end
      end

      # 未ログインの人に一覧を出しても、参加していない以上そこは空になる。
      # ログインを促すだけの導線は、参加できないと言った直後に置くものではない
      it '未ログインでは交換会一覧への導線を出さない' do
        travel_to '2026-09-01T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response.body).not_to include('自分の交換会一覧へ')
        end
      end
    end

    # 参加を決める前に、いつまで考えられるのかと、次に何が起きるまで何日あるのかを出す
    describe '参加を受け付ける締切の案内' do
      it '準備中は登録期間の開始までの残りが出る' do
        travel_to '2026-08-05T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response.body).to include('2026年8月24日 10:00')
          expect(response.body).to include('登録期間の開始')
          expect(response.body).to include('あと5日')
        end
      end

      it '登録期間は登録の締切までの残りが出る' do
        travel_to '2026-08-20T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response.body).to include('登録の締切')
          expect(response.body).to include('あと4日')
        end
      end

      # 参加できないときに締切までの残りを出すと、まだ間に合うように読める
      it '参加できないときは出さない' do
        travel_to '2026-09-01T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response.body).not_to include('参加できるのは')
        end
      end
    end

    # 招待URLを知っているだけの人が開く画面なので、参加者向けの情報を一切載せない
    describe '載せない情報' do
      it '本の情報とギフトコードが含まれない' do
        book = create(:book, title: '吾輩は猫である', gift_code: 'GIFTCODE12345678',
                             participation: create(:participation, exchange:))

        get invitation_path(exchange.invite_token)

        expect(response.body).not_to include(book.title)
        expect(response.body).not_to include('GIFTCODE12345678')
      end
    end
  end
end
