# frozen_string_literal: true

require 'net/http'

module Notifications
  # 交換会に設定された Webhook へ本文を投稿する。
  #
  # 交換会から読むのは URL だけで、本文は呼ぶ側（#43 #44）が組んだものをそのまま投げる。
  # ここで交換会の中身を足せるようにすると、文面を組む側が除いたはずのものが
  # 送信側で戻ってくる。ギフトコードを含めない責任は文面の側にある。
  # 本文とギフトコードを突き合わせる検査は置かない。平文の取得経路を
  # Book#gift_code_for の1つに保つため（docs/spec.md 8.）、
  # 照合のために2つ目の復号経路を作ることになるほうが危うい
  class Webhook
    # 送り先ごとの作法を、送り方から切り離して置く。送り方（https の限定、失敗の
    # 分け方、例外に URL を書かないこと）はどの送り先でも同じでなければ困るため。
    # リンクの記法が Discord と Slack で割れたとき（#43）に足す先もここになる
    Format = Data.define(:name, :body_key) do
      def payload(text)
        { body_key => text }
      end
    end

    DISCORD = Format.new(name: :discord, body_key: 'content')
    SLACK = Format.new(name: :slack, body_key: 'text')

    # 交換会は URL を1つしか持たないので、形式を選ばせる項目は要らない。
    # ホストと作法を別の表に分けると、送り先を足す人が片方だけを直したときに、
    # 起動時には何も起きず、送信のときになって初めて落ちる
    FORMATS = {
      'discord.com' => DISCORD,
      'discordapp.com' => DISCORD,
      'hooks.slack.com' => SLACK,
    }.freeze

    # 通知が遅れて困るものではない。相手が黙り込んだときに、
    # ジョブのスレッドを長く握らせない
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5

    class Error < StandardError; end
    class TransientFailure < Error; end
    class PermanentFailure < Error; end

    # 呼ぶ側それぞれに URL の有無と対応可否を書かせない。
    # 未設定は異常ではない。通知は交換会ごとの任意の設定にあたる
    def self.for(exchange)
      uri = parse(exchange.webhook_url)
      return nil if uri.nil?

      format = FORMATS[uri.host]
      return nil if format.nil?

      new(uri:, format:)
    end

    # URL にはトークンが載る。平文で流れる経路には投げないため https に限る
    def self.parse(url)
      return nil if url.blank?

      uri = URI.parse(url)
      uri.is_a?(URI::HTTPS) ? uri : nil
    rescue URI::InvalidURIError
      nil
    end
    private_class_method :parse

    attr_reader :format

    def initialize(uri:, format:)
      @uri = uri
      @format = format
    end

    # @raise [TransientFailure] 時間をおけば通りうる失敗
    # @raise [PermanentFailure] 待っても変わらない失敗
    def deliver(text)
      verify(post(text))
      nil
    end

    private

    def post(text)
      request = Net::HTTP::Post.new(@uri)
      request['Content-Type'] = 'application/json'
      request.body = @format.payload(text).to_json

      http.request(request)
    rescue Timeout::Error, IOError, SystemCallError, OpenSSL::SSL::SSLError, SocketError => e
      # つながらないのは相手か経路の一時的な事情のことが多い。積み直して待つ
      raise TransientFailure, "#{@uri.host} へ届かなかった: #{e.class}"
    end

    def http
      Net::HTTP.new(@uri.host, @uri.port).tap do |client|
        client.use_ssl = true
        client.open_timeout = OPEN_TIMEOUT
        client.read_timeout = READ_TIMEOUT
      end
    end

    # 失敗のメッセージにホストより先を出さない。URL のトークンは、
    # 例外がログとジョブの失敗の両方に残る以上、載せた時点で漏れたことになる
    def verify(response)
      return if response.is_a?(Net::HTTPSuccess)

      message = "#{@uri.host} が #{response.code} を返した"
      raise TransientFailure, message if retryable?(response)

      raise PermanentFailure, message
    end

    # 相手の不調（5xx）と流量の制限（429）は待てば変わる。
    # それ以外の 4xx と、想定していないリダイレクトは待っても変わらない
    def retryable?(response)
      response.is_a?(Net::HTTPServerError) || response.is_a?(Net::HTTPTooManyRequests)
    end
  end
end
