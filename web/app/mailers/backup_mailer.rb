# The weekly backup email to Alex (BackupJob)
class BackupMailer < ApplicationMailer
  def dump
    @filename = File.basename(params[:path])
    attachments[@filename] = { mime_type: "application/octet-stream", content: File.binread(params[:path]) }
    mail to: params[:to], subject: t(".subject", filename: @filename)
  end

  def too_large
    @filename = params[:filename]
    @size_mb = (params[:size].to_f / 1.megabyte).round(1)
    mail to: params[:to], subject: t(".subject", filename: @filename)
  end

  def photos_reminder
    @count, @size_mb = params[:count], params[:size_mb]
    mail to: params[:to], subject: t(".subject", count: @count)
  end
end
