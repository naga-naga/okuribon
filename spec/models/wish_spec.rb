# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wish do
  it '順位に nil を保存できない' do
    expect { create(:wish, position: nil) }.to raise_error(ActiveRecord::NotNullViolation)
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
end
