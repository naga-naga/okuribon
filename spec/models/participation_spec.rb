# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Participation do
  # 交換会も参加者も belongs_to の既定で必須になるが、
  # ここで確かめたいのは DB 側の制約なのでバリデーションを飛ばす
  it '交換会と参加者のどちらが欠けても保存できない' do
    expect { build(:participation, exchange: nil).save(validate: false) }
      .to raise_error(ActiveRecord::NotNullViolation)
    expect { build(:participation, user: nil).save(validate: false) }
      .to raise_error(ActiveRecord::NotNullViolation)
  end

  it '交換会と参加者を往復できる' do
    exchange = create(:exchange)
    user = create(:user)
    participation = create(:participation, exchange:, user:)

    expect(participation.exchange).to eq(exchange)
    expect(participation.user).to eq(user)
    expect(exchange.participations).to contain_exactly(participation)
    expect(user.participations).to contain_exactly(participation)
  end

  it '同じ参加者が同じ交換会に二重に参加できない' do
    participation = create(:participation)

    expect { create(:participation, exchange: participation.exchange, user: participation.user) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it '同じ参加者が別の交換会には参加できる' do
    user = create(:user)
    create(:participation, user:)

    expect { create(:participation, user:) }.not_to raise_error
  end

  it '主催者は自分の交換会に参加者として加われる' do
    exchange = create(:exchange)

    participation = create(:participation, exchange:, user: exchange.owner)

    expect(exchange.participations).to contain_exactly(participation)
  end
end
