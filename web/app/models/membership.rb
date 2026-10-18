class Membership < ApplicationRecord
  belongs_to :household
  belongs_to :user

  enum :role, { owner: "owner", co_owner: "co_owner", viewer: "viewer" }, validate: true

  # Records, categories, templates, import (PRD §12)
  def can_write? = owner? || co_owner?
end
