# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wish do
  it '順位が無ければ保存できない' do
    expect(build(:wish, position: nil)).not_to be_valid
  end

  # 保存前の参加と本は id を持たない。nil どうしを突き合わせると、
  # 別々に作ったものが同じ参加の、同じ交換会のものに見える
  it '保存されていない参加と本で組んでも、自分の本とは見なさない' do
    expect(build(:wish)).to be_valid
  end

  # ここで確かめたいのは DB 側の制約なのでバリデーションを飛ばす。
  # 保存済みのものを書き換えるのは、参加と本の欠落を先に踏まないため
  it '順位に nil を書き込めない' do
    wish = create(:wish)
    wish.position = nil

    expect { wish.save(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
  end

  it '参加者と本のどちらが欠けても保存できない' do
    expect { build(:wish, participation: nil).save(validate: false) }
      .to raise_error(ActiveRecord::NotNullViolation)
    expect { build(:wish, book: nil).save(validate: false) }
      .to raise_error(ActiveRecord::NotNullViolation)
  end

  it '参加者と本を往復できる' do
    exchange = create(:exchange)
    book = create(:book, participation: create(:participation, exchange:))
    participation = create(:participation, exchange:)

    wish = create(:wish, participation:, book:)

    expect(wish.participation).to eq(participation)
    expect(wish.book).to eq(book)
    expect(participation.wishes).to contain_exactly(wish)
    expect(book.wishes).to contain_exactly(wish)
  end

  it '同じ参加者が同じ本を二重に希望できない' do
    wish = create(:wish)

    expect { create(:wish, participation: wish.participation, book: wish.book) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it '別の参加者は同じ本を希望できる' do
    wish = create(:wish)
    other = create(:participation, exchange: wish.book.exchange)

    expect { create(:wish, participation: other, book: wish.book) }.not_to raise_error
  end

  # 希望に入れられると、選んだのに絶対に当たらない枠を1つ抱えることになる
  it '自分が登録した本は希望できない' do
    participation = create(:participation)
    book = create(:book, participation:)

    wish = build(:wish, participation:, book:)

    expect(wish).not_to be_valid
    expect(wish.errors).to be_of_kind(:book, :own_book)
  end

  it '別の交換会の本は希望できない' do
    wish = build(:wish, participation: create(:participation), book: create(:book))

    expect(wish).not_to be_valid
    expect(wish.errors).to be_of_kind(:book, :other_exchange)
  end

  # 順位が重複すると order(:position) の並びが不定になり、
  # 乱数シードを固定してもマッチングの結果を再現できなくなる。
  # 制約は遅延させてあるので、検査を今ここで起こして確かめる
  it '同じ参加者の中で順位が重複できない' do
    wish = create(:wish, position: 1)
    create(:wish, participation: wish.participation, position: 1)

    expect { ActiveRecord::Base.connection.execute('SET CONSTRAINTS ALL IMMEDIATE') }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  # 並べ替えは順位を1つずつ書き換えるので、途中で必ず重複が生まれる。
  # 即時に検査する制約だと、退避用の値を経由するような書き方を強いられる
  it '並べ替えの途中で順位が重複しても、元に戻せば通る' do
    first = create(:wish, position: 1)
    second = create(:wish, participation: first.participation, position: 2)

    first.update!(position: 2)
    second.update!(position: 1)

    expect { ActiveRecord::Base.connection.execute('SET CONSTRAINTS ALL IMMEDIATE') }
      .not_to raise_error
  end
end
