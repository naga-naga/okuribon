# frozen_string_literal: true

FactoryBot.define do
  factory :wish do
    participation
    book
    sequence(:position, 1)
  end
end
