# frozen_string_literal: true

module BooksHelper
  # 削除の確認文。一覧と編集フォームの2か所から押せるので、文言をここへ集める。
  # 消えるのは本だけではない。取得枠が1つ減り、その本への他の人の希望も一緒に消える
  def book_deletion_confirm(book, slots:)
    t('book.deletion_confirm', title: book.title, before: slots, after: slots - 1)
  end
end
