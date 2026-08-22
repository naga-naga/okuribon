# frozen_string_literal: true

require 'rails_helper'

# フォームから送られた値が平文のままログに残らないことを固定する。
RSpec.describe 'ログのパラメータフィルタ' do
  let!(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  it 'ギフトコードをログに残さない' do
    filtered = filter.filter('book' => { 'gift_code' => 'ABCD-1234' })

    expect(filtered['book']['gift_code']).not_to eq('ABCD-1234')
  end

  it '招待トークンをログに残さない' do
    filtered = filter.filter('invite_token' => 'secret-token')

    expect(filtered['invite_token']).not_to eq('secret-token')
  end

  # Webhook URL は交換会の作成・編集フォームから送られる。パスにトークンが載っており、
  # URL を知られた時点で誰でもそのチャンネルへ投稿できる
  it 'Webhook URL をログに残さない' do
    url = 'https://discord.com/api/webhooks/123456789012345678/token'
    filtered = filter.filter('exchange' => { 'webhook_url' => url })

    expect(filtered['exchange']['webhook_url']).not_to eq(url)
  end

  # OAuth のコールバックは認可コードをクエリ文字列で受け取る。
  # 短命で1回しか使えないが、アクセストークンと交換できる資格情報には違いない
  it 'OAuth の認可コードをログに残さない' do
    filtered = filter.filter('code' => '4/0AeanS0abcdef')

    expect(filtered['code']).not_to eq('4/0AeanS0abcdef')
  end
end
