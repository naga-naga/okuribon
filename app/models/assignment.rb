# frozen_string_literal: true

class Assignment < ApplicationRecord
  belongs_to :book
  belongs_to :participation

  # 返却フラグは false が正しい値なので presence では見られない。
  # 巡は余り物の割当で nil になるため、ここには並べない
  validates :returned, inclusion: { in: [true, false] }
end
