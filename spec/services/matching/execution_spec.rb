# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Matching::Execution do
  let!(:exchange) do
    create(:exchange,
           registration_starts_at: '2026-08-01T10:00:00+09:00'.in_time_zone,
           registration_ends_at: '2026-08-15T10:00:00+09:00'.in_time_zone,
           wish_ends_at: '2026-08-29T10:00:00+09:00'.in_time_zone)
  end

  # マッチング実行待ち。実行できる時刻の既定として使う
  let!(:awaiting_matching) { '2026-08-30T10:00:00+09:00'.in_time_zone }

  # 主催者の参加は factory が作る。1冊も登録しなければ取得枠が0で、どの割当にも現れない
  let!(:owner_participation) { exchange.participations.find_by!(user: exchange.owner) }

  def join(display_name)
    create(:participation, exchange:, user: create(:user, display_name:))
  end

  def register(participation, count)
    create_list(:book, count, participation:)
  end

  def wish(participation, books)
    books.each_with_index { |book, index| create(:wish, participation:, book:, position: index + 1) }
  end

  def execute(at: awaiting_matching)
    described_class.new(exchange:, at:).call
  end

  # 全員が1冊ずつ登録し、互いの本を希望している。返却の出ない素直な成立
  def build_round_robin
    participations = [owner_participation, join('りく'), join('ゆうと')]
    books = participations.map { |participation| register(participation, 1).first }

    participations.each_with_index do |participation, index|
      others = books.reject { |book| book.participation_id == participation.id }
      wish(participation, others.rotate(index))
    end

    [participations, books]
  end

  # 誰も希望を出さなければ、割当は余り物の配り方だけで決まる。
  # 同じ形の交換会を並べて、シードの違いだけが結果に出るようにする。
  # 返すのは「何冊目の本が何人目の参加者に渡ったか」の並び。
  # レコードの id は交換会ごとに変わるので、並び順の位置で見る
  def lottery_pattern(seed)
    lottery = create(:exchange, random_seed: seed,
                                registration_starts_at: exchange.registration_starts_at,
                                registration_ends_at: exchange.registration_ends_at,
                                wish_ends_at: exchange.wish_ends_at)
    participations = [lottery.participations.sole] + create_list(:participation, 4, exchange: lottery)
    books = participations.map { |participation| create(:book, participation:) }

    described_class.new(exchange: lottery, at: awaiting_matching).call

    ids = participations.map(&:id)
    books.map { |book| ids.index(Assignment.find_by!(book:).participation_id) }
  end

  it '割当を保存する' do
    _participations, books = build_round_robin

    execute

    expect(Assignment.count).to eq(books.size)
  end

  it 'マッチング実行日時を記録する' do
    build_round_robin

    execute

    expect(exchange.reload.matched_at).to eq(awaiting_matching)
  end

  it '交換会が結果公開フェーズに入る' do
    build_round_robin

    execute

    expect(exchange.reload.phase(at: awaiting_matching)).to eq(:published)
  end

  describe '成立の中身' do
    # 登録した冊数だけ受け取り、自分が登録した本は受け取れない
    it '全員が登録した冊数だけ受け取る' do
      participations, = build_round_robin

      execute

      received = Assignment.where(returned: false).group(:participation_id).count
      expect(received.keys).to match_array(participations.map(&:id))
      expect(received.values).to all(eq(1))
    end

    it '自分が登録した本は受け取らない' do
      build_round_robin

      execute

      own = Assignment.joins(:book)
                      .where(returned: false)
                      .where('books.participation_id = assignments.participation_id')
      expect(own).to be_empty
    end

    # 希望から取れた割当は何巡目かが分かる。余り物は巡の外で配られる
    it '希望から取れた割当には巡が入る' do
      build_round_robin

      execute

      expect(Assignment.pluck(:round)).to all(eq(1))
    end

    # りくの3冊はゆうとが1冊しか受け取れず、残る2冊には渡す先が無い
    it '渡す先の無かった本は返却として登録者に紐づく' do
      riku = join('りく')
      yuto = join('ゆうと')
      riku_books = register(riku, 3)
      yuto_book = register(yuto, 1).first
      wish(riku, [yuto_book])
      wish(yuto, [riku_books.first])

      execute

      returned = Assignment.where(returned: true).includes(:book)
      expect(returned.count).to eq(2)
      expect(returned.pluck(:participation_id)).to all(eq(riku.id))
      # 返却は登録者の手元へ戻る。本の登録者と割当の相手が一致する
      expect(returned.map { |assignment| assignment.book.participation_id }).to all(eq(riku.id))
      expect(returned.pluck(:round)).to all(be_nil)
    end

    # 参加者が自分ひとりしかいない交換会
    it '参加者がひとりだけなら全冊が返却として成立する' do
      register(owner_participation, 3)

      execute

      expect(Assignment.count).to eq(3)
      expect(Assignment.where(returned: true).count).to eq(3)
      expect(Assignment.pluck(:participation_id)).to all(eq(owner_participation.id))
    end

    # 希望を出さなかった人も受け取る権利は失わない
    it '希望を出さなかった参加者にも取得枠の分だけ割り当てられる' do
      riku = join('りく')
      yuto = join('ゆうと')
      riku_books = register(riku, 2)
      register(yuto, 2)
      wish(yuto, riku_books)

      execute

      expect(Assignment.where(participation: riku, returned: false).count).to eq(2)
    end

    # 1冊も登録しなかった人は取得枠が0で受け取れない
    it '1冊も登録しなかった参加者には割り当てられない' do
      build_round_robin
      empty_handed = join('はるか')

      execute

      expect(Assignment.where(participation: empty_handed)).to be_empty
    end
  end

  # 抽選順は結果公開後に見せてよい。実行のときにしか決まらないので、
  # Engine が返した並びを参加へ書き戻す
  describe '抽選順' do
    it '参加者全員に1から始まる連番が入る' do
      participations, = build_round_robin

      execute

      expect(participations.map { it.reload.draft_position }).to match_array(1..participations.size)
    end

    # 取得枠が0でも抽選には並ぶ。抜けた番号があると、除外された人がいるように読める
    it '1冊も登録しなかった参加者にも入る' do
      build_round_robin
      empty_handed = join('はるか')

      execute

      expect(empty_handed.reload.draft_position).not_to be_nil
    end

    it '拒否されたら抽選順も残らない' do
      participations, = build_round_robin

      begin
        execute(at: '2026-08-20T10:00:00+09:00'.in_time_zone)
      rescue Exchange::PhaseViolation
        nil
      end

      expect(participations.map { it.reload.draft_position }).to all(be_nil)
    end
  end

  describe 'マッチング実行待ちより前' do
    before { build_round_robin }

    # 書き込みの可否はサーバー側で検証する
    it '希望提出期間のうちは実行できない' do
      expect { execute(at: '2026-08-20T10:00:00+09:00'.in_time_zone) }
        .to raise_error(Exchange::PhaseViolation)
    end

    it '登録期間のうちは実行できない' do
      expect { execute(at: '2026-08-10T10:00:00+09:00'.in_time_zone) }
        .to raise_error(Exchange::PhaseViolation)
    end

    # 各期間は終了時刻を含まない。希望提出の締切ちょうどはもうマッチング実行待ち
    it '希望提出の締切ちょうどには実行できる' do
      expect { execute(at: exchange.wish_ends_at) }.to change(Assignment, :count).from(0)
    end

    it '拒否されたら割当も実行日時も残らない' do
      begin
        execute(at: '2026-08-20T10:00:00+09:00'.in_time_zone)
      rescue Exchange::PhaseViolation
        nil
      end

      expect(Assignment.count).to eq(0)
      expect(exchange.reload.matched_at).to be_nil
    end
  end

  # マッチングは一度だけ実行でき、再実行できない（CLAUDE.md「マッチング」）
  describe '実行済みの交換会' do
    before do
      build_round_robin
      execute
    end

    it '再実行が拒否される' do
      expect { execute }.to raise_error(Exchange::PhaseViolation)
    end

    it '再実行しても割当は増えない' do
      expect { execute }.to raise_error(Exchange::PhaseViolation)
      expect(Assignment.count).to eq(3)
    end

    # 実行後に主催者が締切を先へ動かしても、結果公開のままで実行し直せない
    it '締切を動かしても再実行できない' do
      exchange.update!(wish_ends_at: '2026-09-30T10:00:00+09:00'.in_time_zone)

      expect { execute }.to raise_error(Exchange::PhaseViolation)
    end
  end

  # 途中で落ちた結果が残ると、割当の一部だけが見える交換会ができる。
  # 実行日時も入らないので、その状態からやり直すこともできない
  describe '実行の途中で例外が起きたとき' do
    before { build_round_robin }

    it '書けていた割当も巻き戻る' do
      # 1件目を保存したあとで落とす。何も書けずに落ちたのでは、
      # 巻き戻ったのか最初から書いていないのかを見分けられない
      saved = 0
      allow(Assignment).to receive(:create!).and_wrap_original do |original, *args|
        saved += 1
        raise ActiveRecord::StatementInvalid, '保存に失敗した' if saved == 2

        original.call(*args)
      end

      expect { execute }.to raise_error(ActiveRecord::StatementInvalid)
      expect(Assignment.count).to eq(0)
      expect(exchange.reload.matched_at).to be_nil
    end

    it '実行日時の記録で落ちても割当が残らない' do
      allow(exchange).to receive(:update!).and_raise(ActiveRecord::StatementInvalid, '保存に失敗した')

      expect { execute }.to raise_error(ActiveRecord::StatementInvalid)
      expect(Assignment.count).to eq(0)
      expect(exchange.reload.matched_at).to be_nil
    end
  end

  # 主催者が二度押しした場合も、複数のタブから同時に押した場合もここに落ちる
  describe '同時に呼ばれたとき' do
    # 行ロックが効くことを見るには本物のトランザクションが要る。example ごと
    # トランザクションで包んだままだと、別スレッドからは作ったデータが見えない。
    # 巻き戻しが無くなるぶん、後始末は自分で書く
    self.use_transactional_tests = false

    after do
      # 外部キーの向きに沿って消す
      Assignment.delete_all
      Wish.delete_all
      Book.delete_all
      Participation.delete_all
      Exchange.delete_all
      User.delete_all
    end

    it '1回しか走らない' do
      build_round_robin
      # 両方が交換会を読み終えてから走り出させる。読む前に片方が終わってしまうと、
      # あとから来たほうは手元の matched_at を見るだけで断れてしまい、
      # ロックが効いているのかどうかが分からない
      loaded = Thread::Queue.new
      gate = Thread::Queue.new

      threads = Array.new(2) do
        # with_connection で借りて返す。スレッドを終えるだけだと、
        # 中途半端な状態の接続がプールに戻り、あとの example がそれを引く
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            target = Exchange.find(exchange.id)
            loaded.push(true)
            gate.pop

            described_class.new(exchange: target, at: awaiting_matching).call
            nil
          rescue Exchange::PhaseViolation => e
            e
          end
        end
      end

      2.times { loaded.pop }
      2.times { gate.push(true) }
      rejections = threads.filter_map(&:value)

      expect(rejections.size).to eq(1)
      expect(Assignment.count).to eq(3)
      expect(exchange.reload.matched_at).to eq(awaiting_matching)
    end
  end

  describe '乱数シード' do
    # 実行時にシードを作っていたら、揃えた交換会どうしでも配り方がばらつく
    it '同じシードの交換会は同じ割当になる' do
      # 呼ぶたびに別の交換会を作るので、同じ引数でも同じものを2度数えてはいない
      first = lottery_pattern(20_260_809)
      second = lottery_pattern(20_260_809)

      expect(first).to eq(second)
    end

    # 交換会のシードを読まずに固定値で回していないことを見る
    it '違うシードの交換会は違う割当になる' do
      expect(lottery_pattern(20_260_809)).not_to eq(lottery_pattern(20_260_810))
    end
  end
end
