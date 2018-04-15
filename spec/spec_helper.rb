require "bundler/setup"
require "refile_json"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

tmp_path = Dir.mktmpdir

at_exit do
  FileUtils.remove_entry_secure(tmp_path)
end

Refile.store = Refile::Backend::FileSystem.new(File.expand_path("default_store", tmp_path))
Refile.cache = Refile::Backend::FileSystem.new(File.expand_path("default_cache", tmp_path))

class FakePresignBackend < Refile::Backend::FileSystem
  def presign
    id = Refile::RandomHasher.new.hash
    Refile::Signature.new(as: "file", id: id, url: "/presigned/posts/upload", fields: { id: id, token: "xyz123" })
  end
end

Refile.secret_key = "144c82de680afe5e8e91fc7cf13c22b2f8d2d4b1a4a0e92531979b12e2fa8b6dd6239c65be28517f27f442bfba11572a8bef80acf44a11f465ba85dde85488d5"

Refile.backends["limited_cache"] = FakePresignBackend.new(File.expand_path("default_cache", tmp_path), max_size: 100)

Refile.allow_uploads_to = %w[cache limited_cache]

Refile.allow_origin = "*"

Refile.app_host = "http://localhost:56120"

# not included latest version...
module Refile
  class FileDouble
    attr_reader :original_filename, :content_type
    def initialize(data, name = nil, content_type: nil)
      @io = StringIO.new(data)
      @original_filename = name
      @content_type = content_type
    end

    extend Forwardable
    def_delegators :@io, :read, :rewind, :size, :eof?, :close
  end
end
