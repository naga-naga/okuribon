# frozen_string_literal: true

require 'rails_helper'
require 'kamal'

# Kamal が秘密を読むのは配る直前なので、レジストリの認証も手元の鍵も要らずに
# 設定の読み込みと検証まで通せる
RSpec.describe 'Kamal のデプロイ設定' do
  def destinations
    ['production', 'staging']
  end

  def deploy_configuration(destination)
    Kamal::Configuration.create_from(config_file: Rails.root.join('config/deploy.yml'), destination:)
  end

  def web_environment(destination)
    role = deploy_configuration(destination).role(:web)

    role.env(role.hosts.first).clear
  end

  # create_from は KAMAL_DESTINATION を書き込む。ほかの例に持ち越さない
  around do |example|
    original = ENV.fetch('KAMAL_DESTINATION', nil)

    example.run
  ensure
    ENV['KAMAL_DESTINATION'] = original
  end

  it '環境ごとに変わる値を共通の設定に持たない' do
    common = Kamal::Configuration.load_raw_config(config_file: Rails.root.join('config/deploy.yml'))

    expect(common[:servers]).to be_nil
    expect(common[:proxy]).not_to include('host')
    ['RAILS_ENV', 'APP_HOST', 'DB_HOST'].each do |key|
      expect(common.dig(:env, 'clear')).not_to include(key)
    end
  end

  it '環境ごとに RAILS_ENV を渡す' do
    expect(destinations.map { |destination| web_environment(destination)['RAILS_ENV'] })
      .to eq(destinations)
  end

  it '環境ごとに別のドメインで受ける' do
    production, staging = destinations.map { |destination| deploy_configuration(destination).proxy.hosts }

    expect(production & staging).to be_empty
  end

  it 'リンクのホストとプロキシが受けるドメインが揃っている' do
    destinations.each do |destination|
      expect(web_environment(destination)['APP_HOST'])
        .to eq(deploy_configuration(destination).proxy.hosts.sole)
    end
  end

  it 'アプリが自分の環境のデータベースを指す' do
    destinations.each do |destination|
      expect(web_environment(destination)['DB_HOST'])
        .to eq(deploy_configuration(destination).accessory(:db).service_name)
    end
  end

  # 接続は主・キャッシュ・ジョブ・ケーブルの4つある。アンカーを外した接続が
  # 混ざっていないか見るため、値を1つずつではなくまとめて突く
  it 'デプロイした環境の接続先が DB_HOST から決まる' do
    original = ENV.fetch('DB_HOST', nil)
    ENV['DB_HOST'] = 'okuribon-db-production'
    database = YAML.safe_load(ERB.new(Rails.root.join('config/database.yml').read).result, aliases: true)

    destinations.each do |destination|
      expect(database[destination].values.pluck('host')).to all(eq('okuribon-db-production'))
    end
  ensure
    ENV['DB_HOST'] = original
  end

  describe 'コンテナの名前' do
    it 'アプリが環境ごとに分かれる' do
      names = destinations.map { |destination| deploy_configuration(destination).role(:web).container_prefix }

      expect(names.uniq.size).to eq(2)
    end

    it 'データベースが環境ごとに分かれる' do
      names = destinations.map { |destination| deploy_configuration(destination).accessory(:db).service_name }

      expect(names.uniq.size).to eq(2)
    end
  end
end
