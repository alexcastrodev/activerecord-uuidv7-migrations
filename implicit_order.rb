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
  self.implicit_order_column = :created_at

  before_create :generate_internal_id

  has_many :posts, foreign_key: 'user_internal_id'

  private

  def generate_internal_id
    self.internal_id ||= SecureRandom.uuid
  end
end

class Post < ActiveRecord::Base
  self.implicit_order_column = :created_at

  belongs_to :user, foreign_key: 'user_internal_id', primary_key: 'internal_id'
end

class Uuidv4WithCreatedAtOrderingTest < Minitest::Test
  def setup
    User.delete_all
    Post.delete_all
  end

  def test_uuidv4_is_not_time_ordered
    user1 = User.create!(name: 'First')
    sleep 0.01
    user2 = User.create!(name: 'Second')
    sleep 0.01
    user3 = User.create!(name: 'Third')

    ordered_by_uuid = User.order(:internal_id).to_a

    refute_equal 'First', ordered_by_uuid[0].name, "UUID v4 não deve manter ordem cronológica"
  end

  def test_created_at_maintains_order
    user1 = User.create!(name: 'First')
    sleep 0.01
    user2 = User.create!(name: 'Second')
    sleep 0.01
    user3 = User.create!(name: 'Third')

    ordered_by_created_at = User.order(:created_at).to_a

    assert_equal 'First', ordered_by_created_at[0].name
    assert_equal 'Second', ordered_by_created_at[1].name
    assert_equal 'Third', ordered_by_created_at[2].name
    assert user1.created_at < user2.created_at
    assert user2.created_at < user3.created_at
  end

  def test_implicit_order_column_uses_created_at
    user1 = User.create!(name: 'First')
    sleep 0.01
    user2 = User.create!(name: 'Second')
    sleep 0.01
    user3 = User.create!(name: 'Third')

    users = User.all.to_a

    assert_equal 'First', users[0].name
    assert_equal 'Second', users[1].name
    assert_equal 'Third', users[2].name
  end

  def test_first_and_last_use_created_at
    user1 = User.create!(name: 'First')
    sleep 0.01
    user2 = User.create!(name: 'Second')
    sleep 0.01
    user3 = User.create!(name: 'Third')

    first_user = User.first
    last_user = User.last

    assert_equal 'First', first_user.name
    assert_equal 'Third', last_user.name
  end

  def test_order_by_created_at_asc_and_desc
    user1 = User.create!(name: 'User A')
    sleep 0.01
    user2 = User.create!(name: 'User B')
    sleep 0.01
    user3 = User.create!(name: 'User C')

    ordered_users = User.order(:created_at).to_a
    reverse_ordered = User.order(created_at: :desc).to_a

    assert_equal 3, ordered_users.length
    assert_equal ordered_users.first.internal_id, reverse_ordered.last.internal_id
    assert_equal ordered_users.last.internal_id, reverse_ordered.first.internal_id
  end

  def test_join_respects_created_at_ordering
    user1 = User.create!(name: 'Alpha')
    sleep 0.01
    user2 = User.create!(name: 'Beta')

    user1.posts.create!(title: 'Post 1', content: 'Content 1')
    sleep 0.01
    user2.posts.create!(title: 'Post 2', content: 'Content 2')

    results = User.joins(:posts).to_a

    assert_equal 'Alpha', results.first.name
    assert_equal 'Beta', results.last.name
  end

  def test_posts_also_ordered_by_created_at
    user = User.create!(name: 'Test User')

    post1 = user.posts.create!(title: 'First Post', content: 'Content 1')
    sleep 0.01
    post2 = user.posts.create!(title: 'Second Post', content: 'Content 2')
    sleep 0.01
    post3 = user.posts.create!(title: 'Third Post', content: 'Content 3')

    posts = user.posts.to_a

    assert_equal 'First Post', posts[0].title
    assert_equal 'Second Post', posts[1].title
    assert_equal 'Third Post', posts[2].title
  end

  def test_uuidv4_format_validation
    user = User.create!(name: 'Test')

    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i, user.internal_id)
  end

  def test_comparison_uuid_vs_created_at_ordering
    users = []
    5.times do |i|
      user = User.create!(name: "User #{i + 1}")
      users << user
      sleep 0.01
    end

    ordered_by_uuid = User.order(:internal_id).to_a
    ordered_by_created_at = User.order(:created_at).to_a

    assert_equal 'User 1', ordered_by_created_at[0].name
    assert_equal 'User 2', ordered_by_created_at[1].name
    assert_equal 'User 3', ordered_by_created_at[2].name
    assert_equal 'User 4', ordered_by_created_at[3].name
    assert_equal 'User 5', ordered_by_created_at[4].name

    refute_equal ordered_by_uuid.map(&:name), ordered_by_created_at.map(&:name),
                 "UUID v4 não deve manter a mesma ordem que created_at"
  end
end
