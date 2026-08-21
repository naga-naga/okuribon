# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exchanges::Creation do
  let!(:owner) { create(:user) }

  let!(:attributes) do
    {
      name: '夏の交換会',
      description: 'Kindle のみ。1000円前後を目安に。',
      registration_starts_at: '2026-08-10T10:00:00+09:00'.in_time_zone,
      registration_ends_at: '2026-08-24T10:00:00+09:00'.in_time_zone,
      wish_ends_at: '2026-09-07T10:00:00+09:00'.in_time_zone,
    }
  end

  # 準備中。作れる時刻の既定として使う
  let!(:before_registration) { '2026-08-05T00:00:00+09:00'.in_time_zone }

  def create_exchange(at: before_registration, **overrides)
    described_class.new(owner:, attributes: attributes.merge(overrides), at:).call
  end

  it '交換会を作る' do
    exchange = create_exchange

    expect(exchange).to be_persisted
    expect(exchange.name).to eq('夏の交換会')
  end

  it '渡した利用者が主催者になる' do
    expect(create_exchange.owner).to eq(owner)
  end

  # 参加していない人には交換会が見えない。主催者だけが参加者でないまま残ると、
  # どの画面も「主催者が来たらどうするか」を個別に答えることになる
  it '主催者の参加も同時にできる' do
    exchange = create_exchange

    expect(exchange.participant?(owner)).to be(true)
    expect(exchange.participations.count).to eq(1)
  end

  it '登録期間に入っていても作れる' do
    exchange = create_exchange(at: '2026-08-15T00:00:00+09:00'.in_time_zone)

    expect(exchange).to be_persisted
    expect(exchange.participant?(owner)).to be(true)
  end

  describe '登録の締切を過ぎた日程' do
    # 締切を過ぎていると主催者の参加を作れず、参加者のいない交換会が残る
    it '作れない' do
      expect { create_exchange(at: '2026-08-25T00:00:00+09:00'.in_time_zone) }
        .not_to change(Exchange, :count)
    end

    # 各期間は終了時刻を含まない。締切ちょうどはもう登録期間の外
    it '締切ちょうどでも作れない' do
      exchange = create_exchange(at: '2026-08-24T10:00:00+09:00'.in_time_zone)

      expect(exchange).not_to be_persisted
    end

    it '差し戻した交換会に日本語のエラーが載る' do
      exchange = create_exchange(at: '2026-08-25T00:00:00+09:00'.in_time_zone)

      expect(exchange.errors.full_messages)
        .to include('登録期間の終了日時は現在より後にしてください')
    end

    it '参加も作られない' do
      expect { create_exchange(at: '2026-08-25T00:00:00+09:00'.in_time_zone) }
        .not_to change(Participation, :count)
    end
  end

  describe '入力の不備' do
    it '作れない' do
      expect { create_exchange(name: '') }.not_to change(Exchange, :count)
    end

    # 差し戻したフォームに入力が残らないと、全部打ち直しになる
    it '入力を保ったまま差し戻す' do
      exchange = create_exchange(name: '')

      expect(exchange.description).to eq('Kindle のみ。1000円前後を目安に。')
      expect(exchange.errors[:name]).to be_present
    end

    # 締切の判定はフェーズの導出を通るため、日時が欠けていると先に落ちる。
    # 不備を先に見て、判定そのものへ進ませない
    it '日時が空でも落ちない' do
      exchange = create_exchange(registration_ends_at: nil)

      expect(exchange).not_to be_persisted
      expect(exchange.errors[:registration_ends_at]).to be_present
    end
  end

  # 交換会だけが残ると、主催者が参加者でない交換会ができてしまう。
  # 参加の作成は組み立てた交換会に対して呼ぶので、差し替えられる場所がここしかない
  it '参加を作れなければ交換会も残らない' do
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Exchange).to receive(:join!).and_raise(ActiveRecord::StatementInvalid)
    # rubocop:enable RSpec/AnyInstance

    expect { create_exchange }.to raise_error(ActiveRecord::StatementInvalid)
    expect(Exchange.count).to eq(0)
  end
end
