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

  describe '期間の整合性' do
    it '登録期間のあとに希望提出期間が並んでいれば有効になる' do
      exchange = build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_starts_at: '2026-08-10T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )

      expect(exchange).to be_valid
    end

    # 各期間は開始時刻を含み終了時刻を含まないため、境界が一致していても重ならない
    it '登録期間の終了と希望提出期間の開始が同時刻でも有効になる' do
      exchange = build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_starts_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )

      expect(exchange).to be_valid
    end

    it '登録期間の終了が開始より前だと無効になる' do
      exchange = build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-07-31T00:00:00+09:00'.in_time_zone,
        wish_starts_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )

      expect(exchange).not_to be_valid
      expect(exchange.errors.full_messages)
        .to contain_exactly('登録期間の終了日時は開始日時より後にしてください')
    end

    it '登録期間の開始と終了が同時刻だと無効になる' do
      exchange = build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        wish_starts_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )

      expect(exchange).not_to be_valid
      expect(exchange.errors.full_messages)
        .to contain_exactly('登録期間の終了日時は開始日時より後にしてください')
    end

    it '希望提出期間の終了が開始より前だと無効になる' do
      exchange = build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_starts_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-07T00:00:00+09:00'.in_time_zone
      )

      expect(exchange).not_to be_valid
      expect(exchange.errors.full_messages)
        .to contain_exactly('希望提出期間の終了日時は開始日時より後にしてください')
    end

    it '希望提出期間の開始と終了が同時刻だと無効になる' do
      exchange = build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_starts_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone
      )

      expect(exchange).not_to be_valid
      expect(exchange.errors.full_messages)
        .to contain_exactly('希望提出期間の終了日時は開始日時より後にしてください')
    end

    it '希望提出期間の開始が登録期間の終了より前だと無効になる' do
      exchange = build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_starts_at: '2026-08-07T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )

      expect(exchange).not_to be_valid
      expect(exchange.errors.full_messages)
        .to contain_exactly('希望提出期間の開始日時は登録期間の終了日時以降にしてください')
    end

    it '日時が欠けていても順序のエラーは足さない' do
      exchange = build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: nil,
        wish_starts_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )

      expect(exchange).not_to be_valid
      expect(exchange.errors.full_messages)
        .to contain_exactly('登録期間の終了日時を入力してください')
    end
  end

  describe '招待トークン' do
    it '作成時に自動で入る' do
      exchange = create(:exchange)

      expect(exchange.invite_token).to be_present
    end

    # URL に載るため、総当たりで引ける長さにしない
    it '推測困難な長さを持つ' do
      exchange = create(:exchange)

      expect(exchange.invite_token.length).to be >= 22
    end

    it '交換会ごとに異なる' do
      tokens = Array.new(20) { create(:exchange).invite_token }

      expect(tokens.uniq.size).to eq(20)
    end

    it '明示的に渡した値は上書きしない' do
      exchange = create(:exchange, invite_token: 'given-token')

      expect(exchange.invite_token).to eq('given-token')
    end

    # #37 で主催者が再発行できるようにするため、こちらは変更を許す
    it '作成後に変更できる' do
      exchange = create(:exchange)

      exchange.update!(invite_token: 'regenerated-token')

      expect(exchange.reload.invite_token).to eq('regenerated-token')
    end
  end

  describe '乱数シード' do
    # 与えたシードでマッチングを回し、結果を比較できる形にして返す
    def matching_result_for(seed)
      Matching::Engine.new(
        participants: ['alice', 'bob', 'carol'],
        books: [
          Matching::Book.new(id: 1, owner_id: 'alice'),
          Matching::Book.new(id: 2, owner_id: 'bob'),
          Matching::Book.new(id: 3, owner_id: 'carol'),
        ],
        wishes: { 'alice' => [2, 3], 'bob' => [3, 1], 'carol' => [1, 2] },
        seed:
      ).call.assignments.map { |a| [a.book_id, a.participant_id, a.round, a.returned] }
    end

    it '作成時に自動で入る' do
      exchange = create(:exchange)

      expect(exchange.random_seed).to be_present
    end

    # bigint に収めるため。Random.new_seed は 128bit で入らない
    it '2^62 未満の非負整数になる' do
      seeds = Array.new(20) { create(:exchange).random_seed }

      expect(seeds).to all(be_between(0, (2**62) - 1))
    end

    it '交換会ごとに異なる' do
      seeds = Array.new(20) { create(:exchange).random_seed }

      expect(seeds.uniq.size).to eq(20)
    end

    it '明示的に渡した値は上書きしない' do
      exchange = create(:exchange, random_seed: 12_345)

      expect(exchange.random_seed).to eq(12_345)
    end

    # 結果を作り直せないようにするため、作成後は動かせない
    it '作成後に変更しようとすると例外になる' do
      exchange = create(:exchange)

      expect { exchange.random_seed = 12_345 }
        .to raise_error(ActiveRecord::ReadonlyAttributeError)
    end

    it '作成後に update しようとすると例外になる' do
      exchange = create(:exchange)

      expect { exchange.update!(random_seed: 12_345) }
        .to raise_error(ActiveRecord::ReadonlyAttributeError)
    end

    # 発行した直後のシードと、DB から読み直したシードで結果が揃うこと。
    # bigint への往復で値が化けると、抽選をやり直しても同じ結果にならない
    it '保存したシードで Matching::Engine の結果が再現できる' do
      exchange = create(:exchange)
      generated = matching_result_for(exchange.random_seed)

      expect(matching_result_for(exchange.reload.random_seed)).to eq(generated)
    end
  end
end
