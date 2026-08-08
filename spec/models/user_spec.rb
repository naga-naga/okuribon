# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User do
  it '必須のカラムが無ければ保存できない' do
    [:provider, :uid, :display_name].each do |column|
      expect(build(:user, column => nil)).not_to be_valid, "#{column} が検証されていない"
    end
  end

  # バリデーションを迂回しても DB が弾く
  it '必須のカラムに nil を書き込めない' do
    [:provider, :uid, :display_name].each do |column|
      expect { build(:user, column => nil).save(validate: false) }
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

  describe '#exchanges' do
    it '参加している交換会を引く' do
      user = create(:user)
      joined = create(:participation, user:).exchange

      expect(user.exchanges).to contain_exactly(joined)
    end

    # 招待されていない交換会が一覧に漏れると、名前と日程だけで実在が知れてしまう
    it '参加していない交換会は引かない' do
      user = create(:user)
      create(:exchange)

      expect(user.exchanges).to be_empty
    end

    # 主催者は必ず参加者を兼ねるので、主催した交換会もここから引ける。
    # 一覧に並ぶ条件はあくまで参加していることで、主催であることではない
    it '主催した交換会も引く' do
      user = create(:user)
      owned = create(:exchange, owner: user)

      expect(user.exchanges).to contain_exactly(owned)
    end
  end

  describe '.from_omniauth' do
    def auth_hash(uid: '100000000000000000001', name: '贈本 太郎', image: 'https://example.com/a.png')
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
        avatar_url: 'https://example.com/a.png'
      )
    end

    # 表示名は本人が入力するもの。名前欄を空で出しても埋めようがないので、
    # 初回に限りプロバイダの名前を初期値として借りる
    it '初回はプロバイダの名前を表示名の初期値にする' do
      user = described_class.from_omniauth(auth_hash)

      expect(user.display_name).to eq('贈本 太郎')
    end

    # 同じ人が再ログインするたびに増えていくと、参加も本も分かれてしまう
    it '2回目以降は同じ利用者に紐づく' do
      first = described_class.from_omniauth(auth_hash)
      second = described_class.from_omniauth(auth_hash)

      expect(second.id).to eq(first.id)
      expect(described_class.count).to eq(1)
    end

    # 本人が変えた表示名をログインのたびに巻き戻してしまう
    it '2回目以降は表示名を上書きしない' do
      user = described_class.from_omniauth(auth_hash)
      user.update!(display_name: 'おくり本の人')

      described_class.from_omniauth(auth_hash(name: '贈本 花子'))

      expect(user.reload.display_name).to eq('おくり本の人')
    end

    # アバターは仕様上プロバイダが返す URL をそのまま持つ。本人の持ち物ではない
    it '2回目以降もアバターはプロバイダに追従する' do
      user = described_class.from_omniauth(auth_hash)

      described_class.from_omniauth(auth_hash(image: 'https://example.com/b.png'))

      expect(user.reload.avatar_url).to eq('https://example.com/b.png')
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
    expect(Participation.exists?(participation.id)).to be(false)
  end
end
