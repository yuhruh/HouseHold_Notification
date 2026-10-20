# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_20_230000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "auth_handoffs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "provider", null: false
    t.string "purpose", default: "sign_in", null: false
    t.string "time_zone", null: false
    t.string "return_to"
    t.string "nonce_digest"
    t.bigint "user_id"
    t.datetime "requested_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_auth_handoffs_on_expires_at"
    t.index ["user_id"], name: "index_auth_handoffs_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "record_type", null: false
    t.string "name_zh", null: false
    t.string "name_en"
    t.string "detail_label_zh"
    t.string "detail_label_en"
    t.boolean "detail_required", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "record_type", "name_zh"], name: "index_categories_on_household_id_and_record_type_and_name_zh", unique: true
    t.index ["household_id"], name: "index_categories_on_household_id"
    t.check_constraint "record_type::text = ANY (ARRAY['expense'::character varying, 'maintenance'::character varying, 'tax'::character varying]::text[])", name: "categories_record_type"
  end

  create_table "category_aliases", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "category_id", null: false
    t.string "alias", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_category_aliases_on_category_id"
    t.index ["household_id", "alias"], name: "index_category_aliases_on_household_id_and_alias", unique: true
    t.index ["household_id"], name: "index_category_aliases_on_household_id"
  end

  create_table "delivery_attempts", force: :cascade do |t|
    t.bigint "reminder_delivery_id", null: false
    t.bigint "push_subscription_id"
    t.string "channel", null: false
    t.string "status", null: false
    t.integer "http_status"
    t.string "error"
    t.string "receipt_token_digest"
    t.datetime "attempted_at", null: false
    t.datetime "received_at"
    t.index ["receipt_token_digest"], name: "index_delivery_attempts_on_receipt_token_digest", unique: true, where: "(receipt_token_digest IS NOT NULL)"
    t.index ["reminder_delivery_id"], name: "index_delivery_attempts_on_reminder_delivery_id"
  end

  create_table "households", force: :cascade do |t|
    t.string "name", null: false
    t.string "default_currency", default: "TWD", null: false
    t.integer "reminder_lead_days", default: 3, null: false
    t.date "last_failure_summary_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "next_record_no", default: 0, null: false
    t.check_constraint "default_currency::text = ANY (ARRAY['TWD'::character varying, 'USD'::character varying]::text[])", name: "households_default_currency"
    t.check_constraint "reminder_lead_days >= 0 AND reminder_lead_days <= 30", name: "households_reminder_lead_days_range"
  end

  create_table "identities", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.string "email"
    t.jsonb "raw_info", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
    t.index ["user_id", "provider"], name: "index_identities_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "import_batch_changes", force: :cascade do |t|
    t.bigint "import_batch_id", null: false
    t.bigint "record_id", null: false
    t.string "action", null: false
    t.jsonb "before"
    t.jsonb "after", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["import_batch_id"], name: "index_import_batch_changes_on_import_batch_id"
    t.check_constraint "action::text = ANY (ARRAY['created'::character varying, 'updated'::character varying]::text[])", name: "import_batch_changes_action"
  end

  create_table "import_batches", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "created_by_id"
    t.string "filename", null: false
    t.integer "row_count", default: 0, null: false
    t.integer "created_count", default: 0, null: false
    t.integer "updated_count", default: 0, null: false
    t.integer "unchanged_count", default: 0, null: false
    t.integer "skipped_count", default: 0, null: false
    t.datetime "undone_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_import_batches_on_created_by_id"
    t.index ["household_id"], name: "index_import_batches_on_household_id"
  end

  create_table "import_keys", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "key", null: false
    t.bigint "record_id"
    t.bigint "import_batch_id"
    t.string "status", default: "active", null: false
    t.string "source_key"
    t.string "retired_digest"
    t.datetime "pasted_back_at"
    t.datetime "created_at", null: false
    t.index ["household_id", "key"], name: "index_import_keys_on_household_id_and_key", unique: true
    t.index ["import_batch_id"], name: "index_import_keys_on_import_batch_id"
    t.index ["record_id"], name: "index_import_keys_on_record_id"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'retired'::character varying]::text[])", name: "import_keys_status"
  end

  create_table "import_previews", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "user_id"
    t.string "filename", null: false
    t.string "csv_sha256", null: false
    t.jsonb "rows", default: [], null: false
    t.jsonb "choices", default: {}, null: false
    t.jsonb "record_versions", default: {}, null: false
    t.datetime "expires_at", null: false
    t.datetime "committed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_import_previews_on_household_id"
    t.index ["user_id"], name: "index_import_previews_on_user_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "invited_by_id"
    t.string "email", null: false
    t.string "role", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at"
    t.datetime "accepted_at"
    t.datetime "declined_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_invitations_on_email"
    t.index ["household_id", "email"], name: "index_invitations_one_open", unique: true, where: "((accepted_at IS NULL) AND (declined_at IS NULL) AND (revoked_at IS NULL))"
    t.index ["household_id"], name: "index_invitations_on_household_id"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
    t.check_constraint "role::text = ANY (ARRAY['co_owner'::character varying, 'viewer'::character varying]::text[])", name: "invitations_role"
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "user_id", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "user_id"], name: "index_memberships_on_household_id_and_user_id", unique: true
    t.index ["household_id"], name: "index_memberships_on_household_id"
    t.index ["household_id"], name: "index_memberships_one_owner", unique: true, where: "((role)::text = 'owner'::text)"
    t.index ["user_id"], name: "index_memberships_on_user_id"
    t.check_constraint "role::text = ANY (ARRAY['owner'::character varying, 'co_owner'::character varying, 'viewer'::character varying]::text[])", name: "memberships_role"
  end

  create_table "notification_preferences", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "household_id", null: false
    t.boolean "web_push", null: false
    t.boolean "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_notification_preferences_on_household_id"
    t.index ["user_id", "household_id"], name: "index_notification_preferences_on_user_id_and_household_id", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "user_id", null: false
    t.string "kind", null: false
    t.string "title", null: false
    t.text "body"
    t.string "url"
    t.bigint "record_id"
    t.bigint "reminder_delivery_id"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.index ["household_id"], name: "index_notifications_on_household_id"
    t.index ["reminder_delivery_id"], name: "index_notifications_on_reminder_delivery_id"
    t.index ["user_id", "read_at", "created_at"], name: "index_notifications_on_user_id_and_read_at_and_created_at"
  end

  create_table "payment_keywords", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "keyword", null: false
    t.bigint "payment_method_id"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "keyword"], name: "index_payment_keywords_on_household_id_and_keyword", unique: true
    t.index ["household_id"], name: "index_payment_keywords_on_household_id"
    t.index ["payment_method_id"], name: "index_payment_keywords_on_payment_method_id"
  end

  create_table "payment_methods", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "name", null: false
    t.string "kind", default: "other", null: false
    t.string "last4"
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_payment_methods_on_household_id"
    t.check_constraint "kind::text = ANY (ARRAY['card'::character varying, 'bank'::character varying, 'e_wallet'::character varying, 'cash'::character varying, 'other'::character varying]::text[])", name: "payment_methods_kind"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "session_id"
    t.string "endpoint", null: false
    t.string "p256dh", null: false
    t.string "auth", null: false
    t.string "user_agent"
    t.string "device_label"
    t.datetime "last_success_at"
    t.datetime "last_receipt_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["session_id"], name: "index_push_subscriptions_on_session_id"
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "reauth_codes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "purpose", null: false
    t.string "code_digest", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_reauth_codes_on_user_id"
  end

  create_table "record_events", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "record_id", null: false
    t.bigint "user_id"
    t.bigint "import_batch_id"
    t.string "action", null: false
    t.jsonb "diff", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["household_id", "created_at"], name: "index_record_events_on_household_id_and_created_at"
    t.index ["record_id", "created_at"], name: "index_record_events_on_record_id_and_created_at"
    t.index ["user_id"], name: "index_record_events_on_user_id"
    t.check_constraint "action::text = ANY (ARRAY['created'::character varying, 'updated'::character varying, 'deleted'::character varying, 'marked_paid'::character varying, 'import_created'::character varying, 'import_updated'::character varying, 'import_undone'::character varying, 'template_updated'::character varying, 'reminders_restarted'::character varying]::text[])", name: "record_events_action"
  end

  create_table "records", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "record_type", null: false
    t.bigint "category_id", null: false
    t.string "title", null: false
    t.string "details"
    t.integer "period_year", null: false
    t.integer "period_start_month", null: false
    t.integer "period_end_year", null: false
    t.integer "period_end_month", null: false
    t.string "currency", default: "TWD", null: false
    t.decimal "amount_required", precision: 12, scale: 2
    t.decimal "amount_paid", precision: 12, scale: 2
    t.boolean "settled", default: false, null: false
    t.date "due_on"
    t.date "paid_on"
    t.bigint "payment_method_id"
    t.text "payment_note"
    t.date "next_due_on"
    t.string "reminder_frequency", default: "none", null: false
    t.date "reminder_starts_on"
    t.integer "record_no", null: false
    t.string "import_key"
    t.string "import_digest"
    t.datetime "imported_at"
    t.jsonb "import_snapshot"
    t.integer "lock_version", default: 0, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "import_batch_id"
    t.bigint "recurring_template_id"
    t.date "reminders_restarted_on"
    t.index ["category_id"], name: "index_records_on_category_id"
    t.index ["created_by_id"], name: "index_records_on_created_by_id"
    t.index ["household_id", "due_on"], name: "index_records_on_household_id_and_due_on", where: "(settled = false)"
    t.index ["household_id", "import_key"], name: "index_records_on_household_id_and_import_key", unique: true
    t.index ["household_id", "next_due_on"], name: "index_records_on_household_id_and_next_due_on", where: "(next_due_on IS NOT NULL)"
    t.index ["household_id", "period_year", "record_type"], name: "index_records_on_household_id_and_period_year_and_record_type"
    t.index ["household_id", "record_no"], name: "index_records_on_household_id_and_record_no", unique: true
    t.index ["household_id", "reminder_frequency"], name: "index_records_on_household_id_and_reminder_frequency", where: "((due_on IS NULL) AND (settled = false))"
    t.index ["import_batch_id"], name: "index_records_on_import_batch_id"
    t.index ["payment_method_id"], name: "index_records_on_payment_method_id"
    t.index ["recurring_template_id", "period_year", "period_start_month"], name: "index_records_one_per_template_period", unique: true, where: "(recurring_template_id IS NOT NULL)"
    t.check_constraint "amount_paid IS NULL OR amount_paid >= 0::numeric", name: "records_amount_paid_nonnegative"
    t.check_constraint "amount_required IS NULL OR amount_required >= 0::numeric", name: "records_amount_required_nonnegative"
    t.check_constraint "currency::text = ANY (ARRAY['TWD'::character varying, 'USD'::character varying]::text[])", name: "records_currency"
    t.check_constraint "period_start_month >= 1 AND period_start_month <= 12 AND period_end_month >= 1 AND period_end_month <= 12", name: "records_period_months"
    t.check_constraint "record_type::text = ANY (ARRAY['expense'::character varying, 'maintenance'::character varying, 'tax'::character varying]::text[])", name: "records_record_type"
    t.check_constraint "reminder_frequency::text = ANY (ARRAY['none'::character varying, 'daily'::character varying, 'every_3_days'::character varying, 'weekly'::character varying, 'biweekly'::character varying, 'monthly'::character varying]::text[])", name: "records_reminder_frequency"
  end

  create_table "recurring_templates", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.string "record_type", null: false
    t.bigint "category_id", null: false
    t.string "title", null: false
    t.string "details"
    t.string "currency", default: "TWD", null: false
    t.decimal "default_amount", precision: 12, scale: 2
    t.boolean "amount_fixed", default: false, null: false
    t.integer "interval_months", null: false
    t.integer "anchor_month", null: false
    t.integer "period_span_months", null: false
    t.date "starts_on", null: false
    t.integer "due_day"
    t.integer "due_month_offset", default: 0, null: false
    t.integer "lead_days", default: 7, null: false
    t.string "default_reminder_frequency", default: "none", null: false
    t.bigint "payment_method_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_recurring_templates_on_category_id"
    t.index ["household_id"], name: "index_recurring_templates_on_household_id"
    t.index ["payment_method_id"], name: "index_recurring_templates_on_payment_method_id"
    t.check_constraint "anchor_month >= 1 AND anchor_month <= 12", name: "recurring_templates_anchor"
    t.check_constraint "due_day IS NULL OR due_day >= 1 AND due_day <= 31", name: "recurring_templates_due_day"
    t.check_constraint "due_month_offset >= 0 AND due_month_offset <= 24", name: "recurring_templates_due_offset"
    t.check_constraint "interval_months >= 1 AND interval_months <= 60", name: "recurring_templates_interval"
    t.check_constraint "lead_days >= 0 AND lead_days <= 90", name: "recurring_templates_lead_days"
    t.check_constraint "period_span_months >= 1 AND period_span_months <= 12", name: "recurring_templates_span"
    t.check_constraint "record_type::text = ANY (ARRAY['expense'::character varying, 'maintenance'::character varying, 'tax'::character varying]::text[])", name: "recurring_templates_record_type"
  end

  create_table "reminder_deliveries", force: :cascade do |t|
    t.bigint "household_id", null: false
    t.bigint "user_id", null: false
    t.string "channel", null: false
    t.date "run_on", null: false
    t.boolean "addition", default: false, null: false
    t.string "status", default: "pending", null: false
    t.datetime "dispatched_at"
    t.string "error"
    t.integer "attempts", default: 0, null: false
    t.datetime "sent_at"
    t.datetime "failed_at"
    t.bigint "resent_by_id"
    t.datetime "resent_at"
    t.datetime "owner_notified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "user_id", "channel", "run_on", "addition"], name: "index_reminder_deliveries_one_per_day", unique: true
    t.index ["household_id"], name: "index_reminder_deliveries_on_household_id"
    t.index ["resent_by_id"], name: "index_reminder_deliveries_on_resent_by_id"
    t.index ["status", "dispatched_at"], name: "index_reminder_deliveries_on_status_and_dispatched_at"
    t.index ["user_id"], name: "index_reminder_deliveries_on_user_id"
    t.check_constraint "channel::text = ANY (ARRAY['in_app'::character varying, 'email'::character varying, 'web_push'::character varying]::text[])", name: "reminder_deliveries_channel"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'awaiting_receipt'::character varying, 'sent'::character varying, 'failed'::character varying, 'resolved'::character varying]::text[])", name: "reminder_deliveries_status"
  end

  create_table "reminder_logs", force: :cascade do |t|
    t.bigint "record_id", null: false
    t.bigint "user_id", null: false
    t.string "kind", null: false
    t.string "channel", null: false
    t.date "scheduled_on", null: false
    t.boolean "snoozed", default: false, null: false
    t.bigint "reminder_delivery_id"
    t.datetime "created_at", null: false
    t.index ["record_id", "user_id", "kind", "channel", "scheduled_on"], name: "index_reminder_logs_claim", unique: true
    t.index ["reminder_delivery_id"], name: "index_reminder_logs_on_reminder_delivery_id"
    t.index ["user_id"], name: "index_reminder_logs_on_user_id"
  end

  create_table "reminder_snoozes", force: :cascade do |t|
    t.bigint "record_id", null: false
    t.bigint "user_id", null: false
    t.date "until_on", null: false
    t.datetime "created_at", null: false
    t.index ["record_id", "user_id"], name: "index_reminder_snoozes_on_record_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_reminder_snoozes_on_user_id"
  end

  create_table "security_events", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "actor_id"
    t.bigint "household_id"
    t.string "kind", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["household_id", "created_at"], name: "index_security_events_on_household_id_and_created_at"
    t.index ["user_id", "created_at"], name: "index_security_events_on_user_id_and_created_at"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "last_seen_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "reauthenticated_at"
    t.index ["expires_at"], name: "index_sessions_on_expires_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.binary "payload", null: false
    t.datetime "created_at", null: false
    t.bigint "channel_hash", null: false
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.binary "key", null: false
    t.binary "value", null: false
    t.datetime "created_at", null: false
    t.bigint "key_hash", null: false
    t.integer "byte_size", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.string "description"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_failure"
    t.text "metadata"
    t.integer "total_jobs", default: 0, null: false
    t.integer "completed_jobs", default: 0, null: false
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "batch_id"
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "spike_push_sends", force: :cascade do |t|
    t.bigint "spike_push_subscription_id", null: false
    t.string "receipt_token", null: false
    t.datetime "scheduled_for", null: false
    t.datetime "sent_at"
    t.integer "http_status"
    t.string "error"
    t.datetime "received_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["receipt_token"], name: "index_spike_push_sends_on_receipt_token", unique: true
    t.index ["spike_push_subscription_id"], name: "index_spike_push_sends_on_spike_push_subscription_id"
  end

  create_table "spike_push_subscriptions", force: :cascade do |t|
    t.string "endpoint", null: false
    t.string "p256dh", null: false
    t.string "auth", null: false
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint"], name: "index_spike_push_subscriptions_on_endpoint", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address"
    t.string "unconfirmed_email"
    t.datetime "email_confirmed_at"
    t.string "password_digest"
    t.string "display_name"
    t.string "locale"
    t.string "time_zone", default: "Asia/Taipei", null: false
    t.integer "reminder_hour", default: 8, null: false
    t.boolean "push_show_amounts", default: true, null: false
    t.bigint "last_household_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true, where: "(email_address IS NOT NULL)"
    t.index ["unconfirmed_email"], name: "index_users_on_unconfirmed_email"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "auth_handoffs", "users", on_delete: :cascade
  add_foreign_key "categories", "households"
  add_foreign_key "category_aliases", "categories"
  add_foreign_key "category_aliases", "households"
  add_foreign_key "delivery_attempts", "reminder_deliveries", on_delete: :cascade
  add_foreign_key "identities", "users"
  add_foreign_key "import_batch_changes", "import_batches"
  add_foreign_key "import_batches", "households"
  add_foreign_key "import_batches", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "import_keys", "households"
  add_foreign_key "import_keys", "import_batches", on_delete: :nullify
  add_foreign_key "import_keys", "records", on_delete: :nullify
  add_foreign_key "import_previews", "households"
  add_foreign_key "import_previews", "users", on_delete: :cascade
  add_foreign_key "invitations", "households"
  add_foreign_key "invitations", "users", column: "invited_by_id", on_delete: :nullify
  add_foreign_key "memberships", "households"
  add_foreign_key "memberships", "users"
  add_foreign_key "notification_preferences", "households"
  add_foreign_key "notification_preferences", "users"
  add_foreign_key "notifications", "households"
  add_foreign_key "notifications", "reminder_deliveries", on_delete: :nullify
  add_foreign_key "notifications", "users", on_delete: :cascade
  add_foreign_key "payment_keywords", "households"
  add_foreign_key "payment_keywords", "payment_methods", on_delete: :nullify
  add_foreign_key "payment_methods", "households"
  add_foreign_key "push_subscriptions", "sessions", on_delete: :nullify
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "reauth_codes", "users", on_delete: :cascade
  add_foreign_key "record_events", "households"
  add_foreign_key "record_events", "users", on_delete: :nullify
  add_foreign_key "records", "categories"
  add_foreign_key "records", "households"
  add_foreign_key "records", "import_batches", on_delete: :nullify
  add_foreign_key "records", "payment_methods", on_delete: :nullify
  add_foreign_key "records", "recurring_templates", on_delete: :nullify
  add_foreign_key "records", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "recurring_templates", "categories"
  add_foreign_key "recurring_templates", "households"
  add_foreign_key "recurring_templates", "payment_methods", on_delete: :nullify
  add_foreign_key "reminder_deliveries", "households"
  add_foreign_key "reminder_deliveries", "users"
  add_foreign_key "reminder_deliveries", "users", column: "resent_by_id", on_delete: :nullify
  add_foreign_key "reminder_logs", "records", on_delete: :cascade
  add_foreign_key "reminder_logs", "reminder_deliveries", on_delete: :nullify
  add_foreign_key "reminder_logs", "users", on_delete: :cascade
  add_foreign_key "reminder_snoozes", "records", on_delete: :cascade
  add_foreign_key "reminder_snoozes", "users", on_delete: :cascade
  add_foreign_key "sessions", "users"
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "spike_push_sends", "spike_push_subscriptions", on_delete: :cascade
  add_foreign_key "users", "households", column: "last_household_id", on_delete: :nullify
end
