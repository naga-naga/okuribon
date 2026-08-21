# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exchanges::BookImbalance do
  let!(:exchange) { create(:exchange, owner: create(:user, display_name: 'みずき')) }
  # 主催者の参加は factory が作る。1冊も登録していないので、どの数え方にも効かない
  let!(:owner_participation) { exchange.participations.find_by!(user: exchange.owner) }

  # 偏りは登録冊数の並びだけで決まる。本の中身も希望リストもここには要らない
  def register(display_name, count)
    participation = create(:participation, exchange:, user: create(:user, display_name:))
    create_list(:book, count, participation:) if count.positive?
    participation
  end

  # 主催者管理画面が渡すのと同じ形で渡す
  def imbalance
    described_class.new(exchange.participations.with_counts.includes(:user)).call
  end

  # 自分が登録した本は受け取れないので、1人の登録冊数が
  # ほかの全員の合計を超えた分は、渡す相手がいない
  context '1人の登録冊数がほかの全員の合計を超えるとき' do
    before do
      register('りく', 5)
      register('ゆうと', 1)
      register('はるか', 1)
    end

    it '超えた分の冊数を返す' do
      expect(imbalance.returning_count).to eq(3)
    end

    it '最も多く登録した参加を返す' do
      expect(imbalance.participation.user.display_name).to eq('りく')
    end

    # 「あと何冊登録してもらえば収まるか」を主催者が数えられるようにする
    it 'ほかの全員の合計冊数も返す' do
      expect(imbalance.others_count).to eq(2)
    end
  end

  # ガイドの 03 が描く構成。りくの5冊はほかの5人がちょうど受け取り、
  # ほかの5人はりくの5冊から1冊ずつ受け取れるので、余る本は出ない
  it '最多の人の冊数がほかの全員の合計と釣り合っていれば nil を返す' do
    register('りく', 5)
    5.times { |i| register("ほか#{i}", 1) }

    expect(imbalance).to be_nil
  end

  it '最多の人の冊数がほかの全員の合計を下回れば nil を返す' do
    register('りく', 2)
    register('ゆうと', 2)
    register('はるか', 2)

    expect(imbalance).to be_nil
  end

  it '誰も本を登録していなければ nil を返す' do
    register('ゆうと', 0)

    expect(imbalance).to be_nil
  end

  # 参加者が自分ひとりの交換会。受け取り手が誰もいないので、
  # 登録した全冊が登録者へ返る
  it '参加者がひとりだけなら、その人の全冊が返る' do
    create_list(:book, 3, participation: owner_participation)

    expect(imbalance.returning_count).to eq(3)
    expect(imbalance.participation).to eq(owner_participation)
  end

  it '参加が1件も無ければ nil を返す' do
    expect(described_class.new(Participation.none).call).to be_nil
  end
end
