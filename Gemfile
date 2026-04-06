source "https://rubygems.org"

gemspec

if ENV["CI"]
  gem "ruby-mana", github: "twokidsCarl/ruby-mana", branch: "main"
else
  gem "ruby-mana", path: "../ruby-mana"
end
gem "base64"  # extracted from stdlib in Ruby 3.4, needed by marshal-md

group :development, :test do
  gem "rspec", "~> 3.0"
  gem "webmock", "~> 3.0"
  gem "simplecov", require: false
  gem "rack-test", "~> 2.0"
  gem "webrick"
end
