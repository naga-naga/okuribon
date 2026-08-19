# frozen_string_literal: true

# 開発環境で5フェーズと状態バリエーションを一度に確かめるためのデータを作る。
#
# 現在時刻を差し替える仕組みは持たないため（docs/spec.md 11.）、見たい状況は
# 基準時刻からの相対で日時を決めて作る。交換会1つにシナリオ1つを持たせ、
# 何を見るための交換会かは名前が言う。名前に入り切らない細部は概要の末尾に書く。
#
# 二度目以降は日時が新しい基準時刻から数え直される。「締切まで残り数時間」は
# 放置すれば次のフェーズへ移るので、見たくなったらもう一度通す。
#
# 作った利用者は Google のアカウントを持たないため、本来の経路ではログインできない。
# 入れ替わりは /dev/login から行う。
class DevelopmentSeeds
  # 作った利用者の印。Google が返す provider と別にしておくと、
  # 本物のアカウントと取り違えない。uid の衝突も起きない
  PROVIDER = 'seed'

  # シナリオの主役。作ったデータは、この人として見ることを前提に組んである
  VIEWER_UID = 'you'

  # どこにも参加していない利用者。招待URLを渡される前の人にあたる
  OUTSIDER_UID = 'oda'

  # 主役の名前は人名の形を借りつつ、ほかの5人には混ざらない姓にする。
  #
  # 「あなた」にはできない。交換会一覧は主催者が自分のとき、名前の代わりに
  # 「あなた」と書く（docs/spec.md 6.6）。名前まで「あなた」だと、画面に出た
  # 「あなた」が置き換えの結果なのか名前そのものなのかを見分けられない。
  # ギフトコードの注記も「見えるのはあなたと あなた さんだけ」になる。
  # かといって普通の人名にすると、今度はほかの参加者と見分けが付かなくなる
  CAST = {
    VIEWER_UID => '開発たろう',
    'mochida' => '持田さくら',
    'kawai' => '川井たける',
    'shibata' => '芝田みのり',
    'aizawa' => '相沢ゆう',
    OUTSIDER_UID => '小田はるか',
  }.freeze

  # 通知の送信先（docs/spec.md 11.）。交換会は Webhook URL を1つしか持たないので、
  # Discord と Slack の両方の形式を手元で試すには、別々の交換会に入れる。
  # ホストは本物にして送信側の見分けを試せるようにし、ID とトークンは偽物にする。
  # 叩いても 404 が返るだけで、どこのチャンネルにも届かない
  DISCORD_WEBHOOK_URL = 'https://discord.com/api/webhooks/000000000000000000/not-a-real-token'
  SLACK_WEBHOOK_URL = 'https://hooks.slack.com/services/T00000000/B00000000/not-a-real-token'

  # タイトル、あらすじ、おすすめポイント。カードの見え方を確かめたいので、
  # 長さはばらつかせてある
  BOOKS = [
    ['夜明けの図書室',
     '閉館後の図書室に集まる四人の司書が、二十年前から返却されていない一冊を追う。',
     '最後の10ページで、それまでの静けさの意味が変わります'],
    ['コーヒーが冷めるまでに考えたこと',
     '喫茶店の常連たちが、それぞれ選ばなかったほうの道について語る短編集。',
     '一話が短いので、通勤の行き帰りに一話ずつ読めます'],
    ['海辺のキオスク',
     '廃線間際のローカル線と、駅の売店を四十年守り続けた祖母の記録。',
     '派手さはないけれど、読み終えたあと誰かに電話したくなります'],
    ['数式のない量子力学',
     '物理学者が、比喩と図だけで量子の世界を説明しきろうと試みた一冊。',
     '数学が苦手でも大丈夫です。とにかく図が親切'],
    ['引っ越し貧乏',
     '三十代で九回引っ越した著者による、住まいと身軽さをめぐる散文集。',
     '部屋探しの前に読むと、間取り図の見え方が変わります'],
    ['猫が二匹いる家',
     '保護猫を迎えた夫婦の、七年分の日記から抜き出した記録。',
     '猫を飼っていなくても読めます。人間のほうの話なので'],
    ['締切が来る前に',
     'フリーランス十年目のライターが書いた、働き方と時間の使い方の本。',
     '精神論が一切ないところが良いです'],
    ['ガラス職人の手帳',
     '明治から続く硝子工房の、四代目までの技術と暮らしをたどる。',
     '写真が多く、眺めているだけでも楽しい一冊'],
    ['誰も来ない山小屋',
     '冬季閉鎖中の山小屋を舞台にした、密室ではない密室ミステリ。',
     '犯人当てよりも、雪の描写を味わってほしいです'],
    ['味噌汁の科学',
     '出汁と塩分と温度から、毎朝の味噌汁を組み立て直す。',
     '読んだ翌朝から味が変わります。実用性が高い'],
    ['遠回りの地図',
     '旅先で道に迷った記録だけを集めた、風変わりな紀行文。',
     '目的地に着かない旅の話ばかりで、妙に落ち着きます'],
    ['拝啓、十年後のあなたへ',
     '往復書簡の形式だけで進む、二人の十年を追った小説。',
     '文体が少しずつ寄っていくところが見どころです'],
    ['図解 発酵のしくみ',
     '味噌、醤油、パン、酒。発酵食品を微生物の側から並べ直す。',
     '台所に置いておくと、失敗した理由が分かります'],
    ['静かな退職',
     '定年後の三年間を淡々と記録した、六十代の日記。',
     '何も起きないのに読めてしまう。文章の力です'],
  ].freeze

  # 作った主役。/dev/login と spec が、どれが主役かを決め打ちせずに引けるようにする
  def self.viewer
    User.find_by(provider: PROVIDER, uid: VIEWER_UID)
  end

  # 基準時刻は必須にする。作っている途中で時刻が進むと、同じ「3時間後」でも
  # 交換会ごとに数ミリ秒ずれた日時が入り、境界を見たいときに読みにくくなる
  def initialize(at:)
    @at = at
    @book_cursor = 0
    @exchanges = []
  end

  # 途中で落ちたときに、半端な交換会を残さない
  def call
    ActiveRecord::Base.transaction do
      @cast = CAST.to_h { |uid, display_name| [uid, find_or_create_user(uid, display_name)] }

      # 小田はるかはどの交換会にも入れない。交換会一覧の空状態（docs/spec.md 6.6）と、
      # 招待URL着地画面の「これから参加する」（6.7）は、参加していない人としてしか
      # 見られない。/dev/login でこの人になり、登録期間の交換会の招待URLを開く
      solo_preparing
      registration_without_books
      registration_in_progress
      registration_imbalanced
      registration_closing_soon
      wish_in_progress
      wish_closing_soon
      awaiting_matching
      published
      published_without_slots
      published_without_luck
      published_without_books

      mark_notified
    end
  end

  private

  # 通知を知らせ済みにしておく。ここで作るのは日時だけを過去に置いた作り物なので、
  # 記録が空のままだと予約（Notifications::NotifyPhaseChangeJob と
  # Notifications::RemindDeadlineJob）が一斉に走り、偽の Webhook URL への送信が積まれる。
  # 締切まで残り数時間の交換会をわざと作ってあるぶん、リマインドのほうも埋める。
  # マッチングを済ませたあとに呼ぶ。結果公開のフェーズは matched_at で決まる。
  # 手元で通知を試すときは、交換会の日時を動かせば新しい予約が積まれる
  def mark_notified
    @exchanges.each do |exchange|
      exchange.update!(notified_phase: exchange.phase(at: @at),
                       reminded_deadline_at: reminder_deadline(exchange))
    end
  end

  # 準備中の交換会が待っているのは締切ではなく登録期間の開始で、リマインドの対象では
  # ない。埋めると、登録期間に入ったあとの本物の締切まで黙らせることになる
  def reminder_deadline(exchange)
    phase = exchange.phase(at: @at)
    return nil unless Notifications::DeadlineReminder::REMINDABLE_PHASES.include?(phase)

    exchange.next_deadline(at: @at)
  end

  # 準備中。作った直後で、まだ誰も招待URLを踏んでいない。
  # docs/spec.md 9.「参加者が自分ひとりしかいない」
  def solo_preparing
    build_exchange(
      'solo-preparing',
      name: 'ひとりだけの準備中の交換会',
      description: "年末に集まる分です。詳細は追って。\n（開発用データ: 登録期間の開始まで3日。自分が主催で、本はまだ登録できない）",
      owner: viewer,
      registration_starts_at: @at + 3.days,
      registration_ends_at: @at + 10.days,
      wish_ends_at: @at + 17.days
    )
  end

  # docs/spec.md 9.「交換会に本が1冊も登録されていない」。
  # ビジュアルガイド「C 本が0冊」に合わせ、登録期間が始まった当日に置く
  def registration_without_books
    exchange = build_exchange(
      'registration-empty',
      name: '本が1冊もない交換会',
      description: "ミステリなら何でも。既読でも構いません。\n（開発用データ: 登録期間の初日。4人いるが、まだ誰も登録していない）",
      owner: member('mochida'),
      registration_starts_at: @at - 2.hours,
      registration_ends_at: @at + 13.days,
      wish_ends_at: @at + 20.days
    )

    join(exchange, [viewer, member('kawai'), member('shibata')])
  end

  # 本の一覧とカードの標準形。人数も冊数もばらつかせてある
  def registration_in_progress
    exchange = build_exchange(
      'registration',
      name: '登録期間のふつうの交換会',
      description: "Kindle のみ。1000円前後を目安に。\n（開発用データ: 本が集まってきた標準形。自分が主催。Discord の Webhook URL 入り）",
      owner: viewer,
      registration_starts_at: @at - 4.days,
      registration_ends_at: @at + 6.days,
      wish_ends_at: @at + 13.days,
      webhook_url: DISCORD_WEBHOOK_URL
    )

    you, sakura, takeru, minori =
      join(exchange, [viewer, member('mochida'), member('kawai'), member('shibata')])

    add_books(you, 2)
    add_books(sakura, 2)
    add_books(takeru, 1)
    add_books(minori, 2)
  end

  # 登録冊数の偏りの警告（docs/spec.md 6.8）。1人の登録冊数がほかの全員の合計を
  # 超えると、超えた分は誰にも渡す先がなく登録者へ返る。5冊対2冊で3冊が返る。
  #
  # 警告が出るのは主催者管理画面で、本を登録できるあいだだけなので、
  # 主役を主催者にしたうえで登録期間のなかばに置く。偏っているのは主役ではなく
  # 持田で、主催者が他人の冊数を見て打つ手を考える場面にあたる
  def registration_imbalanced
    exchange = build_exchange(
      'registration-imbalanced',
      name: '登録が偏っている交換会',
      description: "大きい判のものは送料にご注意を。\n（開発用データ: 持田さんが5冊、ほかが合わせて2冊。自分が主催で、管理画面に警告が出る）",
      owner: viewer,
      registration_starts_at: @at - 3.days,
      registration_ends_at: @at + 4.days,
      wish_ends_at: @at + 11.days
    )

    you, sakura, takeru = join(exchange, [viewer, member('mochida'), member('kawai')])

    add_books(sakura, 5)
    add_books(you, 1)
    add_books(takeru, 1)
  end

  # docs/spec.md 9.「期間の締切まで残り数時間」「自分がまだ1冊も登録していない」。
  # 取得枠は登録冊数と同数なので、このまま締切を迎えると1冊も受け取れない
  def registration_closing_soon
    exchange = build_exchange(
      'registration-closing',
      name: '登録の締切が迫っている交換会',
      description: "読まないまま持っている本を出しましょう。\n（開発用データ: 締切まで5時間20分。自分だけまだ登録していない）",
      owner: member('kawai'),
      registration_starts_at: @at - 6.days,
      # 端数のある残り時間にしておく。残り24時間を切ると分まで出す想定なので、
      # ちょうどの時刻だけで確かめると桁の出方に気付けない
      registration_ends_at: @at + 5.hours + 20.minutes,
      wish_ends_at: @at + 7.days
    )

    _you, takeru, sakura, minori =
      join(exchange, [viewer, member('kawai'), member('mochida'), member('shibata')])

    add_books(takeru, 2)
    add_books(sakura, 1)
    add_books(minori, 2)
  end

  # 希望リストの標準形。自分の希望が並んでいる状態
  def wish_in_progress
    exchange = build_exchange(
      'wish',
      name: '希望提出期間のふつうの交換会',
      description: "翻訳ものに限ります。国は問いません。\n（開発用データ: 自分の希望を4冊まで並べてある標準形）",
      owner: member('mochida'),
      registration_starts_at: @at - 12.days,
      registration_ends_at: @at - 2.days,
      wish_ends_at: @at + 5.days
    )

    you, sakura, takeru, minori =
      join(exchange, [viewer, member('mochida'), member('kawai'), member('shibata')])

    mine = add_books(you, 2)
    hers = add_books(sakura, 2)
    his = add_books(takeru, 2)
    theirs = add_books(minori, 1)

    add_wishes(you, hers + his)
    add_wishes(sakura, mine + theirs)
    add_wishes(takeru, mine)
  end

  # docs/spec.md 9.「希望リストが空のまま希望提出期間の締切が迫っている」。
  # ビジュアルガイドが最重要と書いている状態なので、そこに合わせて
  # 本12冊・取得枠2冊・希望0冊で作る。カードが12枚並ぶ一覧はここでしか見られない
  def wish_closing_soon
    exchange = build_exchange(
      'wish-closing',
      name: '希望を出さないまま締切が迫る交換会',
      description: "去年出た本を中心に。\n（開発用データ: 締切まで3時間8分。本が12冊並び、自分の希望リストだけ空）",
      owner: member('shibata'),
      registration_starts_at: @at - 14.days,
      registration_ends_at: @at - 4.days,
      wish_ends_at: @at + 3.hours + 8.minutes
    )

    you, minori, yuu, sakura, takeru =
      join(exchange,
           [viewer, member('shibata'), member('aizawa'), member('mochida'), member('kawai')])

    mine = add_books(you, 2)
    hers = add_books(minori, 3)
    theirs = add_books(yuu, 3)
    sakuras = add_books(sakura, 2)
    add_books(takeru, 2)

    # 自分だけが希望を出していない。他の4人は出し終えている
    add_wishes(minori, mine + theirs)
    add_wishes(yuu, mine + hers)
    add_wishes(sakura, hers + theirs)
    add_wishes(takeru, mine + sakuras)
  end

  # 希望提出が終わり、主催者がマッチングを実行するのを待っている。
  # 実行ボタン（#31）を押せるのは主催者なので、主役を主催者にしてある
  def awaiting_matching
    exchange = build_exchange(
      'awaiting',
      name: 'マッチングの実行を待つ交換会',
      description: "500ページ以上のものを1冊。\n（開発用データ: 希望提出は締め切り済み。自分が主催。Slack の Webhook URL 入り）",
      owner: viewer,
      registration_starts_at: @at - 21.days,
      registration_ends_at: @at - 11.days,
      wish_ends_at: @at - 1.day,
      webhook_url: SLACK_WEBHOOK_URL
    )

    you, sakura, takeru, yuu =
      join(exchange, [viewer, member('mochida'), member('kawai'), member('aizawa')])

    mine = add_books(you, 2)
    hers = add_books(sakura, 1)
    his = add_books(takeru, 2)
    theirs = add_books(yuu, 1)

    add_wishes(you, hers + his)
    add_wishes(sakura, mine + theirs)
    add_wishes(takeru, mine + hers)
    add_wishes(yuu, mine + his)
  end

  # 結果公開。docs/spec.md 9.「自分の本が返却された」。
  #
  # 返却は「誰にも渡せなかった本が登録者へ戻る」ことなので、狙って作るには
  # 空いた取得枠が登録者本人のものしか残らない形にする必要がある。
  # 3人のうち自分だけが3冊出し、川井が希望を出さないと、余った2冊のうち
  # 1冊は川井の枠へ回り、もう1冊は自分の枠しか残らず返却になる
  def published
    exchange = build_exchange(
      'published',
      name: '結果公開のふつうの交換会',
      description: "仕事で使えるものを。\n（開発用データ: 自分は2冊受け取り、出した本のうち1冊が返却されている）",
      owner: member('mochida'),
      registration_starts_at: @at - 40.days,
      registration_ends_at: @at - 30.days,
      wish_ends_at: @at - 20.days
    )

    you, sakura, takeru = join(exchange, [viewer, member('mochida'), member('kawai')])

    mine = add_books(you, 3)
    hers = add_books(sakura, 1)
    his = add_books(takeru, 1)

    add_wishes(you, hers + his)
    add_wishes(sakura, [mine.first])
    # 川井は希望を出さないまま締切を迎えた。取得枠が空くので、余り物の割当が回る

    # 実行日時はここで直に書かない。マッチングを通した結果として記録させる
    run_matching(exchange, at: @at - 19.days)
  end

  # 受け取りが0冊で、取得枠が0だった場合（docs/spec.md 6.5）。
  # 登録期間に1冊も登録しなければ取得枠は0になり、受け取る本が無い。
  # 言い分けの文面は主役にしか出ないので、0冊なのは主役でなければならない
  def published_without_slots
    exchange = build_exchange(
      'published-without-slots',
      name: '取得枠が0だった交換会',
      description: "作ったことのないものが載っている本を。\n（開発用データ: 自分は1冊も登録しなかったので、受け取る本がない）",
      owner: member('mochida'),
      registration_starts_at: @at - 34.days,
      registration_ends_at: @at - 26.days,
      wish_ends_at: @at - 18.days
    )

    _you, sakura, takeru, minori =
      join(exchange, [viewer, member('mochida'), member('kawai'), member('shibata')])

    hers = add_books(sakura, 2)
    his = add_books(takeru, 2)
    theirs = add_books(minori, 1)

    # 主役は登録も希望もしていない。取得枠が0なので、希望を出しても受け取れない
    add_wishes(sakura, his + theirs)
    add_wishes(takeru, hers + theirs)
    add_wishes(minori, hers + his)

    run_matching(exchange, at: @at - 17.days)
  end

  # 受け取りが0冊で、枠はあったのに回ってこなかった場合（docs/spec.md 6.5）。
  #
  # 総冊数と総取得枠は必ず等しいので、主役の枠が空いたまま終わるには、余った本が
  # 主役のものでなければならない。ほかの人の本が余れば、余り物の割当が空いた枠へ
  # 回してしまう。そのため、この状態には自分の本の返却が必ず伴う。
  #
  # 主役の本を誰も希望せず、ほかの4冊がドラフトで出払う形にする。希望リストを
  # 互いに重ならないように配ってあるのは、抽選順がどう出ても同じ結果にするため。
  # 重ねると、取り合いに負けた人の枠が空いて、余り物が主役へ回ることがある
  def published_without_luck
    exchange = build_exchange(
      'published-without-luck',
      name: '本が回ってこなかった交換会',
      description: "行ったことのない土地の本を。\n（開発用データ: 取得枠は1冊あったのに回ってこず、出した本が戻ってきた）",
      owner: member('kawai'),
      registration_starts_at: @at - 28.days,
      registration_ends_at: @at - 21.days,
      wish_ends_at: @at - 14.days
    )

    you, takeru, sakura, minori =
      join(exchange, [viewer, member('kawai'), member('mochida'), member('shibata')])

    add_books(you, 1)
    hers = add_books(sakura, 2)
    his = add_books(takeru, 2)
    theirs = add_books(minori, 1)

    add_wishes(sakura, his)
    add_wishes(takeru, [hers.first, *theirs])
    add_wishes(minori, [hers.last])

    run_matching(exchange, at: @at - 13.days)
  end

  # 誰も1冊も登録しないまま実行された交換会（docs/spec.md 9.）。
  # 結果画面の全体の成立結果が、節ごと畳まれることを確かめるための状態（6.5）。
  #
  # マッチング実行サービスは冊数を条件にしていない。拒むのは「そのフェーズでは
  # 書き込めない」ときだけなので（Matching::Execution）、0冊でも実行を通す。
  # 割当が1つも作られず、抽選順だけが記録される
  def published_without_books
    exchange = build_exchange(
      'published-without-books',
      name: '本が0冊のまま実行された交換会',
      description: "声をかけたものの、集まりませんでした。\n（開発用データ: 全体の結果が節ごと畳まれる。誰も1冊も登録しなかった）",
      owner: member('aizawa'),
      registration_starts_at: @at - 46.days,
      registration_ends_at: @at - 40.days,
      wish_ends_at: @at - 34.days
    )

    join(exchange, [viewer, member('aizawa'), member('shibata')])

    run_matching(exchange, at: @at - 33.days)
  end

  # 本番と同じ経路で割当を作る。返却を手で書くと本物と違う形のデータが残る。
  # マッチングは一度だけ実行できるもので、二度目の db:seed は実行のやり直しでは
  # ないため、割当は作り直さない。日時だけは新しい基準時刻から引き直す
  # （docs/spec.md 9.1）。実行済みのまま置くと、ほかの日時が動いたぶんだけ
  # 結果公開の日付が取り残される
  def run_matching(exchange, at:)
    return exchange.update!(matched_at: at) if exchange.matched_at.present?

    Matching::Execution.new(exchange:, at:).call
  end

  def viewer
    member(VIEWER_UID)
  end

  def member(uid)
    @cast.fetch(uid)
  end

  # 名前は二度目以降も書き直す。build_exchange が交換会の属性を毎回上書きするのと
  # 同じ扱いで、顔ぶれの名前を変えたときに、古い開発用データだけ前の名前で残らない
  def find_or_create_user(uid, display_name)
    user = User.find_or_initialize_by(provider: PROVIDER, uid:)
    user.update!(display_name:)

    user
  end

  # 招待トークンをここで決め打ちにして、二度目以降も同じ交換会を引けるようにする。
  # 開発中に招待URLが変わらない利点もある。乱数シードは作成時にモデルが発行し、
  # attr_readonly なので二度目以降も動かない
  def build_exchange(token, owner:, **attributes)
    exchange = Exchange.find_or_initialize_by(invite_token: "seed-#{token}")
    exchange.assign_attributes(owner:, **attributes)
    exchange.save!

    # 主催者は必ず参加者を兼ねる（docs/spec.md 2. 用語 / 6.9）。
    # DB の制約では守れないので、交換会を作る口をここ1つに絞って必ず通す
    join(exchange, [owner])

    @exchanges << exchange
    exchange
  end

  # 締切を過ぎた交換会も作るため join! は使えない。フェーズの検証は
  # 利用者の書き込みを止めるためのもので、開発用データを作る道ではない
  def join(exchange, users)
    users.map { |user| exchange.participations.create_or_find_by!(user:) }
  end

  def add_books(participation, count)
    Array.new(count) { add_book(participation) }
  end

  def add_book(participation)
    index = @book_cursor % BOOKS.size
    title, summary, recommendation = BOOKS[index]
    @book_cursor += 1

    participation.books.find_or_create_by!(title:) do |book|
      book.summary = summary
      book.recommendation = recommendation
      book.url = "https://example.com/books/#{index + 1}"
      book.gift_code = format('OKURIBON-%<index>04d-DEV', index:)
    end
  end

  # 順位は渡した並びのとおり、1から始まる連番にする
  def add_wishes(participation, books)
    books.each_with_index do |book, i|
      participation.wishes.find_or_create_by!(book:) { |wish| wish.position = i + 1 }
    end
  end
end
