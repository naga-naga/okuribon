# frozen_string_literal: true

require 'rails_helper'

# 読まれるのは自分の節だけなので、staging の節の欠落は staging を起動するまで
# 分からない。test 環境からファイルを直接読んで全部の節を見る
RSpec.describe 'staging 環境の設定' do
  def configuration(name)
    YAML.safe_load(ERB.new(Rails.root.join('config', name).read).result, aliases: true)
  end

  it 'RAILS_ENV=staging で読む環境ファイルがある' do
    expect(Rails.root.join('config/environments/staging.rb')).to exist
  end

  describe 'データベース' do
    subject(:database) { configuration('database.yml') }

    it '本番と同じ数の接続先を持つ' do
      expect(database['staging'].keys).to match_array(database['production'].keys)
    end

    it '本番と同じデータベースを指さない' do
      staging = database['staging'].values.pluck('database')
      production = database['production'].values.pluck('database')

      expect(staging & production).to be_empty
    end
  end

  it 'ジョブのワーカーとディスパッチャの構成を持つ' do
    expect(configuration('queue.yml')['staging']).to be_present
  end

  it 'キャッシュの保存先を持つ' do
    expect(configuration('cache.yml')['staging']).to be_present
  end

  it 'Action Cable の接続先を持つ' do
    expect(configuration('cable.yml')['staging']).to be_present
  end

  it '本番と同じ定期実行を持つ' do
    recurring = configuration('recurring.yml')

    expect(recurring['staging']).to eq(recurring['production'])
  end
end
