# frozen_string_literal: true

require 'rails_helper'

# 通知はジョブとして走る。設定ファイルの誤りは Puma を起動するまで
# 分からず、起動しても supervisor のログにしか出ない。ここで固定しておく。
RSpec.describe 'Solid Queue の設定' do
  it 'ワーカーとディスパッチャの構成が読める' do
    configuration = SolidQueue::Configuration.new

    expect(configuration).to be_valid, -> { configuration.errors.full_messages.join("\n") }
    expect(configuration.configured_processes).not_to be_empty
  end

  it 'ジョブのテーブルを主のデータベースと分けている' do
    queue = SolidQueue::Record.connection_db_config
    primary = ApplicationRecord.connection_db_config

    expect(queue.name).to eq('queue')
    expect(queue.database).not_to eq(primary.database)
  end

  # recurring.yml は環境ごとに節が分かれ、実行時に読まれるのは自分の節だけになる。
  # 定期実行が要るのは production なので、test 環境から全部の節を検査する
  describe '定期実行の定義' do
    subject(:definitions) do
      YAML.safe_load(ERB.new(Rails.root.join('config/recurring.yml').read).result, aliases: true)
    end

    it '開発と本番の両方にある' do
      expect(definitions['development']).to be_present
      expect(definitions['production']).to be_present
    end

    it 'すべて定期実行として読める' do
      definitions.each do |environment, tasks|
        tasks.each do |key, options|
          task = SolidQueue::RecurringTask.from_configuration(key, **options.symbolize_keys)

          expect(task).to be_valid, -> { "#{environment} の #{key}: #{task.errors.full_messages.join(', ')}" }
          expect(task.next_time).to be_present
        end
      end
    end
  end

  describe 'ジョブの積まれ方' do
    before do
      stub_const('EchoJob', Class.new(ApplicationJob) do
        cattr_accessor :performed, default: []

        def perform(word)
          self.class.performed << word
        end
      end)
    end

    # 積んだ時点で走ってしまうと、通知の spec が「送ろうとしたこと」を検査できなくなる
    it 'test 環境では積むだけのアダプタを使う' do
      expect(ActiveJob::Base.queue_adapter).to be_a(ActiveJob::QueueAdapters::TestAdapter)
    end

    context '積んだだけのとき' do
      include ActiveJob::TestHelper

      it '実行されないまま待つ' do
        expect { EchoJob.perform_later('こんにちは') }.to have_enqueued_job(EchoJob).with('こんにちは')
        expect(EchoJob.performed).to be_empty
      end

      it '明示的に回せば実行される' do
        perform_enqueued_jobs { EchoJob.perform_later('こんにちは') }

        expect(EchoJob.performed).to eq(['こんにちは'])
      end
    end

    context 'Solid Queue のアダプタで積んだとき' do
      before { EchoJob.queue_adapter = :solid_queue }

      it 'ワーカーが拾える実行待ちの行になる' do
        expect { EchoJob.perform_later('こんにちは') }.to change(SolidQueue::ReadyExecution, :count).by(1)

        job = SolidQueue::Job.last
        expect(job.class_name).to eq('EchoJob')
        expect(job.arguments['arguments']).to eq(['こんにちは'])
      end
    end
  end
end
