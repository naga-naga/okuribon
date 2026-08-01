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

  describe '.from_omniauth' do
    def auth_hash(uid: '100000000000000000001', name: '送本 太郎', image: 'https://example.com/a.png')
      OmniAuth::AuthHash.new(
        provider: 'google_oauth2',
        uid:,
        info: { name:, image: }
      )
    end

    it 'プロバイダの識別子から利用者を作る' do
      user = described_class.from_omniauth(auth_hash)

      expect(user).to be_persisted
      expect(user).to have_attributes(
        provider: 'google_oauth2',
        uid: '100000000000000000001',
        display_name: '送本 太郎',
        avatar_url: 'https://example.com/a.png'
      )
    end

    # 同じ人が再ログインするたびに増えていくと、参加も本も分かれてしまう
    it '2回目以降は同じ利用者に紐づく' do
      first = described_class.from_omniauth(auth_hash)
      second = described_class.from_omniauth(auth_hash)

      expect(second.id).to eq(first.id)
      expect(described_class.count).to eq(1)
    end

    # プロバイダ側で改名やアイコン変更があったら、こちらも追従する
    it '2回目以降は表示名とアバターを更新する' do
      user = described_class.from_omniauth(auth_hash)

      described_class.from_omniauth(auth_hash(name: '送本 花子', image: 'https://example.com/b.png'))

      expect(user.reload).to have_attributes(
        display_name: '送本 花子',
        avatar_url: 'https://example.com/b.png'
      )
    end

    it 'uid が違えば別の利用者になる' do
      described_class.from_omniauth(auth_hash)
      other = described_class.from_omniauth(auth_hash(uid: '100000000000000000002'))

      expect(described_class.count).to eq(2)
      expect(other.uid).to eq('100000000000000000002')
    end
  end

  it '主催している交換会が無ければ参加ごと消える' do
    participation = create(:participation)
    user = participation.user

    user.destroy

    expect(described_class.exists?(user.id)).to be(false)
    expect(Participation.count).to eq(0)
  end
end
