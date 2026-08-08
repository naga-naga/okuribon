# frozen_string_literal: true

module BooksHelper
  # 見出しに添える一文。フェーズごとに次にすることが変わる。
  # 待っている日時は next_deadline に任せる。フェーズと日時カラムの対応を
  # ここでもう一度書くと、片方だけ直したときに文と日付が食い違う
  def book_index_guide(exchange, at:)
    deadline = exchange.next_deadline(at:)

    t(exchange.phase(at:),
      scope: 'book.index_guides',
      at: deadline && l(deadline, format: :schedule))
  end

  # 削除の確認文。一覧と編集フォームの2か所から押せるので、文言をここへ集める。
  # 消えるのは本だけではない。取得枠が1つ減り、その本への他の人の希望も一緒に消える
  def book_deletion_confirm(book, slots:)
    t('book.deletion_confirm', title: book.title, before: slots, after: slots - 1)
  end
end
