# Stands in for DriveBackups::Client: keeps what would be in Drive, in memory
class FakeDrive
  attr_reader :folders, :files
  attr_accessor :email, :fail_with, :gone

  def initialize(email: "alex@example.com")
    @email, @folders, @files, @gone = email, {}, {}, []
  end

  def exists?(id) = !@gone.include?(id) && (@folders.key?(id) || @files.key?(id))
  def find_folder(name) = @folders.find { |_, folder| folder[:name] == name }&.first

  def create_folder(name, parent: nil)
    "folder-#{@folders.size + 1}".tap { |id| @folders[id] = { name:, parent: } }
  end

  def create_file(name, io, content_type:, parent:)
    raise @fail_with if @fail_with
    "file-#{@files.size + 1}".tap { |id| @files[id] = { name:, body: io.read, content_type:, parent: } }
  end

  def replace_file(id, name, io, content_type:)
    @files[id] = @files[id].merge(name:, body: io.read)
    id
  end

  def named(pattern) = @files.values.select { |file| file[:name].match?(pattern) }
  def path_of(id) = @folders[id]&.then { |folder| [ *path_of(folder[:parent]), folder[:name] ] }
end

module StubHelper
  # Swaps a class method for the block's duration; value may be a lambda
  def with_stub(object, name, value)
    original = object.method(name)
    object.define_singleton_method(name) { |*args, **options| value.respond_to?(:call) ? value.call(*args, **options) : value }
    yield
  ensure
    object.define_singleton_method(name, original)
  end
end

ActiveSupport.on_load(:active_support_test_case) { include StubHelper }
