# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Participation do
  # 交換会も参加者も belongs_to の既定で必須になるが、
  # ここで確かめたいのは DB 側の制約なのでバリデーションを飛ばす
  it '交換会と参加者のどちらが欠けても保存できない' do
    expect { build(:participation, exchange: nil).save(validate: false) }
      .to raise_error(ActiveRecord::NotNullViolation)
    expect { build(:participation, user: nil).save(validate: false) }
      .to raise_error(ActiveRecord::NotNullViolation)
  end

  it '交換会と参加者を往復できる' do
    exchange = create(:exchange)
    user = create(:user)
    participation = create(:participation, exchange:, user:)

    expect(participation.exchange).to eq(exchange)
    expect(participation.user).to eq(user)
    expect(exchange.participations).to include(participation)
    expect(user.participations).to contain_exactly(participation)
  end

  it '同じ参加者が同じ交換会に二重に参加できない' do
    participation = create(:participation)

    expect { create(:participation, exchange: participation.exchange, user: participation.user) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it '同じ参加者が別の交換会には参加できる' do
    user = create(:user)
    create(:participation, user:)

    expect { create(:participation, user:) }.not_to raise_error
  end

  it '消すと登録した本と、その本への希望・割当まで消える' do
    exchange = create(:exchange)
    owner = create(:participation, exchange:)
    other = create(:participation, exchange:)
    book = create(:book, participation: owner)
    create(:wish, participation: other, book:)
    create(:assignment, book:, participation: other)

    owner.destroy

    expect(Book.count).to eq(0)
    expect(Wish.count).to eq(0)
    expect(Assignment.count).to eq(0)
    expect(other.reload).to be_persisted
  end

  it '消すと自分が出した希望と、自分が受け取る割当も消える' do
    exchange = create(:exchange)
    owner = create(:participation, exchange:)
    recipient = create(:participation, exchange:)
    book = create(:book, participation: owner)
    create(:wish, participation: recipient, book:)
    create(:assignment, book:, participation: recipient)

    recipient.destroy

    expect(Wish.count).to eq(0)
    expect(Assignment.count).to eq(0)
    expect(book.reload).to be_persisted
  end

  describe '.with_counts' do
    let!(:exchange) { create(:exchange) }
    let!(:participation) { create(:participation, exchange:) }
    let!(:other) { create(:participation, exchange:) }

    it '登録冊数と希望冊数を数える' do
      create_list(:book, 2, participation:)
      create_list(:book, 3, participation: other)
      exchange.books.where(participation: other).each_with_index do |book, index|
        create(:wish, participation:, book:, position: index + 1)
      end

      row = exchange.participations.with_counts.find(participation.id)

      expect(row.books_count).to eq(2)
      expect(row.wishes_count).to eq(3)
    end

    it '1冊も登録せず希望も出していなければ0を返す' do
      row = exchange.participations.with_counts.find(participation.id)

      expect(row.books_count).to eq(0)
      expect(row.wishes_count).to eq(0)
    end

    # Book と Wish を同時に外部結合すると、片方の行数がもう片方を水増しする。
    # 掛け合わさった行をそのまま数えると、2冊×3希望が6と6になる
    it 'Book と Wish の両方があっても互いの件数を水増ししない' do
      create_list(:book, 2, participation:)
      exchange.books.where(participation: other).destroy_all
      books = create_list(:book, 3, participation: other)
      books.each_with_index { |book, index| create(:wish, participation:, book:, position: index + 1) }

      row = exchange.participations.with_counts.find(participation.id)

      expect(row.books_count).to eq(2)
      expect(row.wishes_count).to eq(3)
    end

    # ギフトコードの取得経路は1つに限る（CLAUDE.md）。冊数を出すだけの画面が
    # Book を引くと、暗号化された値が画面の裏側まで運ばれてくる。
    # 人数ぶんの追い引きが起きないことも、同じ1本の問い合わせで担保される
    it 'Book にも Wish にも問い合わせず1回で引く' do
      create_list(:book, 2, participation:)
      create_list(:book, 2, participation: other)

      queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        queries << payload[:sql] unless payload[:name] == 'SCHEMA'
      end
      exchange.participations.with_counts.to_a
      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(queries.size).to eq(1)
    end
  end

  describe '結果画面が引く割当' do
    let!(:exchange) { create(:exchange) }
    let!(:participation) { create(:participation, exchange:) }
    let!(:other) { create(:participation, exchange:) }

    def receive_from(owner, round:)
      book = create(:book, participation: owner)
      create(:assignment, book:, participation:, round:, returned: false)
    end

    it '受け取った本と、返却された自分の本を分けて引く' do
      received = receive_from(other, round: 1)
      mine = create(:book, participation:)
      returned = create(:assignment, book: mine, participation:, round: nil, returned: true)

      expect(participation.received_assignments).to contain_exactly(received)
      expect(participation.returned_assignments).to contain_exactly(returned)
    end

    it '他人の割当は引かない' do
      book = create(:book, participation:)
      create(:assignment, book:, participation: other, returned: false)

      expect(participation.received_assignments).to be_empty
      expect(participation.returned_assignments).to be_empty
    end

    # 余り物の割当は巡を持たない。ドラフトで取れた本のあとに並べないと、
    # 希望の上位から順に並んでいるという読み方が崩れる
    it '受け取った本はドラフトの巡の順に並び、余り物の割当は最後になる' do
      leftover = receive_from(other, round: nil)
      second = receive_from(other, round: 2)
      first = receive_from(other, round: 1)

      expect(participation.received_assignments).to eq([first, second, leftover])
    end
  end

  describe '希望リストの操作' do
    let!(:exchange) do
      create(
        :exchange,
        registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
        registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
        wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone
      )
    end
    let!(:participation) { create(:participation, exchange:) }
    # 希望の対象は他人が登録した本。同じ人が登録した3冊を並べても、
    # 確かめたいのは順位の扱いなので足りる
    let!(:books) { create_list(:book, 3, participation: create(:participation, exchange:)) }
    let!(:book) { books.first }

    let!(:wish_phase) { '2026-08-11T00:00:00+09:00'.in_time_zone }

    describe '#add_wish!' do
      it '希望リストの末尾に足す' do
        first = participation.add_wish!(books[0], at: wish_phase)
        second = participation.add_wish!(books[1], at: wish_phase)

        expect(first.position).to eq(1)
        expect(second.position).to eq(2)
      end

      # 二重送信や、同時に届いた2つのリクエストで希望が2つできないこと。
      # 一意インデックスの違反を拾って既存を引くため、2回目もこの経路をそのまま通る
      it '二度足しても希望は増えず、同じものを返す' do
        first = participation.add_wish!(book, at: wish_phase)
        second = participation.add_wish!(book, at: wish_phase)

        expect(second).to eq(first)
        expect(participation.wishes.count).to eq(1)
      end

      it '登録期間には足せない' do
        expect { participation.add_wish!(book, at: '2026-08-04T00:00:00+09:00'.in_time_zone) }
          .to raise_error(Exchange::PhaseViolation)
        expect(participation.wishes.count).to eq(0)
      end

      it '希望提出の締切ちょうどからは足せない' do
        expect { participation.add_wish!(book, at: '2026-08-15T00:00:00+09:00'.in_time_zone) }
          .to raise_error(Exchange::PhaseViolation)
      end

      it '自分が登録した本は足せない' do
        own = create(:book, participation:)

        expect { participation.add_wish!(own, at: wish_phase) }
          .to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    describe '#remove_wish!' do
      before { books.each { |b| participation.add_wish!(b, at: wish_phase) } }

      it '希望を消す' do
        participation.remove_wish!(book, at: wish_phase)

        expect(participation.wishes.reload.map(&:book)).to eq(books.drop(1))
      end

      # 穴が空いたままだと、次に足した1冊の順位が飛ぶ。
      # 画面に出す順位と、リストの何番目かが食い違う
      it '真ん中を消すと順位が1からの連番に詰め直される' do
        participation.remove_wish!(books[1], at: wish_phase)

        expect(participation.wishes.reload.pluck(:position)).to eq([1, 2])
        expect(participation.wishes.map(&:book)).to eq([books[0], books[2]])
      end

      # 二度押しや、別のタブで消したあとの再送信で落とすようなことではない
      it '希望していない本を渡しても落ちない' do
        other = create(:book, participation: book.participation)

        expect { participation.remove_wish!(other, at: wish_phase) }
          .not_to(change { participation.wishes.count })
      end

      it '希望提出の締切ちょうどからは消せない' do
        expect { participation.remove_wish!(book, at: '2026-08-15T00:00:00+09:00'.in_time_zone) }
          .to raise_error(Exchange::PhaseViolation)
        expect(participation.wishes.count).to eq(3)
      end
    end

    describe '#reorder_wishes!' do
      before { books.each { |b| participation.add_wish!(b, at: wish_phase) } }

      it '渡された順に並べ替える' do
        participation.reorder_wishes!([books[2].id, books[0].id, books[1].id], at: wish_phase)

        expect(participation.wishes.reload.map(&:book)).to eq([books[2], books[0], books[1]])
        expect(participation.wishes.pluck(:position)).to eq([1, 2, 3])
      end

      # 並びはフォームから来るので、値は文字列で届く
      it '文字列の id でも並べ替えられる' do
        participation.reorder_wishes!(books.reverse.map { |b| b.id.to_s }, at: wish_phase)

        expect(participation.wishes.reload.map(&:book)).to eq(books.reverse)
      end

      # 集合が食い違うのは、別のタブで追加・削除したときだけ。
      # 黙って片方を捨てるより、読み直させるほうが安全
      it '希望していない本が混じっていれば拒否する' do
        other = create(:book, participation: book.participation)

        expect { participation.reorder_wishes!(books.map(&:id) + [other.id], at: wish_phase) }
          .to raise_error(Participation::WishListMismatch)
      end

      it '希望が欠けていれば拒否し、並びも変えない' do
        expect { participation.reorder_wishes!([books[2].id, books[0].id], at: wish_phase) }
          .to raise_error(Participation::WishListMismatch)
        expect(participation.wishes.reload.map(&:book)).to eq(books)
      end

      it '同じ本が二度現れれば拒否する' do
        expect { participation.reorder_wishes!([books[0].id, books[0].id, books[1].id], at: wish_phase) }
          .to raise_error(Participation::WishListMismatch)
      end

      it '希望提出の締切ちょうどからは並べ替えられない' do
        at = '2026-08-15T00:00:00+09:00'.in_time_zone

        expect { participation.reorder_wishes!(books.reverse.map(&:id), at:) }
          .to raise_error(Exchange::PhaseViolation)
        expect(participation.wishes.reload.map(&:book)).to eq(books)
      end
    end
  end
end
