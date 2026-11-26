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
  # device may still have one saved, so those compare by date. The given version comes from anyone's
  # request, so it's compared as numbers and never handed to Gem::Version.new, which keeps every string
  # it's given for the life of the process.
  def self.since(version)
    version = version.to_s
    if (date = version[/\A\d{4}\.\d{2}\.\d{2}/])
      entries.select { |e| e.date > Date.strptime(date, "%Y.%m.%d") }
    elsif (numbers = version.strip).match?(/\A(\d+(\.\d+)*)?\z/)
      seen = numbers.split(".").map(&:to_i)
      entries.select { |e| newer?(e.version.split(".").map(&:to_i), seen) }
    else
      []
    end
  end

  # Like Gem::Version for numbers only: a missing number counts as 0, so 1.0 and 1.0.0 are the same
  def self.newer?(numbers, than)
    width = [ numbers.size, than.size ].max
    (numbers + [ 0 ] * (width - numbers.size) <=> than + [ 0 ] * (width - than.size)) == 1
  end
  private_class_method :newer?
end
