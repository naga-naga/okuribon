# frozen_string_literal: true

# アプリ全体で唯一の現在時刻の取得元。
# フェーズは日時から導出されるため、開発中に時刻を前後させられないと画面の確認ができない。
# 直接 Time.zone.now を呼ばず、必ずここを通す（禁止は Okuribon/CurrentTime cop で機械的に検出する）。
class Current < ActiveSupport::CurrentAttributes
  attribute :time

  # 書き込まれていなければ実時刻を返す。
  # 代入された値は JST へ寄せる（開発環境で UTC の値を入れても表示がずれないようにする）。
  def time
    super&.in_time_zone || Time.zone.now
  end
end
