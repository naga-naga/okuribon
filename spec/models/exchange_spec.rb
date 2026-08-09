# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exchange do
  # DB の例外にする前にバリデーションで捕まえる。フォームに戻せるのはこちらだけ
  it '必須のカラムに nil を入れるとバリデーションで落ちる' do
    columns = [
      :name, :registration_starts_at, :registration_ends_at,
      :wish_ends_at, :invite_token, :random_seed,
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
      :wish_ends_at, :invite_token, :random_seed,
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

  # 空きを許すとどのフェーズにも属さない時間ができるため、両者は同時刻でなければならない。
  # カラムに分けて等値を検証するのではなく、導出して二重管理をなくす
  describe '#wish_starts_at' do
    it '登録期間の終了と同じ時刻になる' do
      exchange = build(:exchange, registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone)

      expect(exchange.wish_starts_at).to eq('2026-08-08T00:00:00+09:00'.in_time_zone)
    end

    it '登録期間の終了を動かすと追随する' do
      exchange = build(:exchange)
      exchange.registration_ends_at = '2026-09-01T00:00:00+09:00'.in_time_zone

      expect(exchange.wish_starts_at).to eq('2026-09-01T00:00:00+09:00'.in_time_zone)
    end

    # カラムとして残っていると、直接 SQL や update_column で登録期間の終了とずれる
    it 'カラムとしては持たない' do
      expect(described_class.column_names).not_to include('wish_starts_at')
    end
  end

  describe '期間の整合性' do
    it '登録期間の終了が開始より前だと無効になる' do
      exchange = build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-07-31T00:00:00+09:00'.in_time_zone,
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
        wish_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone
      )

      expect(exchange).not_to be_valid
      expect(exchange.errors.full_messages)
        .to contain_exactly('希望提出期間の終了日時は開始日時より後にしてください')
    end

    it '日時が欠けていても順序のエラーは足さない' do
      exchange = build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: nil,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )

      expect(exchange).not_to be_valid
      expect(exchange.errors.full_messages)
        .to contain_exactly('登録期間の終了日時を入力してください')
    end
  end

  describe '#phase' do
    let!(:exchange) do
      build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
    end

    it '登録期間の開始前は準備中になる' do
      expect(exchange.phase(at: '2026-07-25T00:00:00+09:00'.in_time_zone)).to eq(:preparing)
    end

    it '登録期間中は登録期間になる' do
      expect(exchange.phase(at: '2026-08-04T00:00:00+09:00'.in_time_zone)).to eq(:registration)
    end

    it '希望提出期間中は希望提出期間になる' do
      expect(exchange.phase(at: '2026-08-11T00:00:00+09:00'.in_time_zone)).to eq(:wish)
    end

    it '希望提出期間の終了後はマッチング実行待ちになる' do
      expect(exchange.phase(at: '2026-08-20T00:00:00+09:00'.in_time_zone)).to eq(:awaiting_matching)
    end

    it 'マッチング実行日時が入っていれば結果公開になる' do
      exchange.matched_at = '2026-08-16T00:00:00+09:00'.in_time_zone

      expect(exchange.phase(at: '2026-08-20T00:00:00+09:00'.in_time_zone)).to eq(:published)
    end

    # 実行後に主催者が期間の日時を戻しても、結果が公開済みであることは変わらない
    it 'マッチング実行日時が入っていれば、登録期間中の時刻でも結果公開になる' do
      exchange.matched_at = '2026-08-16T00:00:00+09:00'.in_time_zone

      expect(exchange.phase(at: '2026-08-04T00:00:00+09:00'.in_time_zone)).to eq(:published)
    end

    # 既定値を置くと呼ぶたびに現在時刻が進み、締切をまたいだ瞬間に
    # 1つの画面の中でフェーズが食い違う。基準時刻は入口で1回読んで回す
    it '基準時刻を省略すると呼べない' do
      expect { exchange.phase }.to raise_error(ArgumentError)
    end

    # 締切ちょうどの扱いが曖昧だと、締切直前の操作の可否が実装ごとにぶれる。
    # 各期間は開始時刻を含み、終了時刻を含まない。締切ちょうどはその期間の外になる
    describe '境界' do
      it '登録期間の開始ちょうどから登録期間になる' do
        boundary = '2026-08-01T00:00:00+09:00'.in_time_zone

        expect(exchange.phase(at: boundary - 1.second)).to eq(:preparing)
        expect(exchange.phase(at: boundary)).to eq(:registration)
        expect(exchange.phase(at: boundary + 1.second)).to eq(:registration)
      end

      # 登録期間の終了と希望提出期間の開始は同時刻なので、この1点で両者が入れ替わる。
      # 締切ちょうどにはもう本を登録できず、希望リストの編集が始まる
      it '登録の締切ちょうどから希望提出期間になる' do
        boundary = '2026-08-08T00:00:00+09:00'.in_time_zone

        expect(exchange.phase(at: boundary - 1.second)).to eq(:registration)
        expect(exchange.phase(at: boundary)).to eq(:wish)
        expect(exchange.phase(at: boundary + 1.second)).to eq(:wish)
      end

      it '希望提出の締切ちょうどからマッチング実行待ちになる' do
        boundary = '2026-08-15T00:00:00+09:00'.in_time_zone

        expect(exchange.phase(at: boundary - 1.second)).to eq(:wish)
        expect(exchange.phase(at: boundary)).to eq(:awaiting_matching)
        expect(exchange.phase(at: boundary + 1.second)).to eq(:awaiting_matching)
      end

      # 締切は JST の 8/8 0:00。UTC では 8/7 15:00 にあたる。
      # UTC の日付で見ると 8/7 のうちに締切を過ぎることになり、判定が9時間ずれる
      it '同じ瞬間なら UTC 表記で渡しても同じフェーズになる' do
        expect(exchange.phase(at: '2026-08-07T14:59:59Z'.in_time_zone)).to eq(:registration)
        expect(exchange.phase(at: '2026-08-07T15:00:00Z'.in_time_zone)).to eq(:wish)
      end

      # フォームから来る日時にはタイムゾーンが付かない。UTC として読むと9時間ずれる
      it 'タイムゾーンの付かない文字列は JST として解釈される' do
        exchange = build(:exchange, registration_ends_at: '2026-08-08 00:00:00')

        expect(exchange.registration_ends_at).to eq('2026-08-08T00:00:00+09:00'.in_time_zone)
        expect(exchange.phase(at: '2026-08-07T15:00:00Z'.in_time_zone)).to eq(:wish)
      end
    end

    it '5つのフェーズ以外の値は返さない' do
      at_list = [
        '2026-07-25T00:00:00+09:00', '2026-08-04T00:00:00+09:00',
        '2026-08-11T00:00:00+09:00', '2026-08-20T00:00:00+09:00',
      ]

      expect(at_list.map { |at| exchange.phase(at: at.in_time_zone) })
        .to all(be_in(Exchange::PHASES))
    end
  end

  describe '#phase_name' do
    let!(:exchange) do
      build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
    end

    it '基準時刻のフェーズの表示名を日本語で返す' do
      expect(exchange.phase_name(at: '2026-07-25T00:00:00+09:00'.in_time_zone)).to eq('準備中')
      expect(exchange.phase_name(at: '2026-08-04T00:00:00+09:00'.in_time_zone)).to eq('登録期間')
      expect(exchange.phase_name(at: '2026-08-11T00:00:00+09:00'.in_time_zone)).to eq('希望提出期間')
      expect(exchange.phase_name(at: '2026-08-20T00:00:00+09:00'.in_time_zone)).to eq('マッチング実行待ち')
    end

    it 'マッチング実行日時が入っていれば結果公開になる' do
      exchange.matched_at = '2026-08-16T00:00:00+09:00'.in_time_zone

      expect(exchange.phase_name(at: '2026-08-20T00:00:00+09:00'.in_time_zone)).to eq('結果公開')
    end

    it '基準時刻を省略すると呼べない' do
      expect { exchange.phase_name }.to raise_error(ArgumentError)
    end
  end

  describe '#published?' do
    let!(:exchange) do
      build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
    end

    it 'マッチングを実行していなければ、締切を過ぎていても偽になる' do
      expect(exchange).not_to be_published(at: '2026-08-20T00:00:00+09:00'.in_time_zone)
    end

    it 'マッチング実行日時が入っていれば真になる' do
      exchange.matched_at = '2026-08-16T00:00:00+09:00'.in_time_zone

      expect(exchange).to be_published(at: '2026-08-20T00:00:00+09:00'.in_time_zone)
    end

    # フェーズはマッチングを実行したかどうかで決まる（docs/spec.md 4.）。
    # 結果公開後に主催者が日程を戻しても、公開済みであることは変わらない
    it '実行後に日程を戻しても真のままになる' do
      exchange.matched_at = '2026-08-16T00:00:00+09:00'.in_time_zone

      expect(exchange).to be_published(at: '2026-08-04T00:00:00+09:00'.in_time_zone)
    end

    it '基準時刻を省略すると呼べない' do
      expect { exchange.published? }.to raise_error(ArgumentError)
    end
  end

  describe '#next_deadline' do
    let!(:exchange) do
      build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
    end

    it '準備中は登録期間の開始を返す' do
      expect(exchange.next_deadline(at: '2026-07-25T00:00:00+09:00'.in_time_zone))
        .to eq(exchange.registration_starts_at)
    end

    it '登録期間は登録の締切を返す' do
      expect(exchange.next_deadline(at: '2026-08-04T00:00:00+09:00'.in_time_zone))
        .to eq(exchange.registration_ends_at)
    end

    it '希望提出期間は希望提出の締切を返す' do
      expect(exchange.next_deadline(at: '2026-08-11T00:00:00+09:00'.in_time_zone))
        .to eq(exchange.wish_ends_at)
    end

    # 待っているのは主催者の操作で、日時では動かない
    it 'マッチング実行待ちは返さない' do
      expect(exchange.next_deadline(at: '2026-08-20T00:00:00+09:00'.in_time_zone)).to be_nil
    end

    # 終わった交換会に締切を出すと、まだ何かできるように読める
    it '結果公開は返さない' do
      exchange.matched_at = '2026-08-16T00:00:00+09:00'.in_time_zone

      expect(exchange.next_deadline(at: '2026-08-20T00:00:00+09:00'.in_time_zone)).to be_nil
    end

    it '基準時刻を省略すると呼べない' do
      expect { exchange.next_deadline }.to raise_error(ArgumentError)
    end
  end

  describe '#next_deadline_name' do
    let!(:exchange) do
      build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
    end

    # 準備中に待っているのは締切ではなく開始。「締切」と出すと、
    # まだ始まってもいない登録がもう終わるように読める
    it '節目の呼び名をフェーズごとに返す' do
      expect(exchange.next_deadline_name(at: '2026-07-25T00:00:00+09:00'.in_time_zone))
        .to eq('登録期間の開始')
      expect(exchange.next_deadline_name(at: '2026-08-04T00:00:00+09:00'.in_time_zone))
        .to eq('登録の締切')
      expect(exchange.next_deadline_name(at: '2026-08-11T00:00:00+09:00'.in_time_zone))
        .to eq('希望提出の締切')
    end

    it '次の節目が無いフェーズでは返さない' do
      expect(exchange.next_deadline_name(at: '2026-08-20T00:00:00+09:00'.in_time_zone)).to be_nil
    end

    it '基準時刻を省略すると呼べない' do
      expect { exchange.next_deadline_name }.to raise_error(ArgumentError)
    end
  end

  # 招待画面は「何がいつ起きるのか」を3段で見せる。段はフェーズと1対1ではないので、
  # フェーズをそのまま並べず、段ごとの進み具合を導く
  describe '日程の3段' do
    let!(:exchange) do
      build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
    end

    describe '#schedule_starts_at' do
      it '段ごとの開始日時を返す' do
        expect(exchange.schedule_starts_at(:registration)).to eq(exchange.registration_starts_at)
        expect(exchange.schedule_starts_at(:wish)).to eq(exchange.wish_starts_at)
      end

      # 公開されるのは主催者がマッチングを実行したときで、日時では決まらない。
      # 希望提出の締切は「それより前には公開されない」という下限にあたる
      it '結果公開は希望提出の締切を返す' do
        expect(exchange.schedule_starts_at(:published)).to eq(exchange.wish_ends_at)
      end

      it '段に無い名前では落ちる' do
        expect { exchange.schedule_starts_at(:matching) }.to raise_error(KeyError)
      end
    end

    describe '#period' do
      it '期間ごとの範囲を返す' do
        expect(exchange.period(:registration))
          .to eq(exchange.registration_starts_at...exchange.registration_ends_at)
        expect(exchange.period(:wish)).to eq(exchange.wish_starts_at...exchange.wish_ends_at)
      end

      # 各期間は終了時刻を含まない（docs/spec.md 4.）。締切ちょうどは期間の外で、
      # ここが含む範囲になると phase の判定と1点だけ食い違う
      it '終了時刻を含まない' do
        expect(exchange.period(:registration)).not_to cover(exchange.registration_ends_at)
        expect(exchange.period(:registration)).to cover(exchange.registration_starts_at)
      end

      # 主催者が動かせるのは登録期間と希望提出期間だけ。
      # 結果公開は主催者の実行で起きて日時では決まらないため、期間を持たない
      it '期間に無い名前では落ちる' do
        expect { exchange.period(:published) }.to raise_error(KeyError)
      end
    end

    describe '#schedule_state' do
      it '準備中はどの段もまだ始まっていない' do
        at = '2026-07-25T00:00:00+09:00'.in_time_zone

        expect(exchange.schedule_state(:registration, at:)).to eq(:upcoming)
        expect(exchange.schedule_state(:wish, at:)).to eq(:upcoming)
        expect(exchange.schedule_state(:published, at:)).to eq(:upcoming)
      end

      it '登録期間は1段目だけが進行中' do
        at = '2026-08-04T00:00:00+09:00'.in_time_zone

        expect(exchange.schedule_state(:registration, at:)).to eq(:current)
        expect(exchange.schedule_state(:wish, at:)).to eq(:upcoming)
        expect(exchange.schedule_state(:published, at:)).to eq(:upcoming)
      end

      it '希望提出期間は1段目が終わり2段目が進行中' do
        at = '2026-08-11T00:00:00+09:00'.in_time_zone

        expect(exchange.schedule_state(:registration, at:)).to eq(:done)
        expect(exchange.schedule_state(:wish, at:)).to eq(:current)
        expect(exchange.schedule_state(:published, at:)).to eq(:upcoming)
      end

      # マッチング実行待ちに対応する段は無い。希望提出は終わっているが、
      # 主催者が実行するまで結果は公開されない。3段目を進行中にすると、
      # もう結果が見られるように読める
      it 'マッチング実行待ちは2段目まで終わり3段目はまだ始まっていない' do
        at = '2026-08-20T00:00:00+09:00'.in_time_zone

        expect(exchange.schedule_state(:registration, at:)).to eq(:done)
        expect(exchange.schedule_state(:wish, at:)).to eq(:done)
        expect(exchange.schedule_state(:published, at:)).to eq(:upcoming)
      end

      it '結果公開は3段目が進行中' do
        exchange.matched_at = '2026-08-16T00:00:00+09:00'.in_time_zone
        at = '2026-08-20T00:00:00+09:00'.in_time_zone

        expect(exchange.schedule_state(:registration, at:)).to eq(:done)
        expect(exchange.schedule_state(:wish, at:)).to eq(:done)
        expect(exchange.schedule_state(:published, at:)).to eq(:current)
      end

      # 主催者は公開後も日時を動かせる（spec.md 6.9）。日時を先へ動かされても、
      # 公開が済んでいることは変わらない。段の進み具合を日時から数え直さない
      it '公開後に日時を先へ動かしても1段目と2段目は終わったまま' do
        exchange.matched_at = '2026-08-16T00:00:00+09:00'.in_time_zone
        exchange.registration_starts_at = '2027-01-01T00:00:00+09:00'.in_time_zone
        exchange.registration_ends_at = '2027-01-08T00:00:00+09:00'.in_time_zone
        exchange.wish_ends_at = '2027-01-15T00:00:00+09:00'.in_time_zone

        at = '2026-08-20T00:00:00+09:00'.in_time_zone

        expect(exchange.schedule_state(:registration, at:)).to eq(:done)
        expect(exchange.schedule_state(:wish, at:)).to eq(:done)
      end

      it '段に無い名前では落ちる' do
        expect { exchange.schedule_state(:matching, at: Time.current) }.to raise_error(KeyError)
      end

      it '基準時刻を省略すると呼べない' do
        expect { exchange.schedule_state(:registration) }.to raise_error(ArgumentError)
      end
    end
  end

  # 「登録期間中のみ本を登録できる」といった判定を、書き込み口ごとの手書きにしない。
  # 許可されるフェーズは spec.md 4. フェーズの表と補足に対応する
  describe '#writable?' do
    let!(:exchange) do
      build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
    end

    # フェーズごとに全操作の可否を並べる。許可されるものだけを確かめると、
    # 表から漏れた操作が既定で通っていても気付けない
    it '準備中は参加だけできる' do
      at = '2026-07-25T00:00:00+09:00'.in_time_zone

      expect(exchange.writable?(:participation, at:)).to be(true)
      expect(exchange.writable?(:book, at:)).to be(false)
      expect(exchange.writable?(:wish, at:)).to be(false)
      expect(exchange.writable?(:matching, at:)).to be(false)
    end

    it '登録期間は参加と本の登録ができる' do
      at = '2026-08-04T00:00:00+09:00'.in_time_zone

      expect(exchange.writable?(:participation, at:)).to be(true)
      expect(exchange.writable?(:book, at:)).to be(true)
      expect(exchange.writable?(:wish, at:)).to be(false)
      expect(exchange.writable?(:matching, at:)).to be(false)
    end

    it '希望提出期間は希望リストの変更だけできる' do
      at = '2026-08-11T00:00:00+09:00'.in_time_zone

      expect(exchange.writable?(:participation, at:)).to be(false)
      expect(exchange.writable?(:book, at:)).to be(false)
      expect(exchange.writable?(:wish, at:)).to be(true)
      expect(exchange.writable?(:matching, at:)).to be(false)
    end

    it 'マッチング実行待ちはマッチングの実行だけできる' do
      at = '2026-08-20T00:00:00+09:00'.in_time_zone

      expect(exchange.writable?(:participation, at:)).to be(false)
      expect(exchange.writable?(:book, at:)).to be(false)
      expect(exchange.writable?(:wish, at:)).to be(false)
      expect(exchange.writable?(:matching, at:)).to be(true)
    end

    # マッチングを再実行できると結果を引き直せてしまう。
    # 実行済みなら以降どのフェーズの時刻で見ても書き込みは通らない
    it '結果公開ではどれも書けない' do
      exchange.matched_at = '2026-08-16T00:00:00+09:00'.in_time_zone
      at = '2026-08-20T00:00:00+09:00'.in_time_zone

      expect(exchange.writable?(:participation, at:)).to be(false)
      expect(exchange.writable?(:book, at:)).to be(false)
      expect(exchange.writable?(:wish, at:)).to be(false)
      expect(exchange.writable?(:matching, at:)).to be(false)
    end

    # 締切ちょうどはその期間の外になる。登録期間の終了と希望提出期間の開始は
    # 同時刻なので、この1点で書ける対象が入れ替わる
    it '登録の締切ちょうどで、本の登録から希望リストの変更に入れ替わる' do
      boundary = '2026-08-08T00:00:00+09:00'.in_time_zone

      expect(exchange.writable?(:book, at: boundary - 1.second)).to be(true)
      expect(exchange.writable?(:book, at: boundary)).to be(false)
      expect(exchange.writable?(:wish, at: boundary - 1.second)).to be(false)
      expect(exchange.writable?(:wish, at: boundary)).to be(true)
    end

    # 希望提出期間に入ってから抜けられると、取得枠の計算が壊れる
    it '登録の締切ちょうどから参加できなくなる' do
      boundary = '2026-08-08T00:00:00+09:00'.in_time_zone

      expect(exchange.writable?(:participation, at: boundary - 1.second)).to be(true)
      expect(exchange.writable?(:participation, at: boundary)).to be(false)
    end

    it '基準時刻を省略すると呼べない' do
      expect { exchange.writable?(:wish) }.to raise_error(ArgumentError)
    end

    # 表に無い操作名を false で受けると綴り間違いが「書けない」に化けて気付けず、
    # true で受ければ素通りする。どちらも危ないので落とす
    it '表に無い操作名を渡すと例外になる' do
      at = '2026-08-04T00:00:00+09:00'.in_time_zone

      expect { exchange.writable?(:unknown, at:) }.to raise_error(KeyError)
    end
  end

  describe 'フェーズ違反の例外' do
    let!(:exchange) do
      build(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
    end

    # 操作を足したときに翻訳を足し忘れると、拒否の画面が
    # translation missing のまま利用者に出てしまう
    it 'すべての操作について、翻訳の抜けていないメッセージになる' do
      at = '2026-08-11T00:00:00+09:00'.in_time_zone

      messages = Exchange::WRITABLE_PHASES.keys.map do |operation|
        described_class::PhaseViolation.new(exchange, operation, at:).message
      end

      expect(messages.join("\n")).not_to include('translation missing')
      expect(messages.uniq.size).to eq(Exchange::WRITABLE_PHASES.size)
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

  describe '#participant?' do
    let!(:exchange) { create(:exchange) }
    let!(:user) { create(:user) }

    it '参加していれば true になる' do
      create(:participation, exchange:, user:)

      expect(exchange.participant?(user)).to be(true)
    end

    it '参加していなければ false になる' do
      expect(exchange.participant?(user)).to be(false)
    end

    it '別の交換会への参加は数えない' do
      create(:participation, user:)

      expect(exchange.participant?(user)).to be(false)
    end

    # 未ログインの人は着地画面をそのまま見る。呼ぶ側で nil を弾かせない
    it '利用者がいなければ false になる' do
      expect(exchange.participant?(nil)).to be(false)
    end
  end

  describe '#owner?' do
    let!(:exchange) { create(:exchange) }

    it '主催者なら true になる' do
      expect(exchange.owner?(exchange.owner)).to be(true)
    end

    it '主催者以外なら false になる' do
      expect(exchange.owner?(create(:user))).to be(false)
    end

    # 未ログインの人は着地画面をそのまま見る。呼ぶ側で nil を弾かせない
    it '利用者がいなければ false になる' do
      expect(exchange.owner?(nil)).to be(false)
    end
  end

  describe '#removable_participant?' do
    let!(:exchange) do
      create(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
    end
    let!(:user) { create(:user) }

    let!(:registration) { '2026-08-04T00:00:00+09:00'.in_time_zone }

    it '登録期間中の参加者なら true になる' do
      exchange.join!(user, at: registration)

      expect(exchange.removable_participant?(user, at: registration)).to be(true)
    end

    it '参加していなければ false になる' do
      expect(exchange.removable_participant?(user, at: registration)).to be(false)
    end

    # 抜けられる期間かどうかによらない
    it '主催者なら false になる' do
      exchange.join!(exchange.owner, at: registration)

      expect(exchange.removable_participant?(exchange.owner, at: registration)).to be(false)
    end

    it '登録の締切を過ぎていれば false になる' do
      exchange.join!(user, at: registration)

      expect(exchange.removable_participant?(user, at: '2026-08-08T00:00:00+09:00'.in_time_zone)).to be(false)
    end

    it '利用者がいなければ false になる' do
      expect(exchange.removable_participant?(nil, at: registration)).to be(false)
    end
  end

  describe '#join!' do
    let!(:exchange) do
      create(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
    end
    let!(:user) { create(:user) }

    let!(:registration) { '2026-08-04T00:00:00+09:00'.in_time_zone }

    it '参加を作って返す' do
      participation = exchange.join!(user, at: registration)

      expect(participation).to be_persisted
      expect(exchange.participant?(user)).to be(true)
    end

    it '準備中でも参加できる' do
      expect { exchange.join!(user, at: '2026-07-25T00:00:00+09:00'.in_time_zone) }
        .to change { exchange.participations.count }.by(1)
    end

    # 参加の入口はフォームとログイン後の復帰の2つある。どちらから来ても
    # ここを通るため、フェーズの判定はコントローラではなくこのメソッドで確かめる
    it '登録の締切ちょうどからは参加できない' do
      expect { exchange.join!(user, at: '2026-08-08T00:00:00+09:00'.in_time_zone) }
        .to raise_error(Exchange::PhaseViolation)
      expect(exchange.participant?(user)).to be(false)
    end

    it '希望提出期間には参加できない' do
      expect { exchange.join!(user, at: '2026-08-11T00:00:00+09:00'.in_time_zone) }
        .to raise_error(Exchange::PhaseViolation)
    end

    # 二重送信や、同時に届いた2つのリクエストで参加が2つできないこと。
    # 一意インデックスの違反を拾って既存を引くため、2回目はこの経路をそのまま通る
    it '二度呼んでも参加は増えず、同じものを返す' do
      first = exchange.join!(user, at: registration)
      second = exchange.join!(user, at: registration)

      expect(second).to eq(first)
      expect(exchange.participations.where(user:).count).to eq(1)
    end

    it '別の利用者はそれぞれ参加できる' do
      exchange.join!(user, at: registration)

      expect { exchange.join!(create(:user), at: registration) }
        .to change { exchange.participations.count }.by(1)
    end
  end

  describe '#remove_participant!' do
    let!(:exchange) do
      create(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
    end
    let!(:user) { create(:user) }

    let!(:registration) { '2026-08-04T00:00:00+09:00'.in_time_zone }

    it '参加を取り消す' do
      exchange.join!(user, at: registration)

      expect { exchange.remove_participant!(user, at: registration) }
        .to change { exchange.participant?(user) }.from(true).to(false)
    end

    # 抜けた人の本が残ると、誰も受け取れない本として一覧に並び続ける
    it '登録した本も一緒に取り消される' do
      participation = exchange.join!(user, at: registration)
      create(:book, participation:)

      expect { exchange.remove_participant!(user, at: registration) }
        .to change(Book, :count).by(-1)
    end

    it '準備中でも辞退できる' do
      exchange.join!(user, at: '2026-07-25T00:00:00+09:00'.in_time_zone)

      expect { exchange.remove_participant!(user, at: '2026-07-25T00:00:00+09:00'.in_time_zone) }
        .to change { exchange.participations.count }.by(-1)
    end

    # 希望提出期間に入ってから抜けられると、取得枠の計算が壊れる。
    # 判定は join! と同じ表を引くため、参加を許す期間と必ず一致する
    it '登録の締切ちょうどからは辞退できない' do
      exchange.join!(user, at: registration)

      expect { exchange.remove_participant!(user, at: '2026-08-08T00:00:00+09:00'.in_time_zone) }
        .to raise_error(Exchange::PhaseViolation)
      expect(exchange.participant?(user)).to be(true)
    end

    it '希望提出期間には辞退できない' do
      exchange.join!(user, at: registration)

      expect { exchange.remove_participant!(user, at: '2026-08-11T00:00:00+09:00'.in_time_zone) }
        .to raise_error(Exchange::PhaseViolation)
    end

    # 二重送信や、戻るボタンからの再送信で落ちないこと
    it '二度呼んでも落ちない' do
      exchange.join!(user, at: registration)
      exchange.remove_participant!(user, at: registration)

      expect { exchange.remove_participant!(user, at: registration) }
        .not_to(change { exchange.participations.count })
    end

    it '参加していない利用者を渡しても落ちない' do
      expect { exchange.remove_participant!(user, at: registration) }
        .not_to(change { exchange.participations.count })
    end

    it '他の参加者は残る' do
      exchange.join!(user, at: registration)
      other = create(:user)
      exchange.join!(other, at: registration)

      exchange.remove_participant!(user, at: registration)

      expect(exchange.participant?(other)).to be(true)
    end

    # 主催者が抜けると、参加者のいない交換会や、主催者だけが入れない
    # 交換会が残る。フェーズではなく役割による拒否なので、例外を分ける
    it '主催者は辞退できない' do
      exchange.join!(exchange.owner, at: registration)

      expect { exchange.remove_participant!(exchange.owner, at: registration) }
        .to raise_error(Exchange::OwnerLocked)
      expect(exchange.participant?(exchange.owner)).to be(true)
    end

    # 抜けられる期間かどうかによらない。フェーズを先に見ると、
    # 締切後に主催者が押したときだけ理由が入れ替わる
    it '主催者は抜けられない期間でも同じ理由で拒否される' do
      exchange.join!(exchange.owner, at: registration)

      expect { exchange.remove_participant!(exchange.owner, at: '2026-08-11T00:00:00+09:00'.in_time_zone) }
        .to raise_error(Exchange::OwnerLocked)
    end

    # 辞退したあと考え直すことはある。登録期間のうちなら戻れる
    it '辞退したあとに参加し直せる' do
      exchange.join!(user, at: registration)
      exchange.remove_participant!(user, at: registration)

      expect { exchange.join!(user, at: registration) }
        .to change { exchange.participant?(user) }.from(false).to(true)
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
