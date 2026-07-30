# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User do
  it '必須のカラムに nil を保存できない' do
    [:provider, :uid, :display_name].each do |column|
      expect { create(:user, column => nil) }
        .to raise_error(ActiveRecord::NotNullViolation), "#{column} が NOT NULL になっていない"
    end
  end

  it 'アバター画像は無くてもよい' do
    expect { create(:user, avatar_url: nil) }.not_to raise_error
  end

  it '同じプロバイダと uid の組では二重に作れない' do
    create(:user, provider: 'github', uid: '1')

    expect { create(:user, provider: 'github', uid: '1') }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it '別のプロバイダなら同じ uid を使える' do
    create(:user, provider: 'github', uid: '1')

    expect { create(:user, provider: 'google', uid: '1') }.not_to raise_error
  end
end
