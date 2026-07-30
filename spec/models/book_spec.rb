# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Book do
  it 'ファクトリから作れる' do
    book = create(:book)

    expect(book).to be_persisted
    expect(book.title).to be_present
    expect(book.gift_code).to be_present
  end

  it '登録者を往復できる' do
    participation = create(:participation)
    book = create(:book, participation: participation)

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

    books = create_list(:book, 3, participation: participation)

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
end
