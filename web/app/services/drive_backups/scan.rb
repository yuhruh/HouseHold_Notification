require "csv"

module DriveBackups
  # What a fresh connection can see of earlier backups. Called when an empty ledger connects, so the
  # owner can restore: after a lost database, Drive is the only record of where the backups are.
  class Scan
    def self.call(client) = new(client).call

    def initialize(client)
      @client = client
    end

    def call
      ledgers = @client.folders_named(Run::TOP_FOLDER).flat_map { |top| @client.children(top) }.select { @client.folder?(it) }
      ledgers.filter_map { |ledger| found(ledger) }.sort_by { -Time.zone.parse(it["saved_at"]).to_i }
    end

    private

    def found(ledger)
      entries = @client.children(ledger.id)
      csv = entries.find { !@client.folder?(it) && it.name.end_with?(".csv") } or return
      bills = [ CSV.parse(Restore.read_csv(@client, csv.id)).size - 2, 0 ].max
      return if bills.zero?

      { "folder_id" => ledger.id, "name" => ledger.name, "csv_id" => csv.id, "saved_at" => csv.modified_time.to_s, "bills" => bills,
        "photos" => Restore.photos(@client, ledger.id).size }
    end
  end
end
