# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '招待URLのコピー' do
  let!(:exchange) { create(:exchange, :registration) }

  before do
    log_in_as(exchange.owner)
    visit exchange_management_path(exchange)
  end

  it '押すと入力欄がまるごと選ばれる' do
    copy_button.click

    expect(selection).to eq(source_field.value)
  end

  it '押したことがボタンの文字に出て、しばらくすると戻る' do
    revert_after(:clipboard, 300)

    copy_button.click

    expect(copy_button).to have_text('コピーしました')
    expect(page).to have_css('[data-clipboard-target="button"]', exact_text: 'コピー')
  end

  # 選ばれた範囲は画面から読めない。焦点が外れていれば、
  # 選ばれていても利用者の手ではコピーできない
  def selection
    source_field.evaluate_script(
      'document.activeElement === this ? this.value.slice(this.selectionStart, this.selectionEnd) : ""'
    )
  end

  def source_field
    find('[data-clipboard-target="source"]')
  end

  def copy_button
    find('[data-clipboard-target="button"]')
  end
end
