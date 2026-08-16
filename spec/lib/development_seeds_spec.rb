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

    # 主催者は必ず参加者を兼ねる（docs/spec.md 2. 用語 / 6.9）。
    # DB の制約では守れないので、データを作る側で守る
    it 'どの交換会にも主催者の参加がある' do
      not_participating = Exchange.all.reject { |exchange| exchange.participant?(exchange.owner) }

      expect(not_participating).to be_empty
    end

    # 一覧に並ぶのは参加している交換会だけ。参加していない交換会は、
    # 作ってあっても画面から辿り着けない
    it '「あなた」がすべての交換会に参加していて一覧から辿れる' do
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

    # 実行日時だけ据え置くと、ほかの日時が動いたぶんだけ結果公開の日付が取り残される
    it '二度目以降はマッチング実行日時も数え直される' do
      later = at + 3.days
      matched = Exchange.where.not(matched_at: nil).to_a
      matched_at = -> { matched.map { |exchange| exchange.reload.matched_at } }

      expect { seed(at: later) }.to change(&matched_at)
    end
  end

  # できたデータが docs/spec.md 9. を満たしているかを見る。
  # 「ある」ことだけを確かめ、どの交換会が担うかは固定しない。
  # 担い手を名指しすると、シナリオを組み替えるたびに spec を書き換えることになる
  describe '状態バリエーション' do
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

    # 交換会一覧の空状態（docs/spec.md 6.6）と、招待URL着地画面の「これから参加する」
    # （6.7）は、どこにも参加していない人としてしか見られない。主役はすべての
    # 交換会に入っているので、主役として見ているかぎり一生出てこない
    it 'どこにも参加していない利用者がいる' do
      outsiders = User.all.reject { |user| user.exchanges.any? }

      expect(outsiders).to be_present
    end

    it '参加者が自分ひとりしかいない' do
      solo = Exchange.all.select { |exchange| exchange.participations.map(&:user) == [viewer] }

      expect(solo).to be_present
    end

    # 警告は主催者管理画面にしか出ず、出るのは本を登録できるあいだだけ（6.8）。
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

    it '自分の本が返却された' do
      returned = Assignment.where(returned: true)
                           .select { |assignment| assignment.book.participation.user == viewer }

      expect(returned).to be_present
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

  # 次の締切が指定した時間内に迫っている交換会
  def deadline_within(duration, at:)
    Exchange.all.select do |exchange|
      deadline = exchange.next_deadline(at:)
      deadline.present? && deadline.between?(at, at + duration)
    end
  end
end
