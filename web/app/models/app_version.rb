# The app's version and what's new (config/changelog.yml). The build changes on every deploy (Railway's
# commit SHA), so an open app notices a new deploy even when the changelog didn't change.
module AppVersion
  Entry = Data.define(:version, :date, :notes)

  def self.changelog
    @changelog ||= YAML.load_file(Rails.root.join("config/changelog.yml"), permitted_classes: [ Date ])
  end

  def self.entries(locale = I18n.locale)
    changelog.map { |e| Entry.new(version: e["version"], date: e["date"], notes: e[locale.to_s] || e["en"]) }
  end

  def self.current = changelog.first["version"]

  def self.build = ENV["RAILWAY_GIT_COMMIT_SHA"].presence&.first(12) || current

  # Entries newer than the given version (versions are YYYY.MM.DD[.n], so they sort as strings)
  def self.since(version) = entries.select { |e| e.version > version.to_s }
end
