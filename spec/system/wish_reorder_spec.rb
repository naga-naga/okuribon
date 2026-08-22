# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '希望リストの並べ替え' do
  # 並べ替えが動くのは希望提出期間だけなので、trait はここで指定する
  let!(:exchange) { create(:exchange, :wish) }
  let!(:participation) { create(:participation, exchange:) }
  # 本ごとに登録者を分ける。自分が登録した本は希望に選べない
  let!(:books) do
    ['赤の本', '青の本', '緑の本'].map do |title|
      create(:book, title:, participation: create(:participation, exchange:))
    end
  end

  # 送られた並びは book_ids で届く。画面から読めるのは題なので、突き合わせる側も題に直す
  let!(:sent_orders) { [] }

  before do
    books.each_with_index { |book, index| create(:wish, participation:, book:, position: index + 1) }

    log_in_as(participation.user)
    visit exchange_path(exchange)

    # ハンドルが押せるようになるのは Stimulus が繋がってから。
    # 繋がる前に触ると、どの例も disabled のボタンを相手にすることになる。
    # 説明の hidden が外れるのが同じ connect なので、見えるまで待つ
    find('#wish_reorder_help')
  end

  around do |example|
    orders = sent_orders
    titles = ->(ids) { Book.where(id: ids).index_by(&:id).values_at(*ids.map(&:to_i)).map(&:title) }

    subscription = ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*, payload|
      orders << titles.call(payload[:params].fetch('book_ids')) if payload[:controller] == 'WishListsController'
    end

    example.run
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  it 'ドラッグで動かした並びをサーバーへ送る' do
    saving_wish_list { drag_past_next_row('赤の本') }

    expect(sent_orders).to eq([['青の本', '赤の本', '緑の本']])
  end

  it 'ハンドルにフォーカスして ↑↓ で隣と入れ替えられる' do
    press_handle('緑の本', :up)

    expect_rows('赤の本', '緑の本', '青の本')
  end

  it 'ハンドルにフォーカスして Home / End で端まで送れる' do
    press_handle('緑の本', :home)

    expect_rows('緑の本', '赤の本', '青の本')
  end

  it '動かしたあと、掴んでいたハンドルへフォーカスが戻る' do
    saving_wish_list { press_handle('赤の本', :down) }

    expect_rows('青の本', '赤の本', '緑の本')
    expect(focused_handle_position).to eq(2)
  end

  it '続けて押したぶんを1回にまとめて送る' do
    # 2つを1回の呼び出しで送る。呼び分けると、間が SAVE_DELAY を越えたときに
    # まとまらなかったのか、まとめる仕掛けが壊れたのかを見分けられない
    saving_wish_list { press_handle('赤の本', :down, :down) }

    expect(sent_orders).to eq([['青の本', '緑の本', '赤の本']])
  end

  # 保存の往復は画面に現れない。並びは送る前から動いているので、
  # 動かした並びと返ってきた並びを画面の中身では見分けられない。
  # 差し替わる区画に印を付けて、それが消えるのを待つ
  def saving_wish_list
    page.execute_script("document.getElementById('wish_list').dataset.pending = ''")

    yield

    expect(page).to have_no_css('#wish_list[data-pending]', visible: :all)
  end

  # cuprite の send_keys は要素を先にクリックする。ハンドルの pointerdown はつまむ操作に
  # あたり、preventDefault がフォーカスを止めるので、押したキーが本文へ逃げる。
  # フォーカスを当てるところと、キーを送るところを分ける
  def press_handle(title, *keys)
    page.execute_script("#{handle_script(title)}.focus()")

    page.driver.browser.keyboard.type(*keys)
  end

  # 差し込みは重ねた行の半分を越えたところで起きる。
  # 行の高さは装飾で変わるので、越える距離はその場で測る
  def drag_past_next_row(title)
    distance = page.evaluate_script(<<~JS)
      (() => {
        const rows = [...document.querySelectorAll('[data-wish-reorder-target="row"]')];
        const index = rows.findIndex((row) => row.textContent.includes(#{title.to_json}));
        const from = rows[index].getBoundingClientRect();
        const over = rows[index + 1].getBoundingClientRect();
        return Math.ceil(over.top + over.height / 2 - (from.top + from.height / 2)) + 1;
      })()
    JS

    # Capybara が持つのは要素から要素への drag_to だけで、行の半分を越えるだけの
    # 距離を指せない。距離で動かす drag_by は cuprite の側にあるので base から呼ぶ。
    # scroll: false も cuprite への指定。既定では掴む前に window ごと同じだけ流すので、
    # 掴んだ行と重ねる行の位置関係が、測ったときから変わる
    find('#wish_list li', text: title).find('[data-wish-reorder-target="handle"]')
                                      .base.drag_by(0, distance, steps: 10, scroll: false)
  end

  # 差し替えの途中で読むと行が入れ替わっている最中にあたるため、待てる形で見る
  def expect_rows(*titles)
    titles.each_with_index do |title, index|
      expect(page).to have_css("#wish_list li:nth-child(#{index + 1})", text: title)
    end
  end

  # 掴んでいたハンドルは行と一緒に動くので、戻り先は行の位置で見る。
  # ハンドル以外に focus があれば 0 を返す
  def focused_handle_position
    page.evaluate_script(<<~JS)
      (() => {
        const handles = [...document.querySelectorAll('[data-wish-reorder-target="handle"]')];
        return handles.indexOf(document.activeElement) + 1;
      })()
    JS
  end

  def handle_script(title)
    <<~JS.strip
      [...document.querySelectorAll('[data-wish-reorder-target="handle"]')]
        .find((handle) => handle.closest('li').textContent.includes(#{title.to_json}))
    JS
  end
end
