# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DevelopmentSeeds do
  # フェーズは日時から導出されるため、データを作るときの基準時刻を固定して、
  # できた結果を同じ時刻で読む
  let!(:at) { Time.zone.parse('2026-08-08 12:00:00') }

  def seed(at:)
    described_class.new(at:).call
  end

  delegate :viewer, to: :described_class

  describe '#call' do
    before { seed(at:) }

    it '5つのフェーズがすべて揃う' do
      expect(Exchange.all.map { |exchange| exchange.phase(at:) }.uniq)
        .to match_array(Exchange::PHASES)
    end

    # 主催者は必ず参加者を兼ねる。
    # DB の制約では守れないので、データを作る側で守る
    it 'どの交換会にも主催者の参加がある' do
      not_participating = Exchange.all.reject { |exchange| exchange.participant?(exchange.owner) }

      expect(not_participating).to be_empty
    end

    # 一覧に並ぶのは参加している交換会だけ。参加していない交換会は、
    # 作ってあっても画面から辿り着けない
    it '主役がすべての交換会に参加していて一覧から辿れる' do
      expect(viewer.exchanges).to match_array(Exchange.all)
    end

    it '二度目以降も交換会は増えない' do
      expect { seed(at:) }.not_to change(Exchange, :count)
    end

    # マッチングは一度だけ実行でき、再実行できない（CLAUDE.md「マッチング」）。
    # 二度目の db:seed は実行のやり直しではないので、割当はそのまま残す
    it '二度目以降も割当は作り直されない' do
      expect { seed(at:) }.not_to change(Assignment, :count)
    end

    # 「締切まで残り数時間」は基準時刻からの相対で決まるため、放置すれば次のフェーズへ移る。
    # もう一度通せば足りる範囲とするので、数え直されること自体は固定する
    it '二度目以降は締切が新しい基準時刻から数え直される' do
      later = at + 3.days

      expect { seed(at: later) }
        .to change { deadline_within(6.hours, at: later) }.from(be_empty).to(be_present)
    end

    # 名前を変えたときに、古い開発用データだけ前の名前で残ると、画面に出ている
    # 人が誰なのかを読み違える。交換会の属性を毎回上書きするのと同じ扱いにする
    it '二度目以降は利用者の名前が書き直される' do
      user = viewer
      user.update!(display_name: '古い名前')

      expect { seed(at:) }.to change { user.reload.display_name }.from('古い名前')
    end

    # 実行日時だけ据え置くと、ほかの日時が動いたぶんだけ結果公開の日付が取り残される
    it '二度目以降はマッチング実行日時も数え直される' do
      later = at + 3.days
      matched = Exchange.where.not(matched_at: nil).to_a
      matched_at = -> { matched.map { |exchange| exchange.reload.matched_at } }

      expect { seed(at: later) }.to change(&matched_at)
    end
  end

  # 確かめたい状態が一通りできているかを見る。
  # 「ある」ことだけを確かめ、どの交換会が担うかは固定しない。
  # 担い手を名指しすると、シナリオを組み替えるたびに spec を書き換えることになる
  describe '状態バリエーション' do
    include ActiveJob::TestHelper

    before { seed(at:) }

    it '交換会に本が1冊も登録されていない' do
      empty = in_phase(:registration, at:).select { |exchange| exchange.books.empty? }

      expect(empty).to be_present
    end

    # 取得枠は登録冊数と同数なので、0冊なら1冊も受け取れない
    it '自分がまだ1冊も登録していない' do
      unregistered = in_phase(:registration, at:).select do |exchange|
        participation_of(viewer, exchange).books.empty?
      end

      expect(unregistered).to be_present
    end

    it '希望リストが空のまま希望提出期間の締切が迫っている' do
      idle = deadline_within(6.hours, at:).select do |exchange|
        exchange.phase(at:) == :wish && participation_of(viewer, exchange).wishes.empty?
      end

      expect(idle).to be_present
    end

    # 交換会一覧の空状態と、招待URL着地画面の「これから参加する」は、
    # どこにも参加していない人としてしか見られない。主役はすべての
    # 交換会に入っているので、主役として見ているかぎり一生出てこない
    it 'どこにも参加していない利用者がいる' do
      outsiders = User.all.reject { |user| user.exchanges.any? }

      expect(outsiders).to be_present
    end

    it '参加者が自分ひとりしかいない' do
      solo = Exchange.all.select { |exchange| exchange.participations.map(&:user) == [viewer] }

      expect(solo).to be_present
    end

    # 警告は主催者管理画面にしか出ず、出るのは本を登録できるあいだだけ。
    # 主役が主催者でなければ画面自体を開けないので、そこまで含めて見る。
    # 出るかどうかは画面と同じサービスに訊く
    it '登録冊数の偏りの警告を主催者として見られる' do
      warned = Exchange.all.select do |exchange|
        exchange.owner == viewer && exchange.writable?(:book, at:) &&
          Exchanges::BookImbalance.new(exchange.participations.with_counts).call.present?
      end

      expect(warned).to be_present
    end

    it '期間の締切まで残り数時間' do
      expect(deadline_within(6.hours, at:)).to be_present
    end

    # 通知（#42）は Discord と Slack の両方の形式に対応する。交換会は Webhook URL を
    # 1つしか持たないので、両方を手元で試すには形式ごとに1件ずつ要る
    it 'Discord と Slack の Webhook URL がそれぞれ入っている' do
      urls = Exchange.where.not(webhook_url: nil).pluck(:webhook_url)

      expect(urls).to include(a_string_including('discord.com'),
                              a_string_including('hooks.slack.com'))
    end

    # seed が作るのは、日時だけを過去に置いた作り物にあたる。通知の記録を埋めずに
    # 置くと、予約が一斉に走って偽の Webhook URL への送信が積まれる。
    # 手元で通知を試すときは、日時を動かせば新しい予約が積まれる
    it 'どの交換会も通知を知らせ済みにしてある' do
      unnotified = Exchange.all.reject { |exchange| exchange.notified_phase == exchange.phase(at:).to_s }

      expect(unnotified).to be_empty
    end

    # 締切まで残り数時間の交換会をわざと作ってあるので、記録を埋めずに置くと
    # リマインドが一斉に走る
    it 'どの交換会も締切前のリマインドを出し済みにしてある' do
      expect { Notifications::DeadlineReminder.deliver_all(at:) }
        .not_to have_enqueued_job(Notifications::DeliverJob)
    end

    it '自分の本が返却された' do
      returned = Assignment.where(returned: true)
                           .select { |assignment| assignment.book.participation.user == viewer }

      expect(returned).to be_present
    end

    # 受け取りが0冊のとき、結果画面は枠が無かったのか回ってこなかったのかを
    # 言い分ける。言い分けを見るための状態なので、
    # どちらも主役が0冊であること。他人として見ても文面は出ない
    it '取得枠が0のまま結果公開を迎えた交換会がある' do
      no_slots = published_participations_of(viewer, at:).select do |participation|
        participation.books.empty? && participation.received_assignments.empty?
      end

      expect(no_slots).to be_present
    end

    # もう片方の言い分け。枠はあったのに割り当てられる本が残らなかった場合。
    # 総冊数と総取得枠は必ず等しいので、枠が空いたまま終わるには、
    # 残った本が自分のものでなければならない。返却が伴うのは避けられない
    it '取得枠はあったのに1冊も回ってこなかった交換会がある' do
      unlucky = published_participations_of(viewer, at:).select do |participation|
        participation.books.any? && participation.received_assignments.empty?
      end

      expect(unlucky).to be_present
    end

    # 全体の成立結果は、並べるものが無ければ節ごと畳む。
    # 見出しと列名だけの表が残っていないかを、この交換会でしか確かめられない
    it '本が1冊も登録されないまま実行された結果公開の交換会がある' do
      empty = in_phase(:published, at:).select { |exchange| exchange.result_books.empty? }

      expect(empty).to be_present
    end

    # 受け取った本が1冊も無いと、結果画面もギフトコードの可視性も確かめられない。
    # 見えるかどうかは本人に訊く。作る側の意図ではなく、実際の可視性の規則で見る
    it '自分が受け取った本のギフトコードが開ける' do
      received = Book.all.select do |book|
        book.participation.user != viewer && book.gift_code_visible_to?(viewer, at:)
      end

      expect(received).to be_present
    end
  end

  # 入口。ここを通らないと、bin/rails db:seed からは何も起きない
  describe 'db/seeds.rb' do
    def load_seed_in(env)
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new(env))

      Rails.application.load_seed
    end

    it 'development では作り、できた件数を知らせる' do
      allow($stdout).to receive(:puts)

      expect { load_seed_in('development') }.to change(Exchange, :count)
      expect($stdout).to have_received(:puts).with(/交換会 \d+ 件/)
    end

    # 本番のデータベースへ架空の交換会を流し込まない
    it 'production では作らない' do
      expect { load_seed_in('production') }.not_to change(Exchange, :count)
    end

    # db:prepare はデータベースを作ったときに seed も通す。まっさらな test の
    # データベースを毎回作る CI では、rspec が始まる前にデータができてしまい、
    # 件数を数える spec がその分だけずれて落ちる
    it 'test では作らない' do
      expect { Rails.application.load_seed }.not_to change(Exchange, :count)
    end
  end

  def in_phase(phase, at:)
    Exchange.all.select { |exchange| exchange.phase(at:) == phase }
  end

  def participation_of(user, exchange)
    exchange.participations.find_by!(user:)
  end

  # 結果公開を迎えた交換会での、その人の参加。結果画面が見るものはここから引ける
  def published_participations_of(user, at:)
    in_phase(:published, at:).map { |exchange| participation_of(user, exchange) }
  end

  # 次の締切が指定した時間内に迫っている交換会
  def deadline_within(duration, at:)
    Exchange.all.select do |exchange|
      deadline = exchange.next_deadline(at:)
      deadline.present? && deadline.between?(at, at + duration)
    end
  end
end
