# frozen_string_literal: true

require 'rails_helper'

# ギフトコードは一度漏れたら取り消せない。フォームから送られた値が
# 平文のままログに残らないよう、フィルタの対象であることを固定しておく。
RSpec.describe 'ログのパラメータフィルタ' do
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  it 'ギフトコードをログに残さない' do
    filtered = filter.filter('book' => { 'gift_code' => 'ABCD-1234' })

    expect(filtered['book']['gift_code']).not_to eq('ABCD-1234')
  end

  it '招待トークンをログに残さない' do
    filtered = filter.filter('invite_token' => 'secret-token')

    expect(filtered['invite_token']).not_to eq('secret-token')
  end
end
