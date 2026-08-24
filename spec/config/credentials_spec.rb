# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'credentials の置き場' do
  it '本番とステージングがそれぞれのファイルを持つ' do
    expect(Rails.root.join('config/credentials/production.yml.enc')).to exist
    expect(Rails.root.join('config/credentials/staging.yml.enc')).to exist
  end

  # 鍵を追跡しているかは .gitignore にしか書かれておらず、Ruby からは読めない。
  # 判定そのものを git に聞く
  it '鍵を追跡しない' do
    paths = [
      'config/master.key',
      'config/credentials/production.key',
      'config/credentials/staging.key',
    ]

    ignored = paths.select { |path| system('git', 'check-ignore', '--quiet', path) }

    expect(ignored).to match_array(paths)
  end
end
