# Sheet import (PRD §9): upload → preview with choices → commit in one transaction; undo latest.
class ImportsController < ApplicationController
  include HouseholdScoped
  MAX_BYTES = 2.megabytes

  def new
    authorize :import
    @batches = Current.household.import_batches.includes(:created_by).order(id: :desc).limit(10)
  end

  def create
    authorize :import
    file = params[:file]
    csv = read_csv(file)
    return redirect_to(new_household_import_path(Current.household), alert: @upload_error) unless csv

    preview, @result = Imports::Planner.new(household: Current.household, user: Current.user, csv:,
      filename: file.original_filename.to_s.first(200)).call
    if preview
      redirect_to household_import_path(Current.household, preview)
    else
      render :failed, status: :unprocessable_content
    end
  end

  def show
    authorize :import
    @preview = Current.household.import_previews.pending.find(params[:id])
  end

  def commit
    authorize :import
    @preview = Current.household.import_previews.pending.find(params[:id])
    @preview.update!(choices: merged_choices(@preview))
    batch = Imports::Commit.call(@preview, user: Current.user)
    redirect_to household_records_path(Current.household),
      notice: t(".done", created: batch.created_count, updated: batch.updated_count, unchanged: batch.unchanged_count)
  rescue Imports::Commit::Aborted => e
    @error = e
    render :aborted, status: :unprocessable_content
  end

  def undo
    authorize :import
    batch = Current.household.import_batches.find(params[:id])
    return redirect_to(new_household_import_path(Current.household), alert: t(".not_latest")) unless batch.undoable?

    Imports::Undo.call(batch, user: Current.user)
    redirect_to new_household_import_path(Current.household), notice: t(".done")
  end

  private

  def read_csv(file)
    @upload_error = t("imports.create.no_file") and return unless file.respond_to?(:read)
    @upload_error = t("imports.create.too_large") and return if file.size > MAX_BYTES
    text = file.read.force_encoding(Encoding::UTF_8).delete_prefix("﻿")
    @upload_error = t("imports.create.not_utf8") and return unless text.valid_encoding?
    text
  end

  # Only the choice keys the preview offered are accepted
  def merged_choices(preview)
    choices = preview.choices.deep_dup
    submitted = params.fetch(:choices, {})
    category_ids = Current.household.categories.pluck(:id).map(&:to_s)
    submitted.fetch(:categories, {}).each_pair do |mapping, value|
      next unless choices["categories"].key?(mapping)
      value = value.to_s
      choices["categories"][mapping] = value if category_ids.include?(value) || (value.start_with?("new:") && value.length > 4)
    end
    preview.rows_of("update").each do |row|
      row["fields"].select { |f| f["conflict"] }.each do |f|
        key = "#{row['line']}-#{f['field']}"
        choices["conflicts"][key] = submitted.dig(:conflicts, key) == "app" ? "app" : "sheet"
      end
    end
    preview.rows_of("deleted").each do |row|
      choices["deleted"][row["line"].to_s] = submitted.dig(:deleted, row["line"].to_s) == "recreate" ? "recreate" : "skip"
    end
    choices["chains"].each_with_index do |chain, index|
      action = submitted.dig(:chains, index.to_s, :action).to_s
      chain["action"] = action if %w[keep clear new_date].include?(action)
      chain["new_date"] = parse_date(submitted.dig(:chains, index.to_s, :new_date))
      chain["action"] = "clear" if chain["action"] == "new_date" && chain["new_date"].nil?
    end
    choices
  end

  def parse_date(text)
    Date.iso8601(text.to_s).iso8601
  rescue Date::Error
    nil
  end
end
