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

  # ユーザーを消したときに交換会ごと消えるのは事故なので、削除を拒む側に倒してある
  it '主催している交換会があれば消せない' do
    exchange = create(:exchange)
    owner = exchange.owner

    expect(owner.destroy).to be(false)
    expect(owner.errors[:base]).to be_present
    expect(exchange.reload).to be_persisted
  end

  it '主催している交換会が無ければ参加ごと消える' do
    participation = create(:participation)
    user = participation.user

    user.destroy

    expect(described_class.exists?(user.id)).to be(false)
    expect(Participation.count).to eq(0)
  end
end
