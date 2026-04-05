source "https://rubygems.org"

gemspec

gem "ruby-mana", path: "../ruby-mana"
gem "base64"  # extracted from stdlib in Ruby 3.4, needed by marshal-md

group :development, :test do
  gem "rspec", "~> 3.0"
  gem "webmock", "~> 3.0"
  gem "simplecov", require: false
end
