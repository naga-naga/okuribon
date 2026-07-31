# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Book do
  it '登録者を往復できる' do
    participation = create(:participation)
    book = create(:book, participation:)

    expect(book.participation).to eq(participation)
    expect(participation.books).to contain_exactly(book)
  end

  it '登録者を経由して交換会を辿れる' do
    book = create(:book)

    expect(book.exchange).to eq(book.participation.exchange)
    expect(book.exchange.books).to contain_exactly(book)
  end

  it 'ひとりで何冊でも登録できる' do
    participation = create(:participation)

    books = create_list(:book, 3, participation:)

    expect(participation.books).to match_array(books)
  end

  it 'あらすじ・URL・おすすめポイントは無くても登録できる' do
    book = create(:book, summary: nil, url: nil, recommendation: nil)

    expect(book).to be_persisted
  end

  it 'タイトルとギフトコードは欠かせない' do
    expect { create(:book, title: nil) }.to raise_error(ActiveRecord::NotNullViolation)
    expect { create(:book, gift_code: nil) }.to raise_error(ActiveRecord::NotNullViolation)
  end

  it '登録者のいない本は保存できない' do
    expect { build(:book, participation: nil).save(validate: false) }
      .to raise_error(ActiveRecord::NotNullViolation)
  end

  it '消すとその本への希望と割当も消える' do
    exchange = create(:exchange)
    book = create(:book, participation: create(:participation, exchange:))
    recipient = create(:participation, exchange:)
    create(:wish, participation: recipient, book:)
    create(:assignment, book:, participation: recipient)

    book.destroy

    expect(Wish.count).to eq(0)
    expect(Assignment.count).to eq(0)
    expect(recipient.reload).to be_persisted
  end
end
