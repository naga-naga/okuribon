# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../.rubocop/cop/okuribon/current_time'

RSpec.describe RuboCop::Cop::Okuribon::CurrentTime, :config do
  it 'Time.current を検出する' do
    expect_offense(<<~RUBY)
      Time.current
      ^^^^^^^^^^^^ 現在時刻は `Current.time` から取得する。
    RUBY
  end

  it 'Time.now を検出する' do
    expect_offense(<<~RUBY)
      Time.now
      ^^^^^^^^ 現在時刻は `Current.time` から取得する。
    RUBY
  end

  it 'Time.zone.now を検出する' do
    expect_offense(<<~RUBY)
      Time.zone.now
      ^^^^^^^^^^^^^ 現在時刻は `Current.time` から取得する。
    RUBY
  end

  it 'Time.zone.today を検出する' do
    expect_offense(<<~RUBY)
      Time.zone.today
      ^^^^^^^^^^^^^^^ 現在時刻は `Current.time` から取得する。
    RUBY
  end

  it 'Date.today を検出する' do
    expect_offense(<<~RUBY)
      Date.today
      ^^^^^^^^^^ 現在時刻は `Current.time` から取得する。
    RUBY
  end

  it 'Date.current を検出する' do
    expect_offense(<<~RUBY)
      Date.current
      ^^^^^^^^^^^^ 現在時刻は `Current.time` から取得する。
    RUBY
  end

  it 'DateTime.now を検出する' do
    expect_offense(<<~RUBY)
      DateTime.now
      ^^^^^^^^^^^^ 現在時刻は `Current.time` から取得する。
    RUBY
  end

  it 'トップレベル定数を明示しても検出する' do
    expect_offense(<<~RUBY)
      ::Time.current
      ^^^^^^^^^^^^^^ 現在時刻は `Current.time` から取得する。
    RUBY
  end

  it 'Current.time は許す' do
    expect_no_offenses('Current.time')
  end

  it '時刻の生成は許す' do
    expect_no_offenses('Time.zone.local(2026, 7, 30)')
  end

  it 'Time や Date 以外のレシーバは見ない' do
    expect_no_offenses('exchange.now')
  end
end
