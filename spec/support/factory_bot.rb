# spec 内で FactoryBot. を前置せずに create / build を呼べるようにする
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end
