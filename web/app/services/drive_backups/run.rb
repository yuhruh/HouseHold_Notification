module DriveBackups
  # One backup: the CSV of every bill, replaced each time, then the photos Drive doesn't have yet.
  # Files are never deleted from Drive. Each uploaded photo is remembered as it goes, so a run that
  # stops part way carries on from there next time.
  class Run
    TOP_FOLDER = "Household Tracker Backup".freeze
    BOM = "﻿".freeze # Excel reads the CSV as UTF-8 only with this

    def self.call(backup, client: Client.new(backup.refresh_token)) = new(backup, client).call

    def initialize(backup, client)
      @backup, @client = backup, client
      @household = backup.household
    end

    def call
      return unless claim

      begin
        prepare_folders
        upload_csv
        upload_photos
        @backup.update!(last_backup_at: Time.current, bills_count: records.size, photos_count: @backup.files.count, problem: nil)
      ensure
        DriveBackup.where(id: @backup.id).update_all(running_since: nil)
      end
    end

    private

    def claim
      @backup.with_lock do
        next false if @backup.running?
        @backup.update!(running_since: Time.current)
      end
    end

    def records
      @records ||= @household.records.includes(photos_attachments: :blob).to_a
    end

    # A folder removed in Drive took its files with it, so everything goes up again
    def prepare_folders
      return if @backup.folder_id && @client.exists?(@backup.folder_id)

      @backup.files.delete_all
      top = @client.find_folder(TOP_FOLDER) || @client.create_folder(TOP_FOLDER)
      @backup.update!(folder_id: @client.create_folder(@household.name, parent: top), csv_file_id: nil, folders: {})
    end

    def upload_csv
      io = StringIO.new(BOM + Records::CsvExport.new(records).to_csv)
      name = "#{@household.name} bills.csv"
      if @backup.csv_file_id && @client.exists?(@backup.csv_file_id)
        @client.replace_file(@backup.csv_file_id, name, io, content_type: "text/csv")
      else
        @backup.update!(csv_file_id: @client.create_file(name, io, content_type: "text/csv", parent: @backup.folder_id))
      end
    end

    def upload_photos
      done = @backup.files.pluck(:blob_id).to_set
      records.each do |record|
        record.photos.each_with_index do |photo, index|
          next if done.include?(photo.blob_id)
          @backup.reload # raises when disconnected meanwhile, which ends the run
          upload(record, photo, index + 1)
        end
      end
    end

    def upload(record, photo, number)
      name = "#{record.period} #{record.title} #{record.import_key || Records::CsvExport.app_key(record)} #{number}.jpg"
      id = photo.blob.open { |file| @client.create_file(name, file, content_type: photo.blob.content_type, parent: year_folder(record.period_year)) }
      @backup.files.create!(blob_id: photo.blob_id, drive_file_id: id)
    rescue ActiveStorage::FileNotFoundError => e
      # One lost file mustn't stop every other photo being backed up
      Sentry.capture_exception(e)
    end

    def year_folder(year)
      @backup.folders[year.to_s] ||= begin
        photos = @backup.folders["photos"] ||= @client.create_folder("Photos", parent: @backup.folder_id)
        @client.create_folder(year.to_s, parent: photos)
      end.tap { @backup.save! }
    end
  end
end
