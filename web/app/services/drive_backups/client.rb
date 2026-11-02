require "google/apis/drive_v3"

module DriveBackups
  # The few Drive calls a backup needs, with Google's errors turned into the ones a run handles
  class Client
    class NeedsReconnect < StandardError; end
    class StorageFull < StandardError; end

    FOLDER_TYPE = "application/vnd.google-apps.folder".freeze

    def initialize(refresh_token)
      @drive = Google::Apis::DriveV3::DriveService.new
      @drive.authorization = Google::Auth::UserRefreshCredentials.new(client_id: ENV["GOOGLE_DRIVE_CLIENT_ID"],
        client_secret: ENV["GOOGLE_DRIVE_CLIENT_SECRET"], refresh_token:, scope: Oauth::SCOPE)
    end

    def email = call { @drive.get_about(fields: "user(emailAddress)").user.email_address }

    # False when it was deleted or moved to the trash in Drive
    def exists?(id)
      call { !@drive.get_file(id, fields: "id,trashed").trashed }
    rescue Google::Apis::ClientError => e
      raise unless e.status_code == 404
      false
    end

    def find_folder(name) = folders_named(name).first

    # Only a fixed folder name is looked up, so nothing needs escaping in the query
    def folders_named(name)
      call { @drive.list_files(q: "name = '#{name}' and mimeType = '#{FOLDER_TYPE}' and trashed = false", fields: "files(id)", spaces: "drive").files.map(&:id) }
    end

    # Everything in a folder, except what's in the trash
    def children(parent)
      entries, page = [], nil
      loop do
        list = call { @drive.list_files(q: "'#{parent}' in parents and trashed = false", fields: "nextPageToken,files(id,name,mimeType,modifiedTime)", page_size: 1000, page_token: page, spaces: "drive") }
        entries.concat(list.files)
        page = list.next_page_token or return entries
      end
    end

    def folder?(entry) = entry.mime_type == FOLDER_TYPE

    def download(id, io)
      call { @drive.get_file(id, download_dest: io) }
      io.rewind
      io
    end

    def create_folder(name, parent: nil)
      file = Google::Apis::DriveV3::File.new(name:, mime_type: FOLDER_TYPE, parents: Array(parent))
      call { @drive.create_file(file, fields: "id").id }
    end

    def create_file(name, io, content_type:, parent:)
      file = Google::Apis::DriveV3::File.new(name:, parents: [ parent ])
      call { @drive.create_file(file, upload_source: io, content_type:, fields: "id").id }
    end

    def replace_file(id, name, io, content_type:)
      call { @drive.update_file(id, Google::Apis::DriveV3::File.new(name:), upload_source: io, content_type:, fields: "id").id }
    end

    private

    def call
      yield
    rescue Signet::AuthorizationError, Google::Apis::AuthorizationError => e
      raise NeedsReconnect, e.class.name
    rescue Google::Apis::ClientError => e
      raise StorageFull, "storageQuotaExceeded" if e.message.include?("storageQuotaExceeded")
      raise
    end
  end
end
