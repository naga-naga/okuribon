# frozen_string_literal: true

require 'capybara/cuprite'

module SystemSpecBrowser
  module_function

  # 見つからなければ nil を返し、ferrum に PATH から探させる。
  # Playwright はバージョンごとにディレクトリを分けるため、新しいほうを取る
  def path
    Dir.glob(File.expand_path('~/.cache/ms-playwright/chromium-*/chrome-linux*/chrome')).max
  end
end

module SystemRevertHelper
  # 戻るまでの長さは Stimulus が data 属性から読み直すので、始める前に縮めれば効く。
  # 既定の長さをそのまま待つと、待つぶんだけ実行時間が伸びる
  def revert_after(controller, milliseconds)
    find(%([data-controller~="#{controller}"]))
      .execute_script("this.dataset.#{controller}RevertAfterValue = #{milliseconds}")
  end
end

# 保存は SAVE_DELAY のぶん待ってから送られる。既定の2秒だと、
# 往復のたびに余裕が1秒台しか残らない
Capybara.default_max_wait_time = 5

RSpec.configure do |config|
  config.include SystemRevertHelper, type: :system

  config.before(:each, type: :system) do
    # 希望リストが一覧の右に開くのは lg（1024px）から。狭い画面で走らせると、
    # 希望リストに触るどの spec も、先にシートを開く操作を挟むことになる。
    #
    # dockerize は --no-sandbox を足す。devcontainer も ubuntu-latest も
    # 非特権の user namespace を作れず、Chrome は sandbox を張れないまま落ちる。
    #
    # js_errors は既定で false。既定のままだと、JavaScript が落ちても例は通る
    driven_by :cuprite,
              screen_size: [1400, 1000],
              options: { browser_path: SystemSpecBrowser.path, dockerize: true,
                         js_errors: true, process_timeout: 30 }
  end
end
