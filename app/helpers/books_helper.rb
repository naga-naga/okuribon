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

  # 絞り込みの1区画。今どちらを見ているかを面で示す。
  # 文字の色だけで分けると、2つ並んだときにどちらが効いているのか読み取れない
  def book_filter_segment_class(selected)
    base = 'px-3.5 py-2.5 text-[12.5px] no-underline'

    selected ? "#{base} bg-accent font-medium text-paper" : "#{base} bg-paper text-ink hover:bg-paper-hover"
  end

  # ストアへのリンク。登録者が書いた URL をそのままリンクにするので、
  # http と https 以外は開かない。javascript: を書いて登録されると、
  # 読み比べに来た参加者のブラウザでそのまま走る。
  # リンクにしないものは nil を返し、呼ぶ側に判定を書かせない
  def book_store_url(book)
    uri = URI.parse(book.url.to_s)

    uri.to_s if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  # 削除の確認文。一覧と編集フォームの2か所から押せるので、文言をここへ集める。
  # 消えるのは本だけではない。取得枠が1つ減り、その本への他の人の希望も一緒に消える
  def book_deletion_confirm(book, slots:)
    t('book.deletion_confirm', title: book.title, before: slots, after: slots - 1)
  end
end
