# frozen_string_literal: true

# 開発環境で5フェーズと状態バリエーションを確かめるためのデータを撒く。
# 中身は DevelopmentSeeds にある。ここへ直に書くと spec から呼べない。
#
#   bin/rails db:seed          撒く。二度目以降は日時だけが数え直される
#   bin/rails db:seed:replant  消してから撒き直す
#
# 撒いた利用者は Google のアカウントを持たないため、/dev/login から入れ替わる。

# 撒くのは development だけに限る。production を弾くだけでは足りない。
# db:prepare はデータベースを作ったときに seed も撒くため、CI のようにまっさらな
# test のデータベースを毎回作る環境では、rspec が始まる前に撒かれてしまう。
# 件数を数える spec が撒いた分だけずれて落ちる
if Rails.env.development?
  # 現在時刻は入口で1回だけ読む。撒いている途中で進むと、同じ「3時間後」でも
  # 交換会ごとに日時がずれる
  DevelopmentSeeds.new(at: Time.current).call

  $stdout.puts "交換会 #{Exchange.count} 件、利用者 #{User.count} 人を撒きました"
  $stdout.puts '開発用ログインは /dev/login から'
else
  # 黙って何もしないと、撒けたのかどうかが分からない。standard output ではなく
  # ログへ出す。撒かない環境で叩かれたことは、あとから追える場所に残っていればよい
  Rails.logger.warn("#{Rails.env} では seed を撒きません")
end
