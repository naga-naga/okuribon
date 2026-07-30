# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exchange do
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

  # フェーズは日時から導出する。状態カラムを足すと二重管理になり、
  # 日時とフェーズが食い違う余地が生まれる
  it 'フェーズを表す状態カラムを持たない' do
    expect(described_class.column_names)
      .not_to include('phase', 'state', 'status', 'aasm_state')
  end
end
