module DriveBackups
  # Brings a ledger back from its Drive folder: the CSV through the normal import, then each photo
  # onto the bill named in its filename. Nothing in Drive is changed, and later backups carry on in
  # the same folder. Photos go through the normal upload, whose duplicate check makes a run that
  # stopped part way safe to repeat.
  class Restore
    Plan = Data.define(:preview, :failed, :photos, :matched)
    # Upload reads these from a browser's file
    File = Data.define(:tempfile, :original_filename) do
      def size = tempfile.size
    end

    def self.read_csv(client, id) = client.download(id, StringIO.new).string.force_encoding("UTF-8")

    # Every photo, in folders of any age, as [entry, year folder]
    def self.photos(client, folder_id)
      photos = client.children(folder_id).find { client.folder?(it) && it.name == "Photos" } or return []
      client.children(photos.id).select { client.folder?(it) }.flat_map do |year|
        client.children(year.id).reject { client.folder?(it) }.map { [ it, year ] }
      end
    end

    # "2026 9月 AC cleaning app-12 1.jpg" → "app-12"
    def self.key_of(name) = name[/\s(\S+)\s\d+\.\w+\z/, 1]

    # Step 2: nothing is written except the import preview
    def self.plan(backup, found, client: Client.new(backup.refresh_token))
      csv = read_csv(client, found["csv_id"])
      preview, failed = Imports::Planner.new(household: backup.household, user: backup.connected_by, csv:, filename: "Google Drive").call
      keys = preview ? preview.rows.map { it["key"] }.to_set : Set.new
      photos = photos(client, found["folder_id"])
      Plan.new(preview:, failed:, photos: photos.size, matched: photos.count { |entry, _| keys.include?(key_of(entry.name)) })
    end

    def self.call(backup, client: Client.new(backup.refresh_token)) = new(backup, client).call

    def initialize(backup, client)
      @backup, @client = backup, client
    end

    def call
      photos = self.class.photos(@client, @backup.folder_id)
      records = @backup.household.records.where.not(import_key: nil).index_by(&:import_key)
      @backup.update!(restore_total: photos.size, restore_done: 0, restore_unmatched: 0, folders: remembered_folders(photos))
      photos.each { |entry, _| restore(entry, records[self.class.key_of(entry.name)]) }
      @backup.update!(restore_state: "finished")
    end

    private

    # So the next backup uses these folders instead of making new ones
    def remembered_folders(photos)
      parent = @client.children(@backup.folder_id).find { it.name == "Photos" }
      photos.map(&:last).uniq(&:id).to_h { [ it.name, it.id ] }.merge(parent ? { "photos" => parent.id } : {})
    end

    def restore(entry, record)
      return @backup.increment!(:restore_unmatched, touch: true) unless record

      Tempfile.create([ "restore", ".jpg" ], binmode: true) do |file|
        @client.download(entry.id, file)
        known = record.photos.pluck(:blob_id)
        Photos::Upload.attach(record, [ File.new(tempfile: file, original_filename: entry.name) ])
        (record.reload.photos.pluck(:blob_id) - known).each { |blob_id| @backup.files.create!(blob_id:, drive_file_id: entry.id) }
      end
      @backup.increment!(:restore_done, touch: true)
    rescue Photos::Upload::Error
      @backup.increment!(:restore_unmatched, touch: true)
    end
  end
end
