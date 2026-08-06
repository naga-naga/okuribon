# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Book do
  it '登録者を往復できる' do
    participation = create(:participation)
    book = create(:book, participation:)

    expect(book.participation).to eq(participation)
    expect(participation.books).to contain_exactly(book)
  end

  it '登録者を経由して交換会を辿れる' do
    book = create(:book)

    expect(book.exchange).to eq(book.participation.exchange)
    expect(book.exchange.books).to contain_exactly(book)
  end

  it 'ひとりで何冊でも登録できる' do
    participation = create(:participation)

    books = create_list(:book, 3, participation:)

    expect(participation.books).to match_array(books)
  end

  it 'あらすじ・URL・おすすめポイントは無くても登録できる' do
    book = create(:book, summary: nil, url: nil, recommendation: nil)

    expect(book).to be_persisted
  end

  # DB の例外ではなくフォームのエラーとして返す。
  # NOT NULL に任せると、入力欄に戻さず 500 になる。
  # 型ではなく画面に出る文言で固定する。型で照合すると、属性名の訳を
  # ja.yml から落としても spec が通り、「Titleを入力してください」が出続ける
  it 'タイトルが空だと保存できない' do
    book = build(:book, title: '  ')

    expect(book).not_to be_valid
    expect(book.errors.full_messages).to include('タイトルを入力してください')
  end

  it 'ギフトコードが空だと保存できない' do
    book = build(:book, gift_code: '  ')

    expect(book).not_to be_valid
    expect(book.errors.full_messages).to include('ギフトコードを入力してください')
  end

  it 'バリデーションを外しても DB が空を拒む' do
    expect { build(:book, title: nil).save(validate: false) }
      .to raise_error(ActiveRecord::NotNullViolation)
    expect { build(:book, gift_code: nil).save(validate: false) }
      .to raise_error(ActiveRecord::NotNullViolation)
  end

  it '登録者のいない本は保存できない' do
    expect { build(:book, participation: nil).save(validate: false) }
      .to raise_error(ActiveRecord::NotNullViolation)
  end

  describe 'ギフトコード' do
    # 結果公開の交換会。受け取った人にギフトコードが見えるのは成立後に限る
    let!(:exchange) { create(:exchange, matched_at: '2026-08-16T00:00:00+09:00'.in_time_zone) }
    let!(:at) { '2026-08-20T00:00:00+09:00'.in_time_zone }
    let!(:registrant) { create(:participation, exchange:) }
    let!(:recipient) { create(:participation, exchange:) }
    let!(:book) { create(:book, participation: registrant, gift_code: 'GIFT-1234') }

    it '暗号化して保存する' do
      stored = described_class.lease_connection.select_value(
        described_class.sanitize_sql(['SELECT gift_code FROM books WHERE id = ?', book.id])
      )

      expect(stored).not_to include('GIFT-1234')
    end

    it '登録した本人は結果公開後も読める' do
      expect(book.gift_code_for(registrant.user, at:)).to eq('GIFT-1234')
    end

    # 自分の本のギフトコードは登録フォームでも出す。フェーズを問わず読める
    it '登録した本人は登録期間中も読める' do
      registration = create(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
      mine = create(:book, participation: create(:participation, exchange: registration),
                           gift_code: 'GIFT-5678')

      expect(mine.gift_code_for(mine.participation.user, at: '2026-08-04T00:00:00+09:00'.in_time_zone))
        .to eq('GIFT-5678')
    end

    it '受け取った人は結果公開後に読める' do
      create(:assignment, book:, participation: recipient)

      expect(book.gift_code_for(recipient.user, at:)).to eq('GIFT-1234')
    end

    it '主催者でも他人のギフトコードは読めない' do
      create(:assignment, book:, participation: recipient)

      expect(book.gift_code_for(exchange.owner, at:)).to be_nil
    end

    it '割当が成立していない参加者は読めない' do
      expect(book.gift_code_for(recipient.user, at:)).to be_nil
    end

    it '交換会の外の人は読めない' do
      expect(book.gift_code_for(create(:user), at:)).to be_nil
    end

    it '未ログインでは読めない' do
      expect(book.gift_code_for(nil, at:)).to be_nil
    end

    # 割当は結果公開と同時にできるため通常は起きないが、returned を見落とすと
    # 返却フラグが可視性に効かなくなる。返却の割当を受け取りとして扱わないことを固定する
    it '返却された本を受取人扱いで読ませない' do
      create(:assignment, book:, participation: recipient, returned: true)

      expect(book.gift_code_for(recipient.user, at:)).to be_nil
    end

    it '結果公開前は割当があっても読めない' do
      exchange.update!(matched_at: nil)
      create(:assignment, book:, participation: recipient)

      expect(book.gift_code_for(recipient.user, at:)).to be_nil
    end

    # 既定値を置くと呼ぶたびに現在時刻が進む。基準時刻は入口で1回読んで回す
    it '基準時刻を省略すると呼べない' do
      expect { book.gift_code_for(registrant.user) }.to raise_error(ArgumentError)
    end

    it '素のギフトコードは外から読めない' do
      expect { book.gift_code }.to raise_error(NoMethodError)
    end

    it '見えるかどうかを判定できる' do
      create(:assignment, book:, participation: recipient)

      expect(book.gift_code_visible_to?(recipient.user, at:)).to be(true)
      expect(book.gift_code_visible_to?(exchange.owner, at:)).to be(false)
    end

    it 'シリアライズの結果に現れない' do
      expect(book.serializable_hash).not_to have_key('gift_code')
      expect(book.to_json).not_to include('gift_code')
    end

    # only を渡せば出せる、という抜け道を残さない
    it '項目を指定してもシリアライズの結果に現れない' do
      expect(book.serializable_hash(only: :gift_code)).to be_empty
    end
  end

  it '消すとその本への希望と割当も消える' do
    exchange = create(:exchange)
    book = create(:book, participation: create(:participation, exchange:))
    recipient = create(:participation, exchange:)
    create(:wish, participation: recipient, book:)
    create(:assignment, book:, participation: recipient)

    book.destroy

    expect(Wish.count).to eq(0)
    expect(Assignment.count).to eq(0)
    expect(recipient.reload).to be_persisted
  end
end
