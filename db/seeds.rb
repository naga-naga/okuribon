# frozen_string_literal: true

# 開発環境で5フェーズと状態バリエーションを確かめるためのデータを撒く。
# 中身は DevelopmentSeeds にある。ここへ直に書くと spec から呼べない。
#
#   bin/rails db:seed          撒く。二度目以降は日時だけが数え直される
#   bin/rails db:seed:replant  消してから撒き直す
#
# 撒いた利用者は Google のアカウントを持たないため、/dev/login から入れ替わる。

# 本番のデータベースへ架空の交換会を流し込まない。
# db:seed は db:setup からも呼ばれるので、手で叩かれる前提を置かない
if Rails.env.production?
  # 黙って何もしないと、撒けたのかどうかが分からない。standard output ではなく
  # ログへ出す。本番で叩かれたことは、あとから追える場所に残っていればよい
  Rails.logger.warn('production では seed を撒きません')
else
  # 現在時刻は入口で1回だけ読む。撒いている途中で進むと、同じ「3時間後」でも
  # 交換会ごとに日時がずれる
  DevelopmentSeeds.new(at: Time.current).call

  # spec が load_seed を呼ぶので、テストでは黙らせる
  unless Rails.env.test?
    $stdout.puts "交換会 #{Exchange.count} 件、利用者 #{User.count} 人を撒きました"
    $stdout.puts '開発用ログインは /dev/login から'
  end
end
