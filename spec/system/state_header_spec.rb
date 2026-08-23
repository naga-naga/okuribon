# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '状態ヘッダーの畳んだ帯' do
  let!(:exchange) { create(:exchange, :registration) }
  let!(:participation) { create(:participation, exchange:) }

  # 10冊置くのは、状態ヘッダーが画面の上へ抜けるところまで送れる高さを作るため
  before do
    create_list(:book, 10, participation: create(:participation, exchange:))

    log_in_as(participation.user)
    visit exchange_path(exchange)
  end

  it '状態ヘッダーが上へ出ると帯が出る' do
    expect(page).to have_no_css(bar)

    page.scroll_to(:bottom)

    expect(page).to have_css(bar)
  end

  it '状態ヘッダーまで戻ると帯が消える' do
    page.scroll_to(:bottom)
    expect(page).to have_css(bar)

    page.scroll_to(:top)

    expect(page).to have_no_css(bar)
  end

  def bar
    '[data-state-header-target="bar"]'
  end
end
