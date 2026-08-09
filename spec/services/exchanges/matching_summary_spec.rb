# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exchanges::MatchingSummary do
  let!(:exchange) { create(:exchange) }
  # 主催者の参加は factory が作る
  let!(:owner_participation) { exchange.participations.find_by!(user: exchange.owner) }

  def join
    create(:participation, exchange:, user: create(:user))
  end

  # 冊数と希望冊数は SQL で数える。冊数だけが要る場に Book を読み込むと、
  # 暗号化されたギフトコードまで運ばれてくる
  def summary
    described_class.new(exchange.participations.with_counts).call
  end

  def register(participation, count)
    create_list(:book, count, participation:)
  end

  def wish(participation, books)
    books.each_with_index { |book, index| create(:wish, participation:, book:, position: index + 1) }
  end

  # 割当に加わるのは本を登録した人だけ。1冊も登録していない人は取得枠が0で、
  # 何も受け取らない（docs/spec.md 6.9）。主催者に人数を数え直させない
  it '本を登録した人数と、登録された総冊数を数える' do
    register(owner_participation, 2)
    register(join, 1)
    join

    expect(summary).to have_attributes(target_count: 2, books_count: 3)
  end

  it '1冊も登録していない人は対象に数えない' do
    join
    join

    expect(summary).to have_attributes(target_count: 0, books_count: 0)
  end

  # 希望を出していない人にも余り物が回る。実行しても締め出されないことを
  # 主催者が確かめられるよう、人数だけを出す。何を希望したかは出さない（docs/spec.md 8.）
  it '本を登録したのに希望を出していない人数を数える' do
    books = register(owner_participation, 2)
    wisher = join
    register(wisher, 1)
    wish(wisher, books)
    register(join, 1)

    expect(summary.unsubmitted_count).to eq(2)
  end

  # 取得枠が0なら希望を出しようがない。未提出に数えると、
  # 主催者が声を掛けても何も変わらない相手を追うことになる
  it '1冊も登録していない人は未提出に数えない' do
    register(owner_participation, 1)
    join

    expect(summary.unsubmitted_count).to eq(1)
  end

  # 自分が登録した本は受け取れないので（docs/spec.md 3.）、1人の登録冊数が
  # ほかの全員の合計を超えた分は渡す相手がいない
  it '受け取り手のない本の冊数を出す' do
    register(owner_participation, 5)
    register(join, 1)
    register(join, 1)

    expect(summary.returning_count).to eq(3)
  end

  # 偏りが無ければ返却の見込みは無い。nil ではなく0を返して、
  # 表に並べる呼ぶ側に「出るか出ないか」の分岐を書かせない
  it '冊数が釣り合っていれば0冊とする' do
    register(owner_participation, 1)
    register(join, 1)

    expect(summary.returning_count).to eq(0)
  end

  # 作った直後の交換会。参加者は主催者ひとりで本も無い。
  # 確認画面はどのフェーズでも組み立てられる必要がある
  it '参加者が主催者ひとりで本も無ければ、すべて0になる' do
    expect(summary).to have_attributes(target_count: 0, books_count: 0,
                                       unsubmitted_count: 0, returning_count: 0)
  end
end
