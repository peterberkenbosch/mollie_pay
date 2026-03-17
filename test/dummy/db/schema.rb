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

ActiveRecord::Schema[8.1].define(version: 2026_03_17_100000) do
  create_table "mollie_pay_customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "mollie_id", null: false
    t.integer "owner_id", null: false
    t.string "owner_type", null: false
    t.datetime "updated_at", null: false
    t.index ["mollie_id"], name: "index_mollie_pay_customers_on_mollie_id", unique: true
    t.index ["owner_type", "owner_id"], name: "index_mollie_pay_customers_on_owner", unique: true
  end

  create_table "mollie_pay_mandates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.datetime "mandated_at"
    t.string "method", null: false
    t.string "mollie_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "status"], name: "index_mollie_pay_mandates_on_customer_id_and_status"
    t.index ["customer_id"], name: "index_mollie_pay_mandates_on_customer_id"
    t.index ["mollie_id"], name: "index_mollie_pay_mandates_on_mollie_id", unique: true
  end

  create_table "mollie_pay_payments", force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "canceled_at"
    t.string "checkout_url"
    t.datetime "created_at", null: false
    t.string "currency", default: "EUR", null: false
    t.integer "customer_id", null: false
    t.datetime "expired_at"
    t.datetime "failed_at"
    t.string "mollie_id"
    t.datetime "paid_at"
    t.string "sequence_type", default: "oneoff", null: false
    t.string "status", default: "open", null: false
    t.integer "subscription_id"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "status"], name: "index_mollie_pay_payments_on_customer_id_and_status"
    t.index ["customer_id"], name: "index_mollie_pay_payments_on_customer_id"
    t.index ["mollie_id"], name: "index_mollie_pay_payments_on_mollie_id", unique: true
    t.index ["subscription_id"], name: "index_mollie_pay_payments_on_subscription_id"
  end

  create_table "mollie_pay_refunds", force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "EUR", null: false
    t.string "mollie_id", null: false
    t.integer "payment_id", null: false
    t.datetime "refunded_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.index ["mollie_id"], name: "index_mollie_pay_refunds_on_mollie_id", unique: true
    t.index ["payment_id"], name: "index_mollie_pay_refunds_on_payment_id"
  end

  create_table "mollie_pay_subscriptions", force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "canceled_at"
    t.datetime "created_at", null: false
    t.string "currency", default: "EUR", null: false
    t.integer "customer_id", null: false
    t.string "interval", null: false
    t.string "mollie_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "status"], name: "index_mollie_pay_subscriptions_on_customer_id_and_status"
    t.index ["customer_id"], name: "index_mollie_pay_subscriptions_on_customer_id"
    t.index ["mollie_id"], name: "index_mollie_pay_subscriptions_on_mollie_id", unique: true
  end

  create_table "mollie_pay_webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.datetime "failed_at"
    t.string "mollie_id", null: false
    t.datetime "processed_at"
    t.string "resource_type"
    t.datetime "updated_at", null: false
    t.index ["mollie_id"], name: "index_mollie_pay_webhook_events_on_mollie_id", unique: true
    t.index ["processed_at"], name: "index_mollie_pay_webhook_events_on_processed_at"
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "mollie_pay_mandates", "mollie_pay_customers", column: "customer_id"
  add_foreign_key "mollie_pay_payments", "mollie_pay_customers", column: "customer_id"
  add_foreign_key "mollie_pay_payments", "mollie_pay_subscriptions", column: "subscription_id"
  add_foreign_key "mollie_pay_refunds", "mollie_pay_payments", column: "payment_id"
  add_foreign_key "mollie_pay_subscriptions", "mollie_pay_customers", column: "customer_id"
end
