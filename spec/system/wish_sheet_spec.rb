# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '希望リストのシート' do
  let!(:exchange) { create(:exchange, :wish) }
  let!(:participation) { create(:participation, exchange:) }

  before do
    create(:wish, participation:, position: 1,
                  book: create(:book, title: '赤の本', participation: create(:participation, exchange:)))

    # 既定の 1400px では一覧の脇に開いたままで、畳むボタンそのものが出ない
    page.current_window.resize_to(390, 780)

    log_in_as(participation.user)
    visit exchange_path(exchange)
  end

  it '狭い画面では畳まれていて、押すと中身が出る' do
    expect(page).to have_no_css('#wish_list li')

    sheet_toggle.click

    expect(page).to have_css('#wish_list li', text: '赤の本')
    expect(sheet_toggle['aria-expanded']).to eq('true')
  end

  it 'もう一度押すと畳まれる' do
    sheet_toggle.click
    expect(page).to have_css('#wish_list li', text: '赤の本')

    sheet_toggle.click

    expect(page).to have_no_css('#wish_list li')
    expect(sheet_toggle['aria-expanded']).to eq('false')
  end

  def sheet_toggle
    find('[data-wish-sheet-target="toggle"]')
  end
end
