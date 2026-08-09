# frozen_string_literal: true

module ResultsHelper
  # 贈り主の名前を並べる。同じ人から2冊受け取ることがあるので重複は畳む。
  # 読むより先に「誰から」が目に入るようにするための一文なので、
  # 冊数ではなく人を数える
  def result_sender_names(assignments)
    assignments.map { it.book.registrant.display_name }.uniq.map { "#{it} さん" }.join('、')
  end

  # 全体の一覧に出す受取人。返却は渡る先が無いので、名前の代わりにその旨を書く。
  # 空欄にすると、行を書き落としたように見える
  def result_recipient_name(book, viewer:)
    assignment = book.assignment
    return t('result.overall.returned') if assignment.nil? || assignment.returned?

    result_person_name(assignment.participation.user, viewer:)
  end

  # 自分の行だけは名前ではなく「あなた」にする。十数人が並ぶ表の中から
  # 自分の名前を探し直さずに済む
  def result_person_name(user, viewer:)
    user == viewer ? t('result.overall.you') : user.display_name
  end
end
