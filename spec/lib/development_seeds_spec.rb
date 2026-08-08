# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DevelopmentSeeds do
  # フェーズは日時から導出されるため、撒く側の基準時刻を固定して、
  # 撒いた結果を同じ時刻で読む
  let!(:at) { Time.zone.parse('2026-08-08 12:00:00') }

  def sow(at:)
    described_class.new(at:).call
  end

  delegate :viewer, to: :described_class

  describe '#call' do
    before { sow(at:) }

    it '5つのフェーズがすべて揃う' do
      expect(Exchange.all.map { |exchange| exchange.phase(at:) }.uniq)
        .to match_array(Exchange::PHASES)
    end

    # 主催者は必ず参加者を兼ねる（docs/spec.md 2. 用語 / 6.9）。
    # DB の制約では守れないので、撒く側で守る
    it 'どの交換会にも主催者の参加がある' do
      not_participating = Exchange.all.reject { |exchange| exchange.participant?(exchange.owner) }

      expect(not_participating).to be_empty
    end

    # 一覧に並ぶのは参加している交換会だけ。参加していない交換会は、
    # 撒いてあっても画面から辿り着けない
    it '「あなた」がすべての交換会に参加していて一覧から辿れる' do
      expect(viewer.exchanges).to match_array(Exchange.all)
    end

    it '撒き直しても交換会は増えない' do
      expect { sow(at:) }.not_to change(Exchange, :count)
    end

    # 「締切まで残り数時間」は実時刻からの相対で撒くため、放置すれば次のフェーズへ移る。
    # 撒き直しで足りる範囲とするので、撒き直したら数え直されること自体は固定する
    it '撒き直すと締切が撒いた時刻から数え直される' do
      later = at + 3.days

      expect { sow(at: later) }
        .to change { deadline_within(6.hours, at: later) }.from(be_empty).to(be_present)
    end
  end

  # 撒いたデータが docs/spec.md 9. を満たしているかを見る。
  # 「ある」ことだけを確かめ、どの交換会が担うかは固定しない。
  # 担い手を名指しすると、シナリオを組み替えるたびに spec を書き換えることになる
  describe '状態バリエーション' do
    before { sow(at:) }

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

    it '参加者が自分ひとりしかいない' do
      solo = Exchange.all.select { |exchange| exchange.participations.map(&:user) == [viewer] }

      expect(solo).to be_present
    end

    it '期間の締切まで残り数時間' do
      expect(deadline_within(6.hours, at:)).to be_present
    end

    it '自分の本が返却された' do
      returned = Assignment.where(returned: true)
                           .select { |assignment| assignment.book.participation.user == viewer }

      expect(returned).to be_present
    end

    # 受け取った本が1冊も無いと、結果画面もギフトコードの可視性も確かめられない。
    # 見えるかどうかは本人に訊く。撒く側の意図ではなく、実際の可視性の規則で見る
    it '自分が受け取った本のギフトコードが開ける' do
      received = Book.all.select do |book|
        book.participation.user != viewer && book.gift_code_visible_to?(viewer, at:)
      end

      expect(received).to be_present
    end
  end

  # 撒く入口。ここを通らないと、bin/rails db:seed からは何も起きない
  describe 'db/seeds.rb' do
    def load_seed_in(env)
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new(env))

      Rails.application.load_seed
    end

    it 'development では撒き、撒いた件数を知らせる' do
      allow($stdout).to receive(:puts)

      expect { load_seed_in('development') }.to change(Exchange, :count)
      expect($stdout).to have_received(:puts).with(/交換会 \d+ 件/)
    end

    # 本番のデータベースへ架空の交換会を流し込まない
    it 'production では撒かない' do
      expect { load_seed_in('production') }.not_to change(Exchange, :count)
    end

    # db:prepare はデータベースを作ったときに seed も撒く。まっさらな test の
    # データベースを毎回作る CI では、rspec が始まる前に撒かれてしまい、
    # 件数を数える spec が撒いた分だけずれて落ちる
    it 'test では撒かない' do
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
