require_relative 'base'

begin
  puts "\n=== Step 1: Creating table ==="
  ActiveRecord::Schema.define do
    create_table :products do |t|
      t.integer :product_id, null: false
      t.uuid :product_internal_id, default: -> { 'uuidv7()' }, index: { unique: true }
      t.integer :category_id, null: false
      t.uuid :category_internal_id, default: -> { 'uuidv7()' }, index: { unique: true }
      t.integer :supplier_id, null: false
      t.uuid :supplier_internal_id, default: -> { 'uuidv7()' }, index: { unique: true }
    end
  end
  puts "✓ Table 'products' created"

  puts "\n=== Step 2: Populating with 10 records ==="
  10.times do |i|
    Product.create!(
      product_id: 1000 + i,
      category_id: 2000 + i,
      supplier_id: 3000 + i
    )
  end
  puts "✓ Inserted 10 records"

  puts "\n=== Step 3: Verifying data before migration ==="
  Product.limit(5).each do |product|
    puts "  ID: #{product.id}"
    puts "    product_id: #{product.product_id}, product_internal_id: #{product.product_internal_id}"
    puts "    category_id: #{product.category_id}, category_internal_id: #{product.category_internal_id}"
    puts "    supplier_id: #{product.supplier_id}, supplier_internal_id: #{product.supplier_internal_id}"
  end

  count_before = Product.count
  puts "  Total records: #{count_before}"

  puts "\n=== Step 4 & 5: Dropping _id columns and renaming _internal_id columns in transaction ==="
  ActiveRecord::Base.transaction do
    # Drop old integer ID columns
    ActiveRecord::Base.connection.remove_column :products, :product_id
    ActiveRecord::Base.connection.remove_column :products, :category_id
    ActiveRecord::Base.connection.remove_column :products, :supplier_id

    # Rename UUID columns to replace the old IDs
    ActiveRecord::Base.connection.rename_column :products, :product_internal_id, :product_id
    ActiveRecord::Base.connection.rename_column :products, :category_internal_id, :category_id
    ActiveRecord::Base.connection.rename_column :products, :supplier_internal_id, :supplier_id
  end
  puts "✓ Transaction completed successfully"

  Product.reset_column_information

  puts "\n=== Step 6: Verifying data after migration ==="
  Product.limit(5).each do |product|
    puts "  ID: #{product.id}"
    puts "    product_id (UUID): #{product.product_id}"
    puts "    category_id (UUID): #{product.category_id}"
    puts "    supplier_id (UUID): #{product.supplier_id}"
  end

  puts "\n=== Step 7: Checking for empty values ==="
  empty_product_count = Product.where(product_id: nil).count
  empty_category_count = Product.where(category_id: nil).count
  empty_supplier_count = Product.where(supplier_id: nil).count

  if empty_product_count == 0 && empty_category_count == 0 && empty_supplier_count == 0
    puts "✓ No empty values found! All #{count_before} records have valid UUIDs for all fields"
  else
    puts "✗ Found empty values:"
    puts "  - product_id: #{empty_product_count}" if empty_product_count > 0
    puts "  - category_id: #{empty_category_count}" if empty_category_count > 0
    puts "  - supplier_id: #{empty_supplier_count}" if empty_supplier_count > 0
  end

  puts "\n=== Migration completed successfully! ==="

ensure
  ActiveRecord::Base.connection.close if ActiveRecord::Base.connected?
  puts "\nStopping PostgreSQL container..."
  $postgres.stop
  $postgres.remove
  puts "✓ Container stopped and removed"
end
