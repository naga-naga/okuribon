# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'おすすめポイントの字数' do
  let!(:participation) { create(:participation, exchange: create(:exchange, :registration)) }

  before do
    log_in_as(participation.user)
    visit new_exchange_book_path(participation.exchange)
  end

  it '入力した文字数が出る' do
    expect(page).to have_css('[data-counter-target="output"]', exact_text: '0')

    fill_in 'book_recommendation', with: '波を数えるだけの話'

    expect(page).to have_css('[data-counter-target="output"]', exact_text: '9')
  end
end
