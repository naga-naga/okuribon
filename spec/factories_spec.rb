# frozen_string_literal: true

require 'rails_helper'

# trait の名乗るフェーズがずれると、それを使っている spec が
# 何を確かめているのかを変えたまま通り続ける
RSpec.describe 'exchange factory' do
  it '既定は準備中' do
    expect(create(:exchange).phase(at: Time.current)).to eq(:preparing)
  end

  Exchange::PHASES.each do |phase|
    it "#{phase} の trait はそのフェーズになる" do
      expect(create(:exchange, phase).phase(at: Time.current)).to eq(phase)
    end
  end
end
