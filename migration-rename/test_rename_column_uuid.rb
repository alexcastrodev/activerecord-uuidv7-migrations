require_relative 'base'

begin
  puts "\n=== Step 1: Creating table ==="
  ActiveRecord::Schema.define do
    create_table :products do |t|
      t.integer :product_id, null: false
      t.uuid :product_internal_id, default: -> { 'uuidv7()' }
    end
  end
  puts "✓ Table 'products' created"

  puts "\n=== Step 2: Populating with 10 records ==="
  10.times do |i|
    Product.create!(product_id: 1000 + i)
  end
  puts "✓ Inserted 10 records"

  puts "\n=== Step 3: Verifying data before migration ==="
  Product.limit(5).each do |product|
    puts "  ID: #{product.id}, product_id: #{product.product_id}, product_internal_id: #{product.product_internal_id}"
  end

  count_before = Product.count
  puts "  Total records: #{count_before}"

  puts "\n=== Step 4: Dropping product_id column ==="
  ActiveRecord::Base.connection.remove_column :products, :product_id
  puts "✓ Column 'product_id' dropped"

  puts "\n=== Step 5: Renaming product_internal_id to product_id ==="
  ActiveRecord::Base.connection.rename_column :products, :product_internal_id, :product_id
  puts "✓ Column 'product_internal_id' renamed to 'product_id'"

  Product.reset_column_information

  puts "\n=== Step 6: Verifying data after migration ==="
  Product.limit(5).each do |product|
    puts "  ID: #{product.id}, product_id (UUID): #{product.product_id}"
  end

  puts "\n=== Step 7: Checking for empty values ==="
  empty_count = Product.where(product_id: nil).count

  if empty_count == 0
    puts "✓ No empty values found! All #{count_before} records have valid UUIDs"
  else
    puts "✗ Found #{empty_count} empty values!"
  end

  puts "\n=== Migration completed successfully! ==="

ensure
  ActiveRecord::Base.connection.close if ActiveRecord::Base.connected?
  puts "\nStopping PostgreSQL container..."
  $postgres.stop
  $postgres.remove
  puts "✓ Container stopped and removed"
end
