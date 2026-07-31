# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exchange do
  # DB の例外にする前にバリデーションで捕まえる。フォームに戻せるのはこちらだけ
  it '必須のカラムに nil を入れるとバリデーションで落ちる' do
    columns = [
      :name, :registration_starts_at, :registration_ends_at,
      :wish_starts_at, :wish_ends_at, :invite_token, :random_seed,
    ]

    columns.each do |column|
      expect { create(:exchange, column => nil) }
        .to raise_error(ActiveRecord::RecordInvalid), "#{column} に presence バリデーションが無い"
    end
  end

  # バリデーションを外れた経路でも空で入らないよう、DB 側の制約も残す
  it '必須のカラムはバリデーションを迂回しても保存できない' do
    columns = [
      :name, :registration_starts_at, :registration_ends_at,
      :wish_starts_at, :wish_ends_at, :invite_token, :random_seed,
    ]

    columns.each do |column|
      expect { build(:exchange, column => nil).save(validate: false) }
        .to raise_error(ActiveRecord::NotNullViolation), "#{column} が NOT NULL になっていない"
    end
  end

  it '主催者のいない交換会は保存できない' do
    expect { build(:exchange, owner: nil).save(validate: false) }
      .to raise_error(ActiveRecord::NotNullViolation)
  end

  it '概要・マッチング実行日時・Webhook URL は無くてもよい' do
    expect { create(:exchange, description: nil, matched_at: nil, webhook_url: nil) }
      .not_to raise_error
  end

  it '主催者を往復できる' do
    owner = create(:user)
    exchange = create(:exchange, owner:)

    expect(exchange.owner).to eq(owner)
    expect(owner.owned_exchanges).to contain_exactly(exchange)
  end

  it '同じ招待トークンでは二重に作れない' do
    create(:exchange, invite_token: 'same-token')

    expect { create(:exchange, invite_token: 'same-token') }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it '消すと参加・本・希望・割当まで連鎖して消える' do
    exchange = create(:exchange)
    owner = create(:participation, exchange:)
    recipient = create(:participation, exchange:)
    book = create(:book, participation: owner)
    create(:wish, participation: recipient, book:)
    create(:assignment, book:, participation: recipient)

    exchange.destroy

    expect(Participation.count).to eq(0)
    expect(Book.count).to eq(0)
    expect(Wish.count).to eq(0)
    expect(Assignment.count).to eq(0)
  end

  # フェーズは日時から導出する。状態カラムを足すと二重管理になり、
  # 日時とフェーズが食い違う余地が生まれる
  it 'フェーズを表す状態カラムを持たない' do
    expect(described_class.column_names)
      .not_to include('phase', 'state', 'status', 'aasm_state')
  end
end
