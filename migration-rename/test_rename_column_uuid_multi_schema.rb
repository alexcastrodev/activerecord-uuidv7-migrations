require_relative 'base'

# Define models for different schemas
class PublicProduct < ActiveRecord::Base
  self.table_name = 'public.products'
end

class TenantProduct < ActiveRecord::Base
  self.table_name = 'tenant.products'
end

begin
  puts "\n=== Step 0: Creating tenant schema ==="
  ActiveRecord::Base.connection.execute('CREATE SCHEMA IF NOT EXISTS tenant')
  puts "✓ Tenant schema created"

  puts "\n=== Step 1: Creating tables in both schemas ==="
  ActiveRecord::Schema.define do
    create_table 'public.products', force: true do |t|
      t.integer :product_id, null: false
      t.uuid :product_internal_id, default: -> { 'uuidv7()' }, index: { unique: true }
      t.integer :category_id, null: false
      t.uuid :category_internal_id, default: -> { 'uuidv7()' }, index: { unique: true }
      t.integer :supplier_id, null: false
      t.uuid :supplier_internal_id, default: -> { 'uuidv7()' }, index: { unique: true }
    end

    create_table 'tenant.products', force: true do |t|
      t.integer :product_id, null: false
      t.uuid :product_internal_id, default: -> { 'uuidv7()' }, index: { unique: true }
      t.integer :category_id, null: false
      t.uuid :category_internal_id, default: -> { 'uuidv7()' }, index: { unique: true }
      t.integer :supplier_id, null: false
      t.uuid :supplier_internal_id, default: -> { 'uuidv7()' }, index: { unique: true }
    end
  end
  puts "✓ Tables created in both schemas"

  puts "\n=== Step 2: Populating public.products with 10 records ==="
  10.times do |i|
    PublicProduct.create!(
      product_id: 1000 + i,
      category_id: 2000 + i,
      supplier_id: 3000 + i
    )
  end
  puts "✓ Inserted 10 records into public.products"

  puts "\n=== Step 3: Populating tenant.products with 10 records ==="
  10.times do |i|
    TenantProduct.create!(
      product_id: 5000 + i,
      category_id: 6000 + i,
      supplier_id: 7000 + i
    )
  end
  puts "✓ Inserted 10 records into tenant.products"

  puts "\n=== Step 4: Verifying data before migration ==="
  puts "\n  PUBLIC SCHEMA:"
  PublicProduct.limit(3).each do |product|
    puts "    ID: #{product.id}"
    puts "      product_id: #{product.product_id}, product_internal_id: #{product.product_internal_id}"
    puts "      category_id: #{product.category_id}, category_internal_id: #{product.category_internal_id}"
    puts "      supplier_id: #{product.supplier_id}, supplier_internal_id: #{product.supplier_internal_id}"
  end

  puts "\n  TENANT SCHEMA:"
  TenantProduct.limit(3).each do |product|
    puts "    ID: #{product.id}"
    puts "      product_id: #{product.product_id}, product_internal_id: #{product.product_internal_id}"
    puts "      category_id: #{product.category_id}, category_internal_id: #{product.category_internal_id}"
    puts "      supplier_id: #{product.supplier_id}, supplier_internal_id: #{product.supplier_internal_id}"
  end

  public_count_before = PublicProduct.count
  tenant_count_before = TenantProduct.count
  puts "\n  Total records: public=#{public_count_before}, tenant=#{tenant_count_before}"

  puts "\n=== Step 5: Migrating public.products schema in transaction ==="
  ActiveRecord::Base.transaction do
    # Drop old integer ID columns
    ActiveRecord::Base.connection.remove_column 'public.products', :product_id
    ActiveRecord::Base.connection.remove_column 'public.products', :category_id
    ActiveRecord::Base.connection.remove_column 'public.products', :supplier_id

    # Rename UUID columns to replace the old IDs
    ActiveRecord::Base.connection.rename_column 'public.products', :product_internal_id, :product_id
    ActiveRecord::Base.connection.rename_column 'public.products', :category_internal_id, :category_id
    ActiveRecord::Base.connection.rename_column 'public.products', :supplier_internal_id, :supplier_id
  end
  puts "✓ public.products migration completed"

  puts "\n=== Step 6: Migrating tenant.products schema in transaction ==="
  ActiveRecord::Base.transaction do
    # Drop old integer ID columns
    ActiveRecord::Base.connection.remove_column 'tenant.products', :product_id
    ActiveRecord::Base.connection.remove_column 'tenant.products', :category_id
    ActiveRecord::Base.connection.remove_column 'tenant.products', :supplier_id

    # Rename UUID columns to replace the old IDs
    ActiveRecord::Base.connection.rename_column 'tenant.products', :product_internal_id, :product_id
    ActiveRecord::Base.connection.rename_column 'tenant.products', :category_internal_id, :category_id
    ActiveRecord::Base.connection.rename_column 'tenant.products', :supplier_internal_id, :supplier_id
  end
  puts "✓ tenant.products migration completed"

  PublicProduct.reset_column_information
  TenantProduct.reset_column_information

  puts "\n=== Step 7: Verifying data after migration ==="
  puts "\n  PUBLIC SCHEMA:"
  PublicProduct.limit(3).each do |product|
    puts "    ID: #{product.id}"
    puts "      product_id (UUID): #{product.product_id}"
    puts "      category_id (UUID): #{product.category_id}"
    puts "      supplier_id (UUID): #{product.supplier_id}"
  end

  puts "\n  TENANT SCHEMA:"
  TenantProduct.limit(3).each do |product|
    puts "    ID: #{product.id}"
    puts "      product_id (UUID): #{product.product_id}"
    puts "      category_id (UUID): #{product.category_id}"
    puts "      supplier_id (UUID): #{product.supplier_id}"
  end

  puts "\n=== Step 8: Checking for empty values in both schemas ==="

  # Check public schema
  public_empty_product = PublicProduct.where(product_id: nil).count
  public_empty_category = PublicProduct.where(category_id: nil).count
  public_empty_supplier = PublicProduct.where(supplier_id: nil).count

  # Check tenant schema
  tenant_empty_product = TenantProduct.where(product_id: nil).count
  tenant_empty_category = TenantProduct.where(category_id: nil).count
  tenant_empty_supplier = TenantProduct.where(supplier_id: nil).count

  puts "\n  PUBLIC SCHEMA:"
  if public_empty_product == 0 && public_empty_category == 0 && public_empty_supplier == 0
    puts "    ✓ No empty values found! All #{public_count_before} records have valid UUIDs"
  else
    puts "    ✗ Found empty values:"
    puts "      - product_id: #{public_empty_product}" if public_empty_product > 0
    puts "      - category_id: #{public_empty_category}" if public_empty_category > 0
    puts "      - supplier_id: #{public_empty_supplier}" if public_empty_supplier > 0
  end

  puts "\n  TENANT SCHEMA:"
  if tenant_empty_product == 0 && tenant_empty_category == 0 && tenant_empty_supplier == 0
    puts "    ✓ No empty values found! All #{tenant_count_before} records have valid UUIDs"
  else
    puts "    ✗ Found empty values:"
    puts "      - product_id: #{tenant_empty_product}" if tenant_empty_product > 0
    puts "      - category_id: #{tenant_empty_category}" if tenant_empty_category > 0
    puts "      - supplier_id: #{tenant_empty_supplier}" if tenant_empty_supplier > 0
  end

  puts "\n=== Multi-schema migration completed successfully! ==="

ensure
  ActiveRecord::Base.connection.close if ActiveRecord::Base.connected?
  puts "\nStopping PostgreSQL container..."
  $postgres.stop
  $postgres.remove
  puts "✓ Container stopped and removed"
end
