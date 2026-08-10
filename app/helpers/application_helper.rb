# frozen_string_literal: true

module ApplicationHelper
  # 帯を出さない画面が宣言する。いまはログイン画面だけ。
  # まだ誰でもなく、行き先もログアウトも無いうえ、サービス名は画面自身が
  # 大きく名乗るので、帯を重ねると同じ名が上下に2つ並ぶ
  def hide_header!
    content_for :hide_header, 'true'
  end

  def header?
    !content_for?(:hide_header)
  end

  # 帯のパンくずに祖先を1つ足す。根の「読書交換会」は帯が自分で置くので、
  # ここへ渡すのはその先だけ。現在地は渡さない（h1 が名乗る）
  def breadcrumb_ancestor(label, path)
    tag.li(class: 'flex items-center gap-x-2') do
      safe_join([tag.span('／', class: 'text-ink-subtle', aria: { hidden: true }),
                 link_to(label, path)])
    end
  end
end
