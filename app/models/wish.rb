# frozen_string_literal: true

class Wish < ApplicationRecord
  belongs_to :participation
  belongs_to :book
end
