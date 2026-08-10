# frozen_string_literal: true

# 共通ヘッダーのパンくずを読む。画面ごとの spec が、その画面の祖先と行き先を
# 確かめるのに使う。ラベルと行き先を1つの期待値で書けるよう、対応表にして返す。
# 現在地はパンくずに入らない（画面の名前は h1 にある）ので、ここに並ぶのは祖先だけ
module BreadcrumbHelper
  def breadcrumb
    response.parsed_body.css('header nav a').to_h { [it.text, it['href']] }
  end
end

RSpec.configure do |config|
  config.include BreadcrumbHelper, type: :request
end
