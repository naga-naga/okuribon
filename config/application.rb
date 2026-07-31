# frozen_string_literal: true

require_relative 'boot'

require 'rails'
# Pick the frameworks you want:
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_mailbox/engine'
require 'action_text/engine'
require 'action_view/railtie'
require 'action_cable/engine'
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Okuribon
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: ['assets', 'tasks'])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.eager_load_paths << Rails.root.join("extras")

    # 表示・入力はすべて JST で扱う。DB には UTC で保存する
    config.time_zone = 'Tokyo'
    config.active_record.default_timezone = :utc

    # 画面もエラーメッセージも日本語だけを出す。ロケールの切り替えは持たない
    config.i18n.default_locale = :ja

    # Don't generate system test files.
    config.generators.system_tests = nil

    # ジェネレータは RSpec 用のファイルだけを吐く。fixture は使わない
    config.generators do |g|
      g.test_framework :rspec, fixture: false, view_specs: false, helper_specs: false, routing_specs: false
      g.factory_bot dir: 'spec/factories'
    end
  end
end
