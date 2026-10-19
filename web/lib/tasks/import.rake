namespace :import do
  desc "Parse a sheet CSV export, run every Record validation in a rolled-back transaction and print errors/warnings (CSV=path)"
  task dry_run: :environment do
    path = ENV["CSV"] or abort "Usage: bin/rails import:dry_run CSV=path/to/export.csv"
    result = SheetImport::Parser.new(File.read(path, encoding: "bom|utf-8")).call
    SheetImport::DryRun.call(result)
    puts SheetImport::DryRunReport.new(result)
    exit(result.ok? ? 0 : 1)
  end
end
