require_relative 'base'

begin
  puts "\n=== Step 1: Creating tables ==="
  ActiveRecord::Schema.define do
    create_table :colors do |t|
      t.uuid :internal_id, null: false, default: -> { 'uuidv7()' }, index: { unique: true }
      t.string :name, null: false
    end

    create_table :sizes do |t|
      t.uuid :internal_id, null: false, default: -> { 'uuidv7()' }, index: { unique: true }
      t.string :name, null: false
    end

    create_table :products do |t|
      t.integer :color_id, null: false, index: true
      t.uuid :color_internal_id
      t.integer :size_id, null: false
      t.uuid :size_internal_id
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

  puts "\n=== Step 2.5: Creating 3 sizes ==="
  size_names = ['Small', 'Medium', 'Large']
  sizes = size_names.map do |name|
    size = Size.create!(name: name)
    raise "Expected size to have internal_id, got nil" if size.internal_id.nil?

    puts "  Created size: #{name} (id: #{size.id}, internal_id: #{size.internal_id})"
    size
  end

  raise "Expected to create 3 sizes, got #{sizes.size}" unless sizes.size == 3

  puts "✓ Created #{sizes.size} sizes"

  puts "\n=== Step 3: Creating 10 products with color_id and size_id references ==="
  10.times do |i|
    color = colors.sample
    size = sizes.sample
    product = Product.create!(
      name: "Product #{i + 1}",
      color_id: color.id,
      size_id: size.id
    )
    raise "Expected product.color_id to equal color.id, got #{product.color_id} vs #{color.id}" unless product.color_id == color.id
    raise "Expected product.size_id to equal size.id, got #{product.size_id} vs #{size.id}" unless product.size_id == size.id

    puts "  Created: #{product.name} -> color: #{color.name}, size: #{size.name}"
  end

  raise "Expected to create 10 products, got #{Product.count}" unless Product.count == 10

  puts "✓ Inserted 10 products"

  puts "\n=== Step 4: Verifying products before sync ==="
  Product.limit(5).each do |product|
    color = Color.find(product.color_id)
    size = Size.find(product.size_id)
    puts "  Product: #{product.name}"
    puts "    color_id: #{product.color_id} (integer), color_internal_id: #{product.color_internal_id.inspect} (should be nil)"
    puts "    size_id: #{product.size_id} (integer), size_internal_id: #{product.size_internal_id.inspect} (should be nil)"

    raise "Expected color_internal_id to be nil before sync, got: #{product.color_internal_id}" if product.color_internal_id.present?
    raise "Expected size_internal_id to be nil before sync, got: #{product.size_internal_id}" if product.size_internal_id.present?

    puts "    -> references Color: #{color.name}, Size: #{size.name}"
  end

  puts "\n=== Step 5: Syncing color_internal_id and size_internal_id ==="
  sync_count = 0
  Product.find_each do |product|
    color = Color.find(product.color_id)
    raise "Could not find color with id: #{product.color_id}" unless color

    size = Size.find(product.size_id)
    raise "Could not find size with id: #{product.size_id}" unless size

    product.update!(
      color_internal_id: color.internal_id,
      size_internal_id: size.internal_id
    )
    raise "Failed to sync color_internal_id for product #{product.id}" if product.color_internal_id != color.internal_id
    raise "Failed to sync size_internal_id for product #{product.id}" if product.size_internal_id != size.internal_id

    sync_count += 1
  end

  raise "Expected to sync 10 products, synced #{sync_count}" unless sync_count == 10

  puts "✓ Synced #{sync_count} products (color_internal_id and size_internal_id)"

  puts "\n=== Step 6: Verifying products after sync ==="
  Product.limit(5).each do |product|
    raise "Expected color_internal_id to be present after sync, got nil" if product.color_internal_id.nil?
    raise "Expected size_internal_id to be present after sync, got nil" if product.size_internal_id.nil?

    color = Color.find_by(internal_id: product.color_internal_id)
    raise "Could not find color with internal_id: #{product.color_internal_id}" unless color

    size = Size.find_by(internal_id: product.size_internal_id)
    raise "Could not find size with internal_id: #{product.size_internal_id}" unless size

    puts "  Product: #{product.name}"
    puts "    color_id: #{product.color_id} (integer), color_internal_id: #{product.color_internal_id} (UUID)"
    puts "    size_id: #{product.size_id} (integer), size_internal_id: #{product.size_internal_id} (UUID)"
    puts "    -> now references Color: #{color.name}, Size: #{size.name} via UUID"
  end

  # Check that all _internal_id are populated
  null_color_count = Product.where(color_internal_id: nil).count
  null_size_count = Product.where(size_internal_id: nil).count
  puts "\n  Products with NULL values: color=#{null_color_count}, size=#{null_size_count}"

  if null_color_count > 0 || null_size_count > 0
    raise "Cannot proceed with migration - #{null_color_count} products have NULL color_internal_id, #{null_size_count} have NULL size_internal_id!"
  else
    puts "  ✓ All products have valid color_internal_id and size_internal_id values"
  end

  count_before = Product.count

  puts "\n=== Step 7: Migration - Drop _id columns and rename _internal_id columns ==="
  ActiveRecord::Base.transaction do
    # Drop old integer ID columns
    ActiveRecord::Base.connection.remove_column :products, :color_id
    puts "  ✓ Dropped column 'color_id' (integer)"
    ActiveRecord::Base.connection.remove_column :products, :size_id
    puts "  ✓ Dropped column 'size_id' (integer)"

    # Rename UUID columns to replace the old IDs
    ActiveRecord::Base.connection.rename_column :products, :color_internal_id, :color_id
    puts "  ✓ Renamed 'color_internal_id' to 'color_id' (UUID)"
    ActiveRecord::Base.connection.rename_column :products, :size_internal_id, :size_id
    puts "  ✓ Renamed 'size_internal_id' to 'size_id' (UUID)"
  end
  puts "✓ Migration transaction completed successfully"

  Product.reset_column_information

  puts "\n=== Step 8: Verifying products after migration ==="
  Product.limit(5).each do |product|
    raise "Expected color_id to be present after migration, got nil" if product.color_id.nil?
    raise "Expected size_id to be present after migration, got nil" if product.size_id.nil?

    color = Color.find_by(internal_id: product.color_id)
    raise "Could not find color with internal_id: #{product.color_id}" unless color

    size = Size.find_by(internal_id: product.size_id)
    raise "Could not find size with internal_id: #{product.size_id}" unless size

    puts "  Product: #{product.name}"
    puts "    color_id: #{product.color_id} (UUID) -> #{color.name}"
    puts "    size_id: #{product.size_id} (UUID) -> #{size.name}"
  end

  puts "\n=== Step 9: Checking for empty values after migration ==="
  empty_color_count = Product.where(color_id: nil).count
  empty_size_count = Product.where(size_id: nil).count

  if empty_color_count > 0 || empty_size_count > 0
    raise "Migration failed - #{empty_color_count} products have NULL color_id, #{empty_size_count} have NULL size_id!"
  end

  puts "✓ No empty values found! All #{count_before} products have valid UUID color_id and size_id"

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

  size_columns = ActiveRecord::Base.connection.columns(:sizes)
  puts "\n  Sizes table structure:"
  size_columns.each do |column|
    puts "    - #{column.name}: #{column.sql_type} (nullable: #{column.null})"
  end

  puts "\n=== Migration completed successfully! ==="
  puts "  Summary:"
  puts "    - Created #{Color.count} colors with UUID internal_id"
  puts "    - Created #{Size.count} sizes with UUID internal_id"
  puts "    - Created #{Product.count} products"
  puts "    - Synced all color_internal_id and size_internal_id"
  puts "    - Migrated color_id and size_id from integer to UUID"
  puts "    - All products now reference colors and sizes via UUID"

ensure
  ActiveRecord::Base.connection.close if ActiveRecord::Base.connected?
  puts "\nStopping PostgreSQL container..."
  $postgres.stop
  $postgres.remove
  puts "✓ Container stopped and removed"
end
