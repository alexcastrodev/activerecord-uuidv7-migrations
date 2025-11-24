require_relative 'base'

# Define models
class Color < ActiveRecord::Base
end

begin
  puts "\n=== Step 1: Creating tables ==="
  ActiveRecord::Schema.define do
    create_table :colors do |t|
      t.uuid :internal_id, null: false, default: -> { 'uuidv7()' }, index: { unique: true }
      t.string :name, null: false
    end

    create_table :products do |t|
      t.integer :color_id, null: false, index: true
      t.uuid :color_internal_id
      t.string :name, null: false
    end
  end
  puts "✓ Tables 'colors' and 'products' created"

  puts "\n=== Step 2: Creating 5 colors ==="
  color_names = ['Red', 'Blue', 'Green', 'Yellow', 'Purple']
  colors = color_names.map do |name|
    color = Color.create!(name: name)
    raise "Expected color to have internal_id, got nil" if color.internal_id.nil?

    puts "  Created color: #{name} (id: #{color.id}, internal_id: #{color.internal_id})"
    color
  end

  raise "Expected to create 5 colors, got #{colors.size}" unless colors.size == 5

  puts "✓ Created #{colors.size} colors"

  puts "\n=== Step 3: Creating 10 products with color_id references ==="
  10.times do |i|
    color = colors.sample # Pick a random color
    product = Product.create!(
      name: "Product #{i + 1}",
      color_id: color.id  # Using integer ID for now
    )
    raise "Expected product.color_id to equal color.id, got #{product.color_id} vs #{color.id}" unless product.color_id == color.id

    puts "  Created: #{product.name} -> color_id: #{product.color_id} (#{color.name})"
  end

  raise "Expected to create 10 products, got #{Product.count}" unless Product.count == 10

  puts "✓ Inserted 10 products"

  puts "\n=== Step 4: Verifying products before sync ==="
  Product.limit(5).each do |product|
    color = Color.find(product.color_id)
    puts "  Product: #{product.name}"
    puts "    color_id: #{product.color_id} (integer)"
    puts "    color_internal_id: #{product.color_internal_id.inspect} (should be nil)"

    raise "Expected color_internal_id to be nil before sync, got: #{product.color_internal_id}" if product.color_internal_id.present?

    puts "    -> references Color: #{color.name} (internal_id: #{color.internal_id})"
  end

  puts "\n=== Step 5: Syncing color_internal_id from colors.internal_id ==="
  sync_count = 0
  Product.find_each do |product|
    color = Color.find(product.color_id)
    raise "Could not find color with id: #{product.color_id}" unless color

    product.update!(color_internal_id: color.internal_id)
    raise "Failed to sync color_internal_id for product #{product.id}" if product.color_internal_id != color.internal_id

    sync_count += 1
  end

  raise "Expected to sync 10 products, synced #{sync_count}" unless sync_count == 10

  puts "✓ Synced #{sync_count} products"

  puts "\n=== Step 6: Verifying products after sync ==="
  Product.limit(5).each do |product|
    raise "Expected color_internal_id to be present after sync, got nil" if product.color_internal_id.nil?

    color = Color.find_by(internal_id: product.color_internal_id)
    raise "Could not find color with internal_id: #{product.color_internal_id}" unless color

    puts "  Product: #{product.name}"
    puts "    color_id: #{product.color_id} (integer)"
    puts "    color_internal_id: #{product.color_internal_id} (UUID)"
    puts "    -> now references Color: #{color.name} via UUID"
  end

  # Check that all color_internal_id are populated
  null_count = Product.where(color_internal_id: nil).count
  puts "\n  Products with NULL color_internal_id: #{null_count}/#{Product.count}"

  if null_count > 0
    raise "Cannot proceed with migration - #{null_count} products still have NULL color_internal_id!"
  else
    puts "  ✓ All products have valid color_internal_id values"
  end

  count_before = Product.count

  puts "\n=== Step 7: Migration - Drop color_id and rename color_internal_id ==="
  ActiveRecord::Base.transaction do
    # Drop old integer ID column
    ActiveRecord::Base.connection.remove_column :products, :color_id
    puts "  ✓ Dropped column 'color_id' (integer)"

    # Rename UUID column to replace the old ID
    ActiveRecord::Base.connection.rename_column :products, :color_internal_id, :color_id
    puts "  ✓ Renamed 'color_internal_id' to 'color_id' (UUID)"
  end
  puts "✓ Migration transaction completed successfully"

  Product.reset_column_information

  puts "\n=== Step 8: Verifying products after migration ==="
  Product.limit(5).each do |product|
    raise "Expected color_id to be present after migration, got nil" if product.color_id.nil?

    color = Color.find_by(internal_id: product.color_id)
    raise "Could not find color with internal_id: #{product.color_id}" unless color

    puts "  Product: #{product.name}"
    puts "    color_id: #{product.color_id} (UUID - was color_internal_id)"
    puts "    -> references Color: #{color.name}"
  end

  puts "\n=== Step 9: Checking for empty values after migration ==="
  empty_color_count = Product.where(color_id: nil).count

  if empty_color_count > 0
    raise "Migration failed - #{empty_color_count} products have NULL color_id after migration!"
  end

  puts "✓ No empty values found! All #{count_before} products have valid UUID color_id"

  puts "\n=== Step 10: Verifying table structure ==="
  product_columns = ActiveRecord::Base.connection.columns(:products)
  puts "\n  Products table structure:"
  product_columns.each do |column|
    puts "    - #{column.name}: #{column.sql_type} (nullable: #{column.null})"
  end

  color_columns = ActiveRecord::Base.connection.columns(:colors)
  puts "\n  Colors table structure:"
  color_columns.each do |column|
    puts "    - #{column.name}: #{column.sql_type} (nullable: #{column.null})"
  end

  puts "\n=== Migration completed successfully! ==="
  puts "  Summary:"
  puts "    - Created #{Color.count} colors with UUID internal_id"
  puts "    - Created #{Product.count} products"
  puts "    - Synced all color_internal_id from colors.internal_id"
  puts "    - Migrated color_id from integer to UUID"
  puts "    - All products now reference colors via UUID"

ensure
  ActiveRecord::Base.connection.close if ActiveRecord::Base.connected?
  puts "\nStopping PostgreSQL container..."
  $postgres.stop
  $postgres.remove
  puts "✓ Container stopped and removed"
end
