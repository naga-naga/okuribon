# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Matching::Engine do
  # spec に渡す本を組み立てる。build_books("A" => 2) は A1, A2 を返す
  def build_books(spec)
    spec.flat_map do |owner, count|
      (1..count).map { |i| Matching::Book.new(id: "#{owner}#{i}", owner_id: owner) }
    end
  end

  def run_matching(participants:, books:, wishes:, seed:)
    described_class.new(
      participants: participants, books: books, wishes: wishes, seed: seed
    ).call
  end

  # participants / books / wishes / result を let で定義した文脈で使う
  shared_examples 'マッチングの不変条件を満たす' do
    it 'すべての本がちょうど1人に渡る' do
      counts = result.assignments.group_by(&:book_id).transform_values(&:size)

      expect(counts.keys).to match_array(books.map(&:id))
      expect(counts.values).to all(eq(1))
    end

    it '各参加者の取得数が取得枠と一致する' do
      taken = result.assignments.group_by(&:participant_id).transform_values(&:size)

      participants.each do |participant|
        actual = taken.fetch(participant, 0)
        expected = result.quotas[participant]

        expect(actual).to eq(expected), "#{participant}: 取得 #{actual}冊 / 枠 #{expected}冊"
      end
    end

    it '返却された本は出品者本人に戻り、それ以外は必ず他人に渡る' do
      owner_of = books.to_h { |book| [book.id, book.owner_id] }

      result.assignments.each do |assignment|
        if assignment.returned?
          expect(assignment.participant_id).to eq(owner_of[assignment.book_id])
        else
          expect(assignment.participant_id).not_to eq(owner_of[assignment.book_id])
        end
      end
    end

    it 'ドラフトで確定した本は必ず本人の希望リストに載っている' do
      result.assignments.select(&:from_draft?).each do |assignment|
        expect(wishes.fetch(assignment.participant_id, [])).to include(assignment.book_id)
      end
    end
  end

  # ------------------------------------------------------------------
  context '標準的な構成（4人・各2冊・希望はばらける）' do
    let(:participants) { ['A', 'B', 'C', 'D'] }
    let(:books) { build_books('A' => 2, 'B' => 2, 'C' => 2, 'D' => 2) }
    let(:wishes) do
      {
        'A' => ['B1', 'C1', 'D1', 'B2', 'C2', 'D2'],
        'B' => ['C1', 'D1', 'A1', 'C2', 'D2', 'A2'],
        'C' => ['D1', 'A1', 'B1', 'D2', 'A2', 'B2'],
        'D' => ['A1', 'B1', 'C1', 'A2', 'B2', 'C2'],
      }
    end
    let(:result) { run_matching(participants: participants, books: books, wishes: wishes, seed: 12_345) }

    it_behaves_like 'マッチングの不変条件を満たす'

    it '返却は1冊も発生しない' do
      expect(result.assignments).to all(satisfy { |a| !a.returned? })
    end

    it '全員が上位の希望から順に確保している' do
      expect(result.assignments.count(&:from_draft?)).to eq(8)
    end
  end

  # ------------------------------------------------------------------
  context '冊数が偏り、受け取り手のない本が出る（A=5冊・B=1冊）' do
    let(:participants) { ['A', 'B'] }
    let(:books) { build_books('A' => 5, 'B' => 1) }
    let(:wishes) { { 'A' => ['B1'], 'B' => ['A1', 'A2', 'A3', 'A4', 'A5'] } }
    let(:result) { run_matching(participants: participants, books: books, wishes: wishes, seed: 777) }

    it_behaves_like 'マッチングの不変条件を満たす'

    it 'Aの本のうち4冊が返却される' do
      returned = result.assignments.select(&:returned?)

      expect(returned.size).to eq(4)
      expect(returned.map(&:participant_id)).to all(eq('A'))
    end

    it 'Bは1冊しか枠がないので1冊だけ受け取る' do
      expect(result.quotas['B']).to eq(1)
      expect(result.assignments.count { |a| a.participant_id == 'B' }).to eq(1)
    end
  end

  # ------------------------------------------------------------------
  context '全員の希望が同じ本に集中し、すぐ枯渇する' do
    let(:participants) { ['A', 'B', 'C', 'D'] }
    let(:books) { build_books('A' => 1, 'B' => 1, 'C' => 1, 'D' => 1) }
    let(:wishes) { { 'A' => ['B1'], 'B' => ['A1'], 'C' => ['A1'], 'D' => ['A1'] } }
    let(:result) { run_matching(participants: participants, books: books, wishes: wishes, seed: 42) }

    it_behaves_like 'マッチングの不変条件を満たす'

    it '希望が叶わなかった参加者にも余り物が割り当てられる' do
      expect(result.assignments.size).to eq(4)
    end
  end

  # ------------------------------------------------------------------
  context '希望を一切出さなかった参加者がいる' do
    let(:participants) { ['A', 'B', 'C'] }
    let(:books) { build_books('A' => 2, 'B' => 2, 'C' => 2) }
    let(:wishes) { { 'A' => ['B1', 'C1', 'B2', 'C2'], 'B' => ['A1', 'C1', 'A2', 'C2'] } }
    let(:result) { run_matching(participants: participants, books: books, wishes: wishes, seed: 999) }

    it_behaves_like 'マッチングの不変条件を満たす'

    it '希望未提出のCも取得枠のぶんだけ受け取れる' do
      received = result.assignments.select { |a| a.participant_id == 'C' }

      expect(received.size).to eq(2)
    end

    it 'Cへの割当はすべて余り物である' do
      received = result.assignments.select { |a| a.participant_id == 'C' }

      expect(received).to all(satisfy { |a| !a.from_draft? })
    end
  end

  # ------------------------------------------------------------------
  context '参加者が1人しかいない' do
    let(:participants) { ['A'] }
    let(:books) { build_books('A' => 3) }
    let(:wishes) { { 'A' => ['A1', 'A2', 'A3'] } }
    let(:result) { run_matching(participants: participants, books: books, wishes: wishes, seed: 5) }

    it_behaves_like 'マッチングの不変条件を満たす'

    it '3冊すべてが本人へ返却される' do
      expect(result.assignments.size).to eq(3)
      expect(result.assignments).to all(satisfy(&:returned?))
    end
  end

  # ------------------------------------------------------------------
  context '貪欲に割り当てると詰むが、増加路探索なら解ける配置' do
    # 余り物の段階で A=2枠 / B=1枠、残った本が A1・A2・B1。
    # B1 を先に B 以外へ渡さないと、A1 と A2 の行き先が無くなる
    let(:participants) { ['A', 'B'] }
    let(:books) { build_books('A' => 2, 'B' => 1) }
    let(:wishes) { {} }
    let(:result) { run_matching(participants: participants, books: books, wishes: wishes, seed: 31_337) }

    it_behaves_like 'マッチングの不変条件を満たす'

    it '返却は理論上の最小である1冊に収まる' do
      returned = result.assignments.select(&:returned?)

      expect(returned.size).to eq(1)
      expect(returned.first.participant_id).to eq('A')
    end
  end

  # ------------------------------------------------------------------
  describe '再現性' do
    let(:participants) { ['A', 'B', 'C', 'D'] }
    let(:books) { build_books('A' => 2, 'B' => 3, 'C' => 1, 'D' => 2) }
    let(:wishes) do
      {
        'A' => ['B1', 'B2', 'C1', 'D1', 'D2', 'B3'],
        'B' => ['A1', 'C1', 'D1', 'A2', 'D2'],
        'C' => ['A1', 'B1', 'D1'],
        'D' => ['B1', 'A1', 'C1', 'B2', 'A2'],
      }
    end

    def assignments_for(seed)
      run_matching(participants: participants, books: books, wishes: wishes, seed: seed)
        .assignments.map(&:to_a)
    end

    it '同じ seed なら結果が完全に一致する' do
      # 左右が同じ式なのは意図的。同じ seed で2回実行し、結果が毎回同じであることを確かめている
      expect(assignments_for(2024)).to eq(assignments_for(2024)) # rubocop:disable RSpec/IdenticalEqualityAssertion
    end

    it '異なる seed なら結果が変わる' do
      expect(assignments_for(2024)).not_to eq(assignments_for(2025))
    end
  end

  # ------------------------------------------------------------------
  describe 'ランダム入力による総当たり' do
    it '1000件すべてで不変条件を満たす' do
      violations = []

      1000.times do
        participants = Array.new(rand(1..7)) { |i| "P#{i}" }
        books = build_books(participants.index_with { |_p| rand(0..4) })
        next if books.empty?

        book_ids = books.map(&:id)
        wishes = participants.index_with { |_p| book_ids.select { rand < 0.6 }.shuffle }

        result = run_matching(
          participants: participants, books: books, wishes: wishes, seed: rand(1_000_000_000)
        )

        owner_of = books.to_h { |book| [book.id, book.owner_id] }
        counts = result.assignments.group_by(&:book_id).transform_values(&:size)
        taken = result.assignments.group_by(&:participant_id).transform_values(&:size)

        violations << '本の重複または欠落' unless book_ids.all? { |id| counts[id] == 1 }
        violations << '取得数が枠と不一致' unless participants.all? { |p| taken.fetch(p, 0) == result.quotas[p] }
        violations << '自分の本を受け取っている' unless result.assignments.all? do |a|
          a.returned? ? a.participant_id == owner_of[a.book_id] : a.participant_id != owner_of[a.book_id]
        end
      end

      expect(violations.uniq).to be_empty
    end
  end
end
