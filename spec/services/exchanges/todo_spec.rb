# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exchanges::Todo do
  # フェーズの境目を突くので、基準時刻を1つ決めて全体で回す
  let!(:at) { Time.zone.parse('2026-02-10 12:00') }
  let!(:exchange) do
    create(:exchange,
           registration_starts_at: Time.zone.parse('2026-02-01 00:00'),
           registration_ends_at: Time.zone.parse('2026-02-14 23:59'),
           wish_ends_at: Time.zone.parse('2026-02-21 23:59'))
  end
  let!(:participation) { exchange.participations.find_by!(user: exchange.owner) }

  def todo(now = at)
    described_class.new(participation, at: now).call
  end

  describe '準備中' do
    let!(:at) { Time.zone.parse('2026-01-27 12:00') }

    it '待つだけであることと、登録期間の開始日時を出す' do
      expect(todo).to have_attributes(headline: 'いまは待つだけです', tone: :normal)
      expect(todo.detail).to include('2026年2月1日 00:00')
    end
  end

  describe '登録期間' do
    it '1冊も登録していない人には、受け取る権利が無いことを伝える' do
      expect(todo).to have_attributes(headline: '本を登録する', tone: :urgent)
      expect(todo.detail).to include('0冊')
    end

    it '登録済みの人には冊数を出し、切迫させない' do
      create_list(:book, 2, participation:)

      expect(todo).to have_attributes(headline: '本を登録する', tone: :normal)
      expect(todo.detail).to include('2冊')
    end
  end

  describe '希望提出期間' do
    let!(:at) { Time.zone.parse('2026-02-17 12:00') }

    # 取得枠は登録した冊数で決まる。希望を出す意味があるのは1冊以上登録した人だけ
    before { create_list(:book, 2, participation:) }

    it '希望リストが空なら、そのままだとランダムに割り当てられることを伝える' do
      expect(todo).to have_attributes(headline: '希望リストを作る', tone: :urgent)
      expect(todo.detail).to include('まだ空')
    end

    it '希望を出していれば冊数を出し、切迫させない' do
      create_list(:wish, 3, participation:, exchange:)

      expect(todo).to have_attributes(headline: '希望リストを整える', tone: :normal)
      expect(todo.detail).to include('3冊')
    end

    # 希望提出期間に入った時点で登録期間は終わっており、取得枠を増やす道が残っていない。
    # 促しても果たせないので、受け取れないことだけを伝える
    it '取得枠が0の人には希望リストを促さない' do
      participation.books.destroy_all

      expect(todo).to have_attributes(headline: '今回は本を受け取れません', tone: :normal)
    end
  end

  # ここだけは、すべきことが主催者かどうかでも変わる。実行の導線を持つのは主催者だけで、
  # ほかの参加者に待つ以外の道が無いのは、その人が押していないため
  describe 'マッチング実行待ち' do
    let!(:at) { Time.zone.parse('2026-02-25 12:00') }

    it '主催者にはマッチングの実行を出す' do
      expect(todo).to have_attributes(headline: 'マッチングを実行する', tone: :normal)
      expect(todo.detail).to include('結果を見られません')
    end

    context '主催者以外の参加者' do
      let!(:participation) { create(:participation, exchange:, user: create(:user)) }

      it '待つだけであることと、希望提出の締切を出す' do
        expect(todo).to have_attributes(headline: '結果を待ちます', tone: :normal)
        expect(todo.detail).to include('2026年2月21日 23:59')
      end
    end
  end

  describe '結果公開' do
    let!(:at) { Time.zone.parse('2026-02-25 12:00') }
    let!(:giver) { create(:participation, exchange:, user: create(:user, display_name: 'ゆうと')) }

    before { exchange.update!(matched_at: Time.zone.parse('2026-02-22 21:04')) }

    it '受け取った冊数と贈り主の名前を出す' do
      create(:assignment, participation:, book: create(:book, participation: giver))

      expect(todo).to have_attributes(headline: 'あなたに1冊届いています', tone: :done)
      expect(todo.detail).to include('ゆうと')
    end

    # 返却は誰にも渡せなかった本が登録者へ戻ることで、受け取りには数えない
    it '返却された自分の本は受け取りに数えない' do
      create(:assignment, participation:, book: create(:book, participation:), returned: true)

      expect(todo.headline).to eq('受け取った本はありません')
    end

    it '1冊も登録しなかった人には、受け取れない理由を出す' do
      expect(todo).to have_attributes(headline: '受け取った本はありません', tone: :done)
      expect(todo.detail).to include('登録')
    end
  end
end
