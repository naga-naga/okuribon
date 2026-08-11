# frozen_string_literal: true

module BooksHelper
  # 結果公開後、カードの下段に出す1行（docs/spec.md 6.2）。渡った先だけを書く。
  # 何番目の希望で渡ったかは書かない。受け取った人の希望リストの中身にあたるうえ、
  # 順位が低いと渡った事実より順位のほうが目に残る（docs/spec.md 6.5）。
  # 割当を持たない本は返却として扱い、結果画面の全体一覧と読み方を揃える
  def book_result_line(book, viewer:)
    assignment = book.assignment
    registrant = book.registrant

    if assignment.nil? || assignment.returned?
      return t('book.result.returned_to_you') if registrant == viewer

      return t('book.result.returned', name: result_person_label(registrant, viewer:))
    end

    t('book.result.handover',
      from: result_person_label(registrant, viewer:),
      to: result_person_label(assignment.participation.user, viewer:))
  end

  # カードの面と輪郭。選べない本と返却された本は沈め、自分が受け取った本だけを
  # 松葉の輪郭で立てる。返却は失敗ではないので、取り消し線や禁止記号は使わない。
  # 自分の本は登録期間を過ぎても輪郭で見分けられるようにする
  def book_card_tone(dimmed:, received:, mine:)
    return 'border-line bg-surface-sunken' if dimmed
    return 'border-success bg-paper' if received

    "bg-paper #{mine ? 'border-line-strong' : 'border-line'}"
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
