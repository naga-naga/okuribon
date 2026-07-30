# frozen_string_literal: true

class Book < ApplicationRecord
  belongs_to :participation
  has_one :exchange, through: :participation
end
