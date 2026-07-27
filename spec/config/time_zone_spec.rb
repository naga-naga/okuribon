require "rails_helper"

# 交換会のフェーズはすべて日時から導出されるため、
# タイムゾーンの設定が崩れると仕様全体が壊れる。ここで固定しておく。
RSpec.describe "タイムゾーンの設定" do
  it "アプリケーションのタイムゾーンが JST である" do
    expect(Rails.application.config.time_zone).to eq("Tokyo")
    expect(Time.zone.name).to eq("Tokyo")
  end

  it "DB へは UTC で保存する" do
    expect(ActiveRecord.default_timezone).to eq(:utc)
  end
end
