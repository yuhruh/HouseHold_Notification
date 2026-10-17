namespace :import do
  desc "Parse a sheet CSV export and print errors/warnings without writing anything (CSV=path)"
  task dry_run: :environment do
    path = ENV["CSV"] or abort "Usage: bin/rails import:dry_run CSV=path/to/export.csv"
    result = SheetImport::Parser.new(File.read(path, encoding: "bom|utf-8")).call
    puts SheetImport::DryRunReport.new(result)
    exit(result.ok? ? 0 : 1)
  end
end
