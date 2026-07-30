# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Participation do
  it 'ファクトリから作れる' do
    expect(create(:participation)).to be_persisted
  end

  it '交換会と参加者を往復できる' do
    exchange = create(:exchange)
    user = create(:user)
    participation = create(:participation, exchange: exchange, user: user)

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
    create(:participation, user: user)

    expect { create(:participation, user: user) }.not_to raise_error
  end

  it '主催者は自分の交換会に参加者として加われる' do
    exchange = create(:exchange)

    participation = create(:participation, exchange: exchange, user: exchange.owner)

    expect(exchange.participations).to contain_exactly(participation)
  end
end
