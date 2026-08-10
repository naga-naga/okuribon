# frozen_string_literal: true

module ApplicationHelper
  # 共通ヘッダーを出さない画面が宣言する。いまはログイン画面だけ。
  # まだ誰でもなく、行き先もログアウトも無い。加えて、この画面は
  # サービス名を見出しに大きく出すので、ヘッダーにも出すと同じ名が上下に2つ並ぶ
  def hide_header!
    content_for :hide_header, 'true'
  end

  def header?
    !content_for?(:hide_header)
  end

  # 共通ヘッダーのパンくずに、祖先を1つ足す。画面ごとに、根に近いほうから順に呼ぶ。
  # パンくずの先頭に来る「読書交換会」は共通ヘッダーが自分で描くため、
  # ここへ渡すのは2つ目以降だけ。現在地も渡さない。画面の名前は h1 にある
  def breadcrumb_ancestor(label, path)
    tag.li(class: 'flex items-center gap-x-2') do
      safe_join([tag.span('／', class: 'text-ink-subtle', aria: { hidden: true }),
                 link_to(label, path)])
    end
  end
end
