# encoding: utf-8
# frozen_string_literal: true

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'activerecord', '~> 8.1.1'
  gem 'sqlite3', '~> 2.5'
  gem 'minitest', '~> 5.25'
end

require 'active_record'
require 'securerandom'
require 'minitest/autorun'

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

ActiveRecord::Base.logger = nil

ActiveRecord::Schema.define do
  drop_table :posts, if_exists: true
  drop_table :users, if_exists: true

  create_table :users do |t|
    t.string :name, null: false
    t.string :internal_id, limit: 36, null: false
    t.timestamps
  end

  add_index :users, :internal_id, unique: true

  create_table :posts do |t|
    t.string :title, null: false
    t.text :content
    t.string :user_internal_id, limit: 36, null: false
    t.timestamps
  end

  add_index :posts, :user_internal_id
end

class User < ActiveRecord::Base
  self.primary_key = 'internal_id'

  before_create :generate_internal_id

  has_many :posts, foreign_key: 'user_internal_id'

  private

  def generate_internal_id
    self.internal_id ||= SecureRandom.uuid_v7
  end
end

class Post < ActiveRecord::Base
  belongs_to :user, foreign_key: 'user_internal_id', primary_key: 'internal_id'
end

class MigrationScenarioTest < Minitest::Test
  def setup
    User.delete_all
    Post.delete_all
  end

  def test_migrate_existing_data_to_uuidv7_maintaining_order
    begin
      original_pk = User.primary_key

      User.class_eval do
        skip_callback(:create, :before, :generate_internal_id) rescue nil
        self.primary_key = 'id'
      end

      old_user1 = User.create!(name: 'Old User 1', internal_id: 'legacy-id-001', created_at: 1.day.ago, updated_at: 1.day.ago)
      old_user2 = User.create!(name: 'Old User 2', internal_id: 'legacy-id-002', created_at: 12.hours.ago, updated_at: 12.hours.ago)
      old_user3 = User.create!(name: 'Old User 3', internal_id: 'legacy-id-003', created_at: 1.hour.ago, updated_at: 1.hour.ago)

      old_data = User.all.map { |u| { id: u.id, name: u.name, created_at: u.created_at, updated_at: u.updated_at } }

      ActiveRecord::Base.connection.remove_index :users, :internal_id
      ActiveRecord::Base.connection.remove_column :users, :internal_id
      ActiveRecord::Base.connection.add_column :users, :internal_id, :string, limit: 36
      ActiveRecord::Base.connection.add_index :users, :internal_id, unique: true

      User.reset_column_information

      old_data.each do |data|
        user = User.find(data[:id])
        timestamp_ms = (data[:created_at].to_f * 1000).to_i
        uuid_v7_bytes = [timestamp_ms].pack('Q>') + SecureRandom.random_bytes(10)
        uuid_v7_bytes[6] = ((uuid_v7_bytes[6].ord & 0x0f) | 0x70).chr
        uuid_v7_bytes[8] = ((uuid_v7_bytes[8].ord & 0x3f) | 0x80).chr
        new_uuid = uuid_v7_bytes.unpack('H8H4H4H4H12').join('-')

        user.update_column(:internal_id, new_uuid)
      end

      User.class_eval do
        self.primary_key = 'internal_id'
      end

      ordered_users = User.order(:internal_id).to_a

      assert_equal 'Old User 1', ordered_users[0].name
      assert_equal 'Old User 2', ordered_users[1].name
      assert_equal 'Old User 3', ordered_users[2].name
      assert ordered_users[0].internal_id < ordered_users[1].internal_id
      assert ordered_users[1].internal_id < ordered_users[2].internal_id
    ensure
      User.class_eval do
        self.primary_key = original_pk
        set_callback(:create, :before, :generate_internal_id) rescue nil
      end
    end
  end

end
