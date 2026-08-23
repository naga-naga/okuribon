# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ギフトコードの伏せ字' do
  let!(:participation) { create(:participation, exchange: create(:exchange, :registration)) }
  let!(:book) { create(:book, participation:, gift_code: 'MYOWNGIFTCODE') }

  before do
    log_in_as(participation.user)
    visit edit_exchange_book_path(book.exchange, book)
  end

  it '既定では伏せ字で、押すと開く' do
    expect(page).to have_css('[data-reveal-target="field"][type="password"]')

    reveal_button.click

    expect(page).to have_css('[data-reveal-target="field"][type="text"]')
    expect(page).to have_css('[data-reveal-target="warning"]')
    expect(reveal_button).to have_text('隠す')
  end

  it 'もう一度押すと伏せ字に戻る' do
    reveal_button.click
    # 開かないまま2回押しても、伏せ字のままで通ってしまう
    expect(page).to have_css('[data-reveal-target="field"][type="text"]')

    reveal_button.click

    expect(page).to have_css('[data-reveal-target="field"][type="password"]')
    expect(page).to have_no_css('[data-reveal-target="warning"]')
  end

  it '開いたまま放置すると、自ら伏せ字へ戻る' do
    revert_after(:reveal, 300)

    reveal_button.click

    expect(page).to have_css('[data-reveal-target="field"][type="text"]')
    expect(page).to have_css('[data-reveal-target="field"][type="password"]')
  end

  def reveal_button
    find('[data-reveal-target="button"]')
  end
end
