# frozen_string_literal: true

module ResultsHelper
  # 贈り主の名前を並べる。同じ人から2冊受け取ることがあるので重複は畳む。
  # 読むより先に「誰から」が目に入るようにするための一文なので、
  # 冊数ではなく人を数える
  def result_sender_names(assignments)
    assignments.map { it.book.registrant.display_name }.uniq.map { "#{it} さん" }.join('、')
  end
end
