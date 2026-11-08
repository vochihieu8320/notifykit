# frozen_string_literal: true

class CreateOrders < ActiveRecord::Migration[7.2]
  def change
    create_table :orders do |t|
      t.string :code, null: false
      t.string :status, null: false, default: "pending"
      t.timestamps
    end
  end
end
