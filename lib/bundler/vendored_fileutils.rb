# frozen_string_literal: true
module Bundler; end
if RUBY_VERSION >= "2"
  require "bundler/vendor/fileutils/lib/fileutils"
else
  # the version we vendor is 2.0+
  require "fileutils"
end
