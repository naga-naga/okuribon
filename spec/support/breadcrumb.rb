# frozen_string_literal: true

# 帯のパンくずを読む。画面ごとの spec が、その画面の祖先と行き先を確かめるのに使う。
# ラベルと行き先を1つの期待値で書けるよう、対応表にして返す。
# 現在地はパンくずに入らない（h1 が名乗る）ので、ここに並ぶのは祖先だけ
module BreadcrumbHelper
  def breadcrumb
    response.parsed_body.css('header nav a').to_h { [it.text, it['href']] }
  end
end

RSpec.configure do |config|
  config.include BreadcrumbHelper, type: :request
end
