# frozen_string_literal: true

require 'rails_helper'

# 初期化ファイルは起動時に1回しか走らないので、環境ごとの分岐は Rails.env を
# 差し替えて読み直すしかない。書き換えるのは本物の経路の設定なので、例のあとで戻す
RSpec.describe 'リンクのホストの設定' do
  around do |example|
    original_options = Rails.application.routes.default_url_options
    original_host = ENV.fetch('APP_HOST', nil)

    example.run
  ensure
    Rails.application.routes.default_url_options = original_options
    ENV['APP_HOST'] = original_host
  end

  def options_in(environment, app_host: nil)
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new(environment))
    ENV['APP_HOST'] = app_host

    load Rails.root.join('config/initializers/default_url_options.rb').to_s
    Rails.application.routes.default_url_options
  end

  it '本番では APP_HOST から採る' do
    expect(options_in('production', app_host: 'okuribon.example.com'))
      .to eq(host: 'okuribon.example.com', protocol: 'https')
  end

  it 'staging でも APP_HOST から採る' do
    expect(options_in('staging', app_host: 'staging.okuribon.example.com'))
      .to eq(host: 'staging.okuribon.example.com', protocol: 'https')
  end

  it '手元では localhost を指す' do
    expect(options_in('development')).to eq(host: 'localhost', port: 3000)
  end

  it 'APP_HOST が無くても読み込みは通る' do
    expect(options_in('production')).to eq(host: nil, protocol: 'https')
  end
end
