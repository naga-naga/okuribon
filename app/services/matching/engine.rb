# frozen_string_literal: true

module Matching
  Book = Struct.new(:id, :owner_id, keyword_init: true)

  # round が nil のものは余り物の割当。returned が true なら出品者への返却
  Assignment = Struct.new(:book_id, :participant_id, :round, :returned, keyword_init: true) do
    def returned? = returned
    def from_draft? = !round.nil?
  end

  Result = Struct.new(:assignments, :quotas, :draft_order, keyword_init: true)

  # レコードに依存せず、識別子だけで完結する処理として書いてある。
  # 呼び出し側でレコードを Book 構造体へ詰め替え、戻り値を保存すること。
  #
  #   Matching::Engine.new(
  #     participants: ['alice', 'bob'],
  #     books:        [Matching::Book.new(id: 1, owner_id: 'alice')],
  #     wishes:       { 'bob' => [1] },
  #     seed:         exchange.random_seed
  #   ).call
  class Engine
    # @param participants [Array<Object>] 参加者の識別子
    # @param books [Array<Book>]
    # @param wishes [Hash{Object => Array<Object>}] 参加者 => 希望順に並んだ本の識別子
    # @param seed [Integer] 交換会に固定された乱数シード
    def initialize(participants:, books:, wishes:, seed:)
      @participants = participants
      @books = books
      @wishes = wishes
      @seed = seed
    end

    # @return [Result]
    def call
      @rng = Random.new(@seed)
      @owner_of = @books.to_h { |book| [book.id, book.owner_id] }
      @quotas = build_quotas
      @taken = @participants.index_with(0)
      @assigned_book_ids = Set.new
      @assignments = []

      draft_order = shuffle(@participants)
      run_draft(draft_order)
      assign_leftovers

      Result.new(assignments: @assignments, quotas: @quotas, draft_order:)
    end

    private

    def build_quotas
      quotas = @participants.index_with(0)
      @books.each { |book| quotas[book.owner_id] = quotas.fetch(book.owner_id, 0) + 1 }
      quotas
    end

    # Array#shuffle の内部実装は仕様として保証されていないため、
    # 再現性を担保するために Fisher-Yates を自前で持つ
    def shuffle(items)
      result = items.dup
      (result.size - 1).downto(1) do |i|
        j = @rng.rand(i + 1)
        result[i], result[j] = result[j], result[i]
      end
      result
    end

    # 奇数巡は順方向、偶数巡は逆方向。誰も本を取れなくなったら終了する
    def run_draft(draft_order)
      round = 0

      loop do
        round += 1
        order = round.odd? ? draft_order : draft_order.reverse
        progressed = false

        order.each do |participant|
          next if @taken[participant] >= @quotas[participant]

          pick = pick_for(participant)
          next if pick.nil?

          @assigned_book_ids << pick
          @taken[participant] += 1
          @assignments << Matching::Assignment.new(
            book_id: pick, participant_id: participant, round:, returned: false
          )
          progressed = true
        end

        break unless progressed
      end
    end

    def pick_for(participant)
      @wishes.fetch(participant, []).find do |book_id|
        @assigned_book_ids.exclude?(book_id) &&
          @owner_of.key?(book_id) &&
          @owner_of[book_id] != participant
      end
    end

    # 空き枠と残った本を、二部グラフの最大マッチングとして解く。
    # 貪欲に割り当てると、避けられたはずの返却が発生してしまう。
    def assign_leftovers
      @slots = @participants.flat_map do |participant|
        Array.new(@quotas[participant] - @taken[participant], participant)
      end
      @remaining = shuffle(@books.reject { |book| @assigned_book_ids.include?(book.id) })
      @slot_order = shuffle((0...@slots.size).to_a)
      @slot_to_book = Array.new(@slots.size, nil)

      @remaining.each_index { |book_index| try_assign?(book_index, Set.new) }

      matched = Set.new
      @slot_to_book.each_with_index do |book_index, slot_index|
        next if book_index.nil?

        matched << book_index
        @assignments << Matching::Assignment.new(
          book_id: @remaining[book_index].id,
          participant_id: @slots[slot_index],
          round: nil,
          returned: false
        )
      end

      @remaining.each_with_index do |book, book_index|
        next if matched.include?(book_index)

        @assignments << Matching::Assignment.new(
          book_id: book.id, participant_id: book.owner_id, round: nil, returned: true
        )
      end
    end

    # 増加路探索。行き先が塞がっていたら、
    # すでに割り当てた本を別の枠へ押しやれないかを遡って調べる
    def try_assign?(book_index, visited)
      @slot_order.each do |slot_index|
        next if @slots[slot_index] == @remaining[book_index].owner_id
        next if visited.include?(slot_index)

        visited << slot_index

        if @slot_to_book[slot_index].nil? || try_assign?(@slot_to_book[slot_index], visited)
          @slot_to_book[slot_index] = book_index
          return true
        end
      end

      false
    end
  end
end
