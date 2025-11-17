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

class BasicUuidTest < Minitest::Test
  def setup
    User.delete_all
    Post.delete_all
  end

  def test_user_creation_with_uuidv7_primary_key
    user = User.create!(name: 'Alice')

    assert_equal 'internal_id', User.primary_key
    refute_nil user.internal_id
    assert_equal user.internal_id, user.id
  end

  def test_uuidv7_format_validation
    user = User.create!(name: 'Test')

    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i, user.internal_id)
  end

  def test_find_by_uuid_primary_key
    user = User.create!(name: 'Bob')

    found_user = User.find(user.internal_id)

    assert_equal user.internal_id, found_user.internal_id
    assert_equal 'Bob', found_user.name
  end

  def test_uuid_is_string_type
    user = User.create!(name: 'Maria')

    assert_instance_of String, user.internal_id
    assert_instance_of String, user.id
  end
end

class AssociationTest < Minitest::Test
  def setup
    User.delete_all
    Post.delete_all
  end

  def test_has_many_association_with_uuid
    user = User.create!(name: 'Charlie')
    post1 = user.posts.create!(title: 'First Post', content: 'Content 1')
    post2 = user.posts.create!(title: 'Second Post', content: 'Content 2')

    assert_equal 2, user.posts.count
    assert_equal user.internal_id, post1.user_internal_id
    assert_equal user.internal_id, post2.user_internal_id
  end

  def test_belongs_to_association_with_uuid
    user = User.create!(name: 'David')
    post = user.posts.create!(title: 'My Post', content: 'My Content')

    retrieved_post = Post.find(post.id)

    assert_equal user.internal_id, retrieved_post.user.internal_id
    assert_equal 'David', retrieved_post.user.name
  end

  def test_multiple_posts_with_same_uuid_reference
    user = User.create!(name: 'Nathan')
    posts = 3.times.map { |i| user.posts.create!(title: "Post #{i}", content: "Content #{i}") }

    posts.each do |post|
      assert_equal user.internal_id, post.user_internal_id
    end
  end
end

class JoinTest < Minitest::Test
  def setup
    User.delete_all
    Post.delete_all
  end

  def test_inner_join_with_uuid_primary_key
    user1 = User.create!(name: 'Emma')
    user2 = User.create!(name: 'Frank')
    user1.posts.create!(title: 'Post A', content: 'Content A')
    user2.posts.create!(title: 'Post B', content: 'Content B')

    results = User.joins(:posts)

    assert_equal 2, results.count
    assert_includes results.map(&:name), 'Emma'
    assert_includes results.map(&:name), 'Frank'
  end

  def test_join_with_where_clause
    user = User.create!(name: 'Grace')
    user.posts.create!(title: 'Urgent Post', content: 'Urgent content')
    user.posts.create!(title: 'Normal Post', content: 'Normal content')

    results = User.joins(:posts).where("posts.title LIKE ?", "%Urgent%")

    assert_equal 1, results.count
    assert_equal 'Grace', results.first.name
  end

  def test_left_join_includes_users_without_posts
    user_with_posts = User.create!(name: 'Helen')
    user_without_posts = User.create!(name: 'Ivan')
    user_with_posts.posts.create!(title: 'Some Post', content: 'Some content')

    users_with_posts = User.joins(:posts).pluck(:internal_id)
    all_users = User.pluck(:internal_id)

    assert_equal 1, users_with_posts.count
    assert_equal 2, all_users.count
    assert_includes users_with_posts, user_with_posts.internal_id
  end

  def test_join_with_aggregation
    user1 = User.create!(name: 'Jack')
    user2 = User.create!(name: 'Kate')
    user1.posts.create!(title: 'Post 1', content: 'Content 1')
    user1.posts.create!(title: 'Post 2', content: 'Content 2')
    user2.posts.create!(title: 'Post 3', content: 'Content 3')

    results = User.joins(:posts)
                  .group('users.internal_id')
                  .having('COUNT(posts.id) > 1')

    assert_equal 1, results.length
    assert_equal 'Jack', results.first.name
  end

  def test_join_sql_uses_uuid_column
    User.create!(name: 'Leo')

    sql = User.joins(:posts).to_sql

    assert_includes sql, '"users"."internal_id"'
    assert_includes sql, '"posts"."user_internal_id"'
  end

  def test_join_with_select_specific_columns
    user = User.create!(name: 'Olivia')
    user.posts.create!(title: 'Selected Post', content: 'Selected content')

    results = User.joins(:posts).select('users.*, posts.title AS post_title, posts.content AS post_content').limit(1)

    assert_equal 1, results.length
    assert_equal 'Olivia', results.first.name
    assert_equal 'Selected Post', results.first.post_title
    assert_equal 'Selected content', results.first.post_content
  end
end

class Uuidv7OrderingTest < Minitest::Test
  def setup
    User.delete_all
    Post.delete_all
  end

  def test_uuidv7_is_time_ordered
    user1 = User.create!(name: 'First')
    sleep 0.01
    user2 = User.create!(name: 'Second')
    sleep 0.01
    user3 = User.create!(name: 'Third')

    ordered_by_uuid = User.order(:internal_id).to_a

    assert_equal 'First', ordered_by_uuid[0].name
    assert_equal 'Second', ordered_by_uuid[1].name
    assert_equal 'Third', ordered_by_uuid[2].name
    assert user1.internal_id < user2.internal_id
    assert user2.internal_id < user3.internal_id
  end

  def test_first_and_last_work_with_uuidv7_ordering
    user1 = User.create!(name: 'First')
    sleep 0.01
    user2 = User.create!(name: 'Second')
    sleep 0.01
    user3 = User.create!(name: 'Third')

    first_user = User.order(:internal_id).first
    last_user = User.order(:internal_id).last

    assert_equal 'First', first_user.name
    assert_equal 'Third', last_user.name
  end

  def test_order_by_uuid_asc_and_desc
    user1 = User.create!(name: 'User A')
    sleep 0.01
    user2 = User.create!(name: 'User B')
    sleep 0.01
    user3 = User.create!(name: 'User C')

    ordered_users = User.order(:internal_id).to_a
    reverse_ordered = User.order(internal_id: :desc).to_a

    assert_equal 3, ordered_users.length
    assert_equal ordered_users.first.internal_id, reverse_ordered.last.internal_id
    assert_equal ordered_users.last.internal_id, reverse_ordered.first.internal_id
  end

  def test_join_respects_uuidv7_ordering
    user1 = User.create!(name: 'Alpha')
    sleep 0.01
    user2 = User.create!(name: 'Beta')

    user1.posts.create!(title: 'Post 1', content: 'Content 1')
    user2.posts.create!(title: 'Post 2', content: 'Content 2')

    results = User.joins(:posts).order('users.internal_id')

    assert_equal 'Alpha', results.first.name
    assert_equal 'Beta', results.last.name
  end
end
