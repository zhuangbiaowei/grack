require 'rack/builder'
require 'grack/auth'
require 'grack/server'

module Grack
  module Bundle
    extend self

    @@__instance__ = nil
    @@__config__ = YAML.load_file("config/grack.yml")

    def new
      return @@__instance__ if @@__instance__
      @@__instance__ = Rack::Builder.new do
        use Grack::Auth do |username, password|
          false
        end

        run Grack::Server.new(@@__config__)
      end
    end
  end
end
