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

  # Entries newer than the given version (1.0.x). Versions used to be dates (YYYY.MM.DD[.n]), and a
  # device may still have one saved, so those compare by date.
  def self.since(version)
    version = version.to_s
    if (date = version[/\A\d{4}\.\d{2}\.\d{2}/])
      entries.select { |e| e.date > Date.strptime(date, "%Y.%m.%d") }
    elsif Gem::Version.correct?(version)
      entries.select { |e| Gem::Version.new(e.version) > Gem::Version.new(version) }
    else
      []
    end
  end
end
