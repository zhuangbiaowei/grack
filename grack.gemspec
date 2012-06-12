# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.authors       = ["Scott Chacon"]
  gem.email         = ["schacon@gmail.com"]
  gem.description   = %q{Ruby/Rack Git Smart-HTTP Server Handler}
  gem.summary       = %q{Ruby/Rack Git Smart-HTTP Server Handler}
  gem.homepage      = "https://github.com/schacon/grack"

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- tests/*`.split("\n")
  gem.name          = "grack"
  gem.require_paths = ["lib"]
  gem.version       = "1.0.0"

  gem.add_development_dependency("mocha", "~> 0.11")
end
