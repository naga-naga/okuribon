# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '本のカードの開閉' do
  let!(:exchange) { create(:exchange, :registration) }
  let!(:participation) { create(:participation, exchange:) }

  # カードは 768px で止まるので、おすすめポイントの2行は100字あたりで埋まる。
  # あらすじも折られる対象にあたるため、こちらは置かない
  before do
    create(:book, title: '長い本', summary: nil, participation: create(:participation, exchange:),
                  recommendation: '読み終えたあと、しばらく本を閉じたまま座っていました。' * 6)
    create(:book, title: '短い本', summary: nil, participation: create(:participation, exchange:),
                  recommendation: '一息で読めます。')

    log_in_as(participation.user)
    visit exchange_path(exchange)
  end

  it '折られた本文のカードは、押すと開いて閉じられる' do
    card = card('長い本')
    card.find('[data-book-card-target="toggle"]').click

    expect(card).to have_text('閉じる')

    card.find('[data-book-card-target="toggle"]').click

    expect(card).to have_text('続きを読む')
  end

  it '折れていない本文のカードには開くボタンが出ない' do
    # ボタンが出るのは幅を測ってから。待たずに読むと、
    # まだどのカードにも出ていないところを見て通ってしまう
    expect(card('長い本')).to have_css('[data-book-card-target="toggle"]')

    expect(card('短い本')).to have_no_css('[data-book-card-target="toggle"]')
  end

  def card(title)
    find('#book_list li', text: title)
  end
end
