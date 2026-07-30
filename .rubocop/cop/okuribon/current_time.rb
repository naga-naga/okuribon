# frozen_string_literal: true

module RuboCop
  module Cop
    module Okuribon
      # 現在時刻の取得を Current.time に一本化する。
      #
      # フェーズを日時から導出するため、開発中に時刻を前後させられる経路を通す必要がある。
      # rubocop-rails の Rails/TimeZone と Rails/Date はタイムゾーン非対応の書き方だけを潰し、
      # Time.current や Time.zone.now はむしろ推奨するため、この cop で塞ぐ。
      #
      # @example
      #   # bad
      #   Time.current
      #   Time.zone.now
      #   Date.today
      #
      #   # good
      #   Current.time
      class CurrentTime < Base
        MSG = '現在時刻は `Current.time` から取得する。'

        RESTRICT_ON_SEND = [:now, :current, :today].freeze

        # Time / Date / DateTime を直接読む形と、Time.zone を経由する形の両方を拾う
        def_node_matcher :direct_clock_read?, <<~PATTERN
          (send
            {
              (const {nil? cbase} {:Time :Date :DateTime})
              (send (const {nil? cbase} :Time) :zone)
            }
            _)
        PATTERN

        def on_send(node)
          add_offense(node) if direct_clock_read?(node)
        end
      end
    end
  end
end
