# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Assignment do
  it 'ファクトリから作れる' do
    assignment = create(:assignment)

    expect(assignment).to be_persisted
    expect(assignment.returned).to be(false)
  end

  it '本と受取人を往復できる' do
    exchange = create(:exchange)
    book = create(:book, participation: create(:participation, exchange:))
    recipient = create(:participation, exchange:)

    assignment = create(:assignment, book:, participation: recipient)

    expect(assignment.book).to eq(book)
    expect(assignment.participation).to eq(recipient)
    expect(book.assignment).to eq(assignment)
    expect(recipient.assignments).to contain_exactly(assignment)
  end

  it '1冊の本に割当は1つしか作れない' do
    assignment = create(:assignment)
    other = create(:participation, exchange: assignment.book.exchange)

    expect { create(:assignment, book: assignment.book, participation: other) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  # Matching::Engine は余り物の割当を round: nil で返す
  it '余り物の割当は巡を持たない' do
    assignment = create(:assignment, round: nil)

    expect(assignment).to be_persisted
    expect(assignment.round).to be_nil
  end

  it '返却された本は登録者自身への割当になる' do
    book = create(:book)

    assignment = create(:assignment, book:, participation: book.participation, round: nil, returned: true)

    expect(assignment.returned).to be(true)
    expect(assignment.participation).to eq(book.participation)
  end
end
